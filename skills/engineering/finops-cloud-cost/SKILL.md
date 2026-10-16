---
name: finops-cloud-cost
description: Architect, audit, and enforce Cloud FinOps and cost optimization across AWS, Terraform/Terragrunt, and Amazon EKS/Karpenter v1+ without compromising Zero-Trust security or High Availability. Covers cost allocation tagging, S3/EBS/CloudWatch lifecycle policies, Graviton (arm64) & Spot diversification, Karpenter consolidation, NAT Gateway & cross-AZ data-transfer reduction, stateful right-sizing (Aurora I/O-Optimized, DynamoDB TTL, ElastiCache, MSK), Cost Anomaly Detection, and shift-left Infracost CI/CD gates. Trigger whenever analyzing cloud spend, reducing AWS/EKS bills, right-sizing workloads, designing cost-efficient architectures, or adding FinOps guardrails to Terraform/Kubernetes.
---

# Cloud FinOps & AWS / EKS Cost Optimization

Enforce "Cost-Aware by Design" across every AWS architecture, Terraform/Terragrunt module, and EKS/Karpenter manifest—eliminating waste and optimizing unit economics **without** degrading Zero-Trust security posture or production High Availability (HA).

## Language & Communication Stance

- **Language:** Use **English** by default for all cost analyses, architectural recommendations, HCL/YAML code, inline comments, and documentation for maximum token efficiency.
- **Tone:** Concise, direct, and quantitative. Prioritize findings by **estimated monthly savings ($ or %)**, **implementation effort**, and **blast radius / HA impact**.

---

## 1. Cost Visibility, Tagging & Governance (Inform Phase)

### Mandatory Cost Allocation Tags (Terraform & Kubernetes)
- **AWS Provider `default_tags`:** Every Terraform root module / Terragrunt root configuration must enforce:
  - `Environment` (`prod`, `staging`, `dev`)
  - `Project` / `Service`
  - `Owner` / `Team`
  - `CostCenter`
  - `ManagedBy = "Terraform"`
  - `SecurityTier`
- **EKS Split Cost Allocation & Kubecost / OpenCost Labels:** Every Kubernetes workload (`Deployment`, `StatefulSet`, `Job`, `CronJob`) and `Namespace` must carry standard labels (`app.kubernetes.io/name`, `app.kubernetes.io/part-of`, `team`, `cost-center`, `environment`) so shared EKS node and control-plane costs map accurately to owning teams.

### Automated Budgets & Anomaly Detection (IaC)
- **AWS Cost Anomaly Detection:** Provision `aws_ce_anomaly_monitor` (Dimensional `SERVICES` + Contextual `CUSTOM` per `CostCenter` tag) and `aws_ce_anomaly_subscription` routed to Slack (via AWS Chatbot / SNS) to catch runaway scaling or billing spikes within hours.
- **AWS Budgets:** Provision `aws_budgets_budget` with alerts at `50%`, `80%`, and `100%` of **ACTUAL** spend and `100%` of **FORECASTED** spend.

---

## 2. EKS & Karpenter v1+ Compute Optimization (Optimize Phase)

### Graviton (`arm64`) First
- Default stateless microservices, workers, and compatible stateful engines to **AWS Graviton3 / Graviton4** (`c7g`, `m7g`, `r7g`, `c8g`, `m8g`, `r8g`) for ~20–40% better price-performance over comparable `x86_64` instances.
- Build multi-arch container images (`linux/amd64,linux/arm64`) in CI/CD and allow both architectures or prefer `arm64` in Karpenter `NodePool` requirements.

### Karpenter v1+ (`karpenter.sh/v1`) Bin-Packing & Spot Strategy
- **Consolidation:** Set `disruption.consolidationPolicy: WhenEmptyOrUnderutilized` with an explicit `consolidateAfter` (e.g., `1m` for stateless workloads) and safe `disruption.budgets` (e.g., `nodes: "10%"`) paired with workload `PodDisruptionBudget`s so Karpenter continuously replaces fragmented nodes with cheaper, tightly packed instances.
- **Spot Diversification:**
  - Use `karpenter.sh/capacity-type: ["spot", "on-demand"]` (or dedicated Spot `NodePool`s with priority weight) for fault-tolerant, stateless, and batch workloads.
  - Specify **at least 5+ instance families** (`c`, `m`, `r` across generations `Gt "5"`) in `NodePool` requirements to avoid Spot capacity pool exhaustion and reduce interruption frequency.
  - Keep cluster-critical addons (CoreDNS, Karpenter controller, ESO, ingress controllers) and stateful workloads on **On-Demand** capacity backed by Compute Savings Plans.
