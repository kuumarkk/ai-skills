---
name: zero-downtime-migrations-dr
description: Plan, verify, and execute zero-downtime production upgrades, stateful migrations, Terraform state surgery (`moved`/`import`/`removed`), and Disaster Recovery (DR) drills on AWS and Amazon EKS. Covers EKS & Karpenter version upgrade sequencing, Aurora PostgreSQL/RDS Blue-Green & KMS encryption migrations, DNS weighted cutovers, and AWS Backup Vault Lock (WORM) + Velero restore validation. Trigger whenever planning or executing EKS upgrades, database migrations, Terraform state splitting/refactoring, multi-region DR, or production cutover runbooks.
---

# Zero-Downtime Upgrades, Stateful Migrations & Disaster Recovery

Design every infrastructure upgrade, state refactor, and database migration so that **blast radius is bounded**, **rollback takes `< 5 minutes`**, and **zero customer requests are dropped**.

---

## 1. Amazon EKS & Karpenter Zero-Downtime Upgrade Runbook

Never jump multiple EKS minor versions in a single step, and never upgrade worker nodes before the control plane and core add-ons.

### Strict Pre-Flight Checks (Autonomous Read-Only)
1. **Deprecated API Audit:** Run `kubent` (Kube No Trouble) or `pluto` against live cluster manifests and Helm releases (`helm list -A`) to verify zero removed Kubernetes API versions exist for the target EKS version.
2. **PDB Deadlock Audit (CRITICAL):**
   - Inspect `kubectl get pdb -A`: any `PodDisruptionBudget` with `ALLOWED DISRUPTIONS == 0` (`minAvailable: 100%` or `maxUnavailable: 0`, or `replicas: 1` with `minAvailable: 1`) **will block Karpenter node drainage and EKS upgrades indefinitely**. Fix blocking PDBs before starting.
3. **IP Address Exhaustion Check:** Verify private subnet `AvailableIpAddressCount` (`aws ec2 describe-subnets`) has sufficient headroom for surge/replacement nodes during rolling replacement.

### Strict Upgrade Execution Order
1. **EKS Control Plane** (1 minor version at a time).
2. **EKS Core Add-ons (Strict Sequence):**
   - `vpc-cni` → `coredns` → `kube-proxy` → `eks-pod-identity-agent` → `aws-ebs-csi-driver`.
   - Always check the AWS EKS Add-on compatibility matrix for the target K8s version and preserve custom configuration values (`configuration_values` in Terraform) so `WARM_PREFIX_TARGET` or CoreDNS custom forwarders are not wiped.
3. **Karpenter Controller:** Upgrade the Karpenter Helm chart (`oci://public.ecr.aws/karpenter/karpenter`) and CRDs (`karpenter.sh/v1`, `karpenter.k8s.aws/v1`) matching the EKS minor version.
4. **Worker Node Rolling Replacement (Automatic via Karpenter Drift):**
   - Updating `amiSelectorTerms` (or when `alias: al2023@latest` resolves to the new EKS-optimized AMI) marks existing `NodeClaim`s as `Drifted`.
   - Ensure `NodePool.spec.disruption.budgets` throttles drift replacement (e.g., `nodes: "10%"`) so nodes roll gradually while respecting workload `PodDisruptionBudget`s and `topologySpreadConstraints`.

---

## 2. Terraform & Terragrunt Declarative State Surgery

Avoid imperative `terraform state mv` / `terraform state rm` CLI commands in production—they bypass PR code review, leave no Git audit trail, and break concurrent CI plans.

### Declarative Refactoring Patterns (Terraform 1.5+ / 1.7+)
- **Renaming Resources or Moving into Modules (`moved` block):**
  ```hcl
  moved {
    from = aws_security_group.redis
    to   = module.elasticache_redis.aws_security_group.this[0]
  }
  ```
- **Adopting Existing AWS Resources (`import` block):**
  ```hcl
  import {
    to = aws_s3_bucket.audit_logs
    id = "prod-secops-audit-logs-123456789012"
  }
  ```
  Run `terraform plan -generate-config-out=generated.tf` only in scratch/local review, harden the HCL to match module standards, and verify `terraform plan` shows **`0 to add, 0 to change, 0 to destroy`** before merge.
- **Orphaning / Handing Off a Resource to Another State (`removed` block):**
  ```hcl
  removed {
    from = aws_db_cluster_snapshot.legacy_final
    lifecycle {
      destroy = false
    }
  }
  ```
  - Step 1: Add `removed { lifecycle { destroy = false } }` in Source State A and `import {}` in Target State B.
  - Step 2: Verify **both** `terraform plan` outputs show **`0 to destroy`** before applying.

---

## 3. Stateful Database & DNS Zero-Downtime Cutovers

### Aurora PostgreSQL / RDS Major Version or Schema/KMS Cutover
- **Preferred Pattern — AWS RDS Blue/Green Deployments:**
  1. Provision Blue/Green deployment (creates a logically replicated Green staging environment with target engine version, parameter group, and storage settings).
  2. Run read-only validation and performance benchmarks against Green endpoints.
  3. Verify replication lag is `< 100ms` and no long-running transactions/DDL locks are active on Blue.
  4. Execute managed switchover during low-traffic window (typical stall `5–30 seconds`; applications using AWS Advanced JDBC Wrapper or RDS Proxy reconnect sub-second).
  5. **Keep Blue alive (read-only/stopped) for 24–72h** as an instant rollback target before deleting.

### DNS / Edge Traffic Cutovers (Route 53 / CloudFront / ALB)
1. **Step Down TTL 24h Before Cutover:** Lower Route 53 record TTL from `300s`/`3600s` down to `60s` at least 24 hours prior to migration.
2. **Weighted Canary Ramp:** Shift traffic incrementally (`1%` → `10%` → `50%` → `100%`) using Route 53 Weighted Routing or ALB Weighted Target Groups while watching 5xx error rates and p99 latency burn rates.
3. **Instant Rollback Criterion:** Pre-define the exact abort threshold in the runbook (e.g., *"If 5xx rate exceeds 0.5% for 2 consecutive minutes, set new target weight to `0` immediately"*).

---

## 4. Ransomware-Resilient Backups & DR Validation

Backups do not exist until a restore drill has been proven inside the target RTO/RPO.

- **Immutable Backups (WORM):** Protect production RDS/Aurora, EBS, EFS, and S3 backups using **AWS Backup Vault Lock in Compliance Mode** (`min_retention_days`, `max_retention_days`, `changeable_for_days = 3`) in a dedicated, logically isolated **Backup / DR AWS Account** (via AWS Organizations Cross-Account Backup) so even a compromised root/admin principal in the workload account cannot delete backups.
- **EKS Cluster State Recovery (GitOps + Velero):**
  - Treat EKS clusters as cattle reconstructed via **Terraform + ArgoCD App-of-Apps** (stateless manifests rehydrated from Git in `< 15m`), paired with **Velero** (authenticated via EKS Pod Identity to an encrypted S3 bucket) for `PersistentVolumeClaim` snapshots and dynamic cluster-scoped state.
- **Every Migration / DR Runbook Must Document 4 Tables:**
  1. **Pre-Flight Readiness Gates** (exact read-only verification commands + expected outputs).
  2. **Step-by-Step Execution Sequence** (with T-minus timestamps and owner).
  3. **Success Validation Checks** (SLI/SLO queries, synthetic transactions).
  4. **Explicit Point-of-No-Return & Rollback Procedure** (exact commands to revert within `< 5m`).