- **Hard Ceiling Guardrails:** Always define `spec.limits` (`cpu` and `memory`) on every `NodePool` to cap blast radius from runaway HPA/KEDA scaling loops.

### Pod Right-Sizing (Eliminating Slack)
- Audit `resources.requests` against 14–30 day Prometheus p95/p99 actual utilization (`container_cpu_usage_seconds_total` and `container_memory_working_set_bytes`).
- Remember that **Karpenter schedules and provisions EC2 nodes based on `requests`, not actual usage**—over-requesting CPU/memory directly inflates EC2 spend.
- Enforce per-namespace `ResourceQuota` and `LimitRange` defaults to prevent unconfigured pods from claiming excessive node capacity.

---

## 3. Storage, Database & Stateful Service Optimization

### S3 Lifecycle Hardening (Mandatory on Every Bucket)
Pair `aws_s3_bucket_versioning` (`Enabled` for security/recovery) with a mandatory `aws_s3_bucket_lifecycle_configuration` to prevent unbounded storage growth:
1. **Abort Incomplete Multipart Uploads:** Always set `abort_incomplete_multipart_upload { days_after_initiation = 7 }`.
2. **Noncurrent Version Pruning:** Transition noncurrent versions to `STANDARD_IA` / `GLACIER_IR` after 30 days and expire (`noncurrent_version_expiration`) after 90–365 days (per compliance tier).
3. **Storage Class Tiering:**
   - Use `INTELLIGENT_TIERING` for datasets with unknown or shifting access patterns (>128 KB objects).
   - Transition immutable security/audit/ALB/VPC Flow Logs (`STANDARD` -> `STANDARD_IA` at 30d -> `GLACIER_IR` at 90d -> `DEEP_ARCHIVE` at 180d/365d).

### EBS Volumes & Snapshots
- **Enforce `gp3` Everywhere:** Never provision `gp2` or `io1`. Use `gp3` (20% lower base cost per GB than `gp2`, includes 3,000 IOPS and 125 MB/s free, with independent IOPS/throughput scaling) in Terraform and Karpenter `EC2NodeClass` `blockDeviceMappings`.
- **Orphaned Volume & Snapshot Cleanup:** Identify and remove unattached EBS volumes (`status = available`) and enforce snapshot retention schedules via AWS Data Lifecycle Manager (DLM).

### CloudWatch Logs & Observability Retention
- **Never Leave Log Groups on `Never Expire`:** Explicitly set `retention_in_days` on every `aws_cloudwatch_log_group` (e.g., `7` or `14` days for `dev`/`staging`, `30`–`90` days for `prod` hot search, with S3 Glacier export via Kinesis Data Firehose for long-term compliance archival).
- **Metric & Log Filtering:** Drop noisy health-check access logs (`/healthz`, `/readyz`, `/metrics`) before ingestion into CloudWatch Logs, Datadog, or Loki/AMP.

### Stateful Managed Services (Aurora, RDS, ElastiCache, MSK, DynamoDB)
- **Graviton Instance Families:** Standardize on `db.r7g.*` / `db.t4g.*` (RDS/Aurora), `cache.r7g.*` (ElastiCache), and `kafka.m7g.*` (MSK).
- **Aurora Storage Configuration:** Compare `standard` vs `aurora-iopt1` (I/O-Optimized); switch to `aurora-iopt1` only when billed I/O operations exceed ~25% of total Aurora cluster compute + storage spend.
- **DynamoDB Billing Mode & TTL:**
  - Enable `ttl` on ephemeral/session/event tables to purge expired records at **zero write cost**.
  - Use `PAY_PER_REQUEST` (On-Demand) for spiky, new, or unpredictable tables; switch to `PROVISIONED` with Auto Scaling when utilization is steady and predictable.

---

## 4. Network & Data Transfer Optimization (The Hidden Tax)

### Eliminate Avoidable NAT Gateway Data Processing Charges (`$0.045/GB`)
- **Mandatory Gateway VPC Endpoints (Free):** Always provision `aws_vpc_endpoint` of type `Gateway` for **S3** (`com.amazonaws.<region>.s3`) and **DynamoDB** (`com.amazonaws.<region>.dynamodb`) attached to all private route tables so image pulls (ECR S3 layers), S3 backups, and DynamoDB queries never traverse NAT Gateways.
- **Interface VPC Endpoints Break-Even Check:** Evaluate PrivateLink (`Interface` endpoints, ~$7.20/AZ/month + $0.01/GB) for high-throughput AWS services (`ecr.dkr`, `ecr.api`, `logs`, `sts`, `kms`, `secretsmanager`) whenever NAT Gateway data processing for that service exceeds ~160 GB/month per AZ.

### Cross-AZ Data Transfer Reduction (`$0.01/GB` Each Direction)
- **Topology-Aware Routing:** Preserve multi-AZ High Availability (`topologySpreadConstraints`) while minimizing cross-AZ traffic via Kubernetes **Topology Aware Routing** (`service.kubernetes.io/topology-mode: Auto`) where endpoints are evenly distributed and sufficient per AZ.
- **Stateful Locality:** Enable MSK/Kafka rack awareness (`client.rack` mapped to AZ), read from same-AZ ElastiCache/Aurora replicas where possible, and colocate chatty batch workers with their data sources.

### Edge Caching
- Offload static assets and cacheable read-heavy APIs through **Amazon CloudFront** (using Origin Shield and compression `gzip`/`brotli`) to reduce ALB LCU consumption and origin data egress costs.

---

## 5. Shift-Left FinOps in CI/CD & Rate Optimization (Operate Phase)

### Shift-Left Cost Gates (`infracost`)
- Integrate **Infracost** (`infracost breakdown` / `infracost diff`) into GitHub Actions / GitLab CI pull requests alongside `tflint` and `checkov` so engineers see the monthly cost delta and FinOps policy violations (e.g., missing `gp3`, missing S3 lifecycle, missing log retention) **before** merging.

### Non-Production Lifecycle & Right-Sizing Before Commitments
- **Ephemeral & Off-Hours Scaling:** Scale down non-production EKS workloads/Karpenter `NodePool`s, stop non-prod RDS/Aurora clusters outside business hours, and auto-destroy PR preview environments.
- **Sequence Before Committing:** Always execute **1) Delete Idle -> 2) Right-Size & Migrate to Graviton -> 3) Purchase Commitments**.
- **Savings Plans & RIs:** Prefer **Compute Savings Plans** (1-year No Upfront / Partial Upfront) for flexible coverage across EC2, Fargate, and Lambda (targeting 70–80% of steady-state hourly baseline), and Reserved Instances / Savings Plans for steady-state production RDS, ElastiCache, and OpenSearch clusters.

---

## 6. Execution Guardrails & Self-Verification Loop

1. **Autonomous Safe Execution:** Freely run read-only cost, inventory, and utilization commands:
   - `infracost breakdown --path .`
   - `aws ce get-cost-and-usage` / `aws ce get-cost-forecast` / `aws ce get-anomalies`
   - `aws compute-optimizer get-ec2-instance-recommendations` / `get-ebs-volume-recommendations`
   - `aws ec2 describe-volumes --filters Name=status,Values=available`
   - `aws ec2 describe-nat-gateways` / `aws ec2 describe-vpc-endpoints`
   - `kubectl top nodes` / `kubectl top pods -A`
   - `terraform fmt` / `terraform validate` / `helm lint` / `kubeconform`
2. **Mandatory Human-in-the-Loop Lock:** **NEVER** automatically execute state-mutating, destructive, or commitment-purchasing commands (`terraform apply`, `terraform destroy`, `kubectl apply/delete/scale`, `aws ec2 delete-volume`, `aws ec2 delete-snapshot`, `aws savingsplans create-savings-plan`, `aws rds modify-db-instance`) without explicit user confirmation in chat first.
3. **Self-Verification Loop:** After authoring or updating Terraform, Terragrunt, or Kubernetes/Karpenter files for FinOps optimization, automatically validate syntax (`terraform fmt`, `terraform validate`, `helm lint`, `kubeconform`) and verify that **zero security controls (encryption, IMDSv2, least privilege) or HA guarantees (multi-AZ, PDBs) were weakened**.
