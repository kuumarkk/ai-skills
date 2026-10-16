---
name: post-mortem
description: Write the canonical DevSecOps engineering record of a resolved infrastructure incident, security finding remediation, or production bug — blast radius, root cause, mechanism, fix, validation, detection/CI-CD gap, and shift-left prevention items. Engineer-audience, AWS/Terraform/K8s identifiers and Confluence Cloud Mermaid diagrams welcome. Trigger on /post-mortem, when the user says "write the post-mortem / postmortem / RCA / root cause analysis", "document this incident/fix", "write up the root cause", or hands you a resolved and validated infra/security issue.
---

# Post-mortem & Incident RCA (DevSecOps Edition)

The canonical engineering record of a resolved production incident, infrastructure bug, or security remediation. Written **after** the fix/mitigation is validated, **for** DevSecOps/Platform engineers. Exact Terraform resource addresses, Kubernetes object names, IAM role ARNs, AWS error codes, and commit SHAs belong here.

For the executive / leadership version of this same incident, hand the finished post-mortem to [`management-talk`](../../productivity/management-talk/SKILL.md).

## Language & Communication Stance

- **Language:** Write in concise, technical **English** by default for maximum token efficiency and greppability across engineering tickets and documentation.
- **Tone:** Blameless, direct, mechanism-first, zero hedging.

## When NOT to use

- **Incident still active or fix unvalidated.** Refuse to draft until the bleeding is stopped, root cause is proven, and the fix is validated. List which required inputs are missing and stop.
- **Trivial typo / non-operational change.** The PR description is sufficient.

## Required inputs — refuse to draft without these

Confirm all four before drafting. If any are missing, list what is missing and stop:

- [ ] **Deterministic repro or authoritative telemetry** exists (CloudTrail event, ALB/WAF log, `kubectl events`, `terraform plan` diff, Prometheus/CloudWatch metric spike).
- [ ] **Root cause mechanism is proven** (not a speculation).
- [ ] **Fix / remediation is identified** (PR, commit SHA, Terraform state/module change, ArgoCD revision).
- [ ] **Fix is validated** (workload healthy, `terraform plan` clean, security scan passing, synthetic/canary check green).

## Structure

Use these sections in order. **Summary, Blast Radius & Impact, Root Cause, Fix, and Validation are mandatory.**

### 1. Summary _(mandatory)_
One paragraph: what failed or was exposed, customer/workload blast radius, duration, root cause in one sentence, and what resolved it. Include JIRA/Incident key, PR number, and owner.

### 2. Blast Radius, Impact & Symptom _(mandatory)_
- Affected environment(s), AWS account/region, EKS cluster, and services.
- Exact symptom observed: HTTP 5xx rate, pod crash/pending state, `AccessDenied` error code, latency spike, or failed pipeline gate.

### 3. Root Cause & Failure Chain _(mandatory)_
Walk the exact technical mechanism end-to-end using concrete identifiers (`module.eks_karpenter`, `karpenter.sh/v1` `NodePool`, `aws_iam_role_policy`, Security Group IDs, commit SHAs).
Include a **Confluence Cloud-compatible Mermaid diagram** (all labels containing `()`, `/`, `:`, `[]`, `-` wrapped in double quotes `["..."]`) when illustrating a multi-hop failure chain (e.g., IAM trust mismatch, network drop, or ArgoCD/Karpenter race).

### 4. Fix & Remediation _(mandatory)_
- Immediate mitigation (rollback, WAF rule, PDB adjustment, scaling override) vs. permanent IaC/GitOps fix (PR/commit).
- Explain **why** the permanent change eliminates the root cause class rather than masking the symptom.

### 5. How it was diagnosed
Short debugging path (pulling from the `debug-mantra` breadcrumb ledger):
- Which telemetry source isolated the layer (CloudTrail, `kubectl get events`, VPC Flow Logs, `terraform plan`).
- Hypotheses ruled out and the single check that proved the root cause.

### 6. Why it slipped through (Shift-Left & Detection Gap)
Identify the systemic gap (**blameless** — never name individuals as the cause):
- **CI/CD Shift-Left Gap:** Missing `checkov` / `tflint` / `kubeconform` / `trivy` / `gitleaks` policy check.
- **Environment Drift / Parity Gap:** Staging `live/staging` differed from `live/prod` in Terragrunt inputs or workload traffic shape.
- **Observability / Alerting Gap:** Missing CloudWatch, Prometheus, or GuardDuty alert before customer impact.

### 7. Validation _(mandatory)_
Concrete proof that the fix works and did not introduce regressions:
- `terraform plan` shows zero unexpected changes; `tflint` and `checkov` pass.
- Kubernetes rollout status, pod health probes, and Karpenter node provisioning verified.
- Canary / synthetic workload test results and observation window duration.

### 8. Action Items (Shift-Left Prevention)
Concrete follow-ups with **What + Owner + Tracking Ticket**:
- Policy-as-Code / CI gate added (`checkov` custom policy, `kubeconform` schema check, OPA/Kyverno rule).
- Module hardening (`validation` block, `prevent_destroy`, `PodDisruptionBudget`, `disruption.budgets`).
- Alerting / runbook update.

---

## Worked example — EKS Checkout Service Outage during Karpenter Consolidation (INC-4092)

> **Summary.** Checkout API (`checkout-svc`) on the `prod-ap-southeast-1` EKS cluster returned HTTP 503 for 14 minutes (02:10–02:24 UTC) when Karpenter consolidated three underutilized nodes simultaneously. `checkout-svc` had no `PodDisruptionBudget`, and replacement pods on newly provisioned nodes failed AWS Secrets Manager authentication because application containers started before the `eks-pod-identity-agent` DaemonSet became `Ready`. Fixed by enabling `PodDisruptionBudget` and `topologySpreadConstraints`, setting explicit `disruption.budgets` on the `NodePool`, and enforcing node readiness ordering for `eks-pod-identity-agent`. Incident: INC-4092, PR `infra-gitops#812`, Owner: Alex (Platform DevSecOps).
>
> **Blast Radius & Symptom.**
> - **Affected:** `checkout-svc` (production, `ap-southeast-1`); 38% of checkout requests returned `503 Service Temporarily Unavailable` at the public ALB (`arn:aws:elasticloadbalancing:...:loadbalancer/app/prod-public-alb/...`).
> - **Symptom:** Replacement pods stalled in `CreateContainerConfigError` due to `ExternalSecret` sync failures (`AccessDeniedException: User: arn:aws:sts::...:assumed-role/karpenter-node-role/... is not authorized to perform: secretsmanager:GetSecretValue`) as SDK calls fell back to the EC2 Node IAM Role before Pod Identity was initialized on the new node.
>
> **Root Cause & Failure Chain.**
> 1. `NodePool` `general-spot` (`karpenter.sh/v1`) used `consolidationPolicy: WhenEmptyOrUnderutilized` without a restrictive `disruption.budgets` ceiling, draining 3 nodes hosting `checkout-svc` simultaneously during a low-traffic window.
> 2. `checkout-svc` Helm values had `pdb.enabled: false` and no `topologySpreadConstraints`, allowing all 4 replicas to be evicted concurrently.
> 3. On the newly launched `EC2NodeClass` instance, application pods were scheduled concurrently with `eks-pod-identity-agent`; during the 8-second window before the agent bound its link-local socket, secret fetches fell back to IMDSv2 / Node IAM Role and were blocked by Zero-Trust IAM policy.
>
> ```mermaid
> flowchart LR
>   KP["Karpenter v1 (NodePool: general-spot)"] -->|"Consolidate 3 Nodes (No PDB)"| EVICT["Evict All 4 checkout-svc Replicas"]
>   EVICT --> NEW["Provision New EC2NodeClass (al2023)"]
>   NEW --> RACE["App Pod Starts Before eks-pod-identity-agent Ready"]
>   RACE --> IAM["Fallback to Node Role -> SecretsManager AccessDenied"]
>   IAM --> ALB["Public ALB Returns HTTP 503 (14 mins)"]
> ```
>
> **Fix & Remediation.**
> - **Immediate mitigation (02:21 UTC):** Paused Karpenter consolidation via `disruption.budgets: [{ nodes: "0" }]` and triggered a rolling restart of `checkout-svc` once `eks-pod-identity-agent` was healthy on all nodes.
> - **Permanent Fix (PR `infra-gitops#812` & `terraform-live#1405`):**
>   1. Enabled `PodDisruptionBudget` (`minAvailable: "75%"`) and `topologySpreadConstraints` (`topology.kubernetes.io/zone` & `kubernetes.io/hostname`, `maxSkew: 1`) in `checkout-svc` Helm values.
>   2. Configured `disruption.budgets` on `karpenter.sh/v1` `NodePool` capping concurrent disruptions at `nodes: "10%"` and blocking consolidation during peak traffic windows.
>   3. Added startup readiness ordering so critical CNI and `eks-pod-identity-agent` DaemonSets initialize before application pods start on new nodes.
>
> **Validation.**
> - `helm lint` and `kubeconform -strict` passed on `infra-gitops#812`.
> - Simulated concurrent `kubectl drain` on `staging-ap-southeast-1`: `PodDisruptionBudget` restricted evictions to 1 pod at a time, maintaining zero dropped requests across a 30-minute load test.
>
> **Action Items.**
> - Add Kyverno / Checkov policy requiring `PodDisruptionBudget` and `topologySpreadConstraints` on all production `Deployment` workloads with `replicas >= 2`. (Owner: Alex, DEVSEC-1102)
> - Add CI check enforcing explicit `disruption.budgets` and resource `limits` on every `karpenter.sh/v1` `NodePool`. (Owner: Alex, DEVSEC-1103)

## Rules

- **Refuse to draft without all four required inputs.**
- **Never invent root causes, metrics, commit SHAs, or validation results.** Ask if facts are missing.
- **Keep exact AWS/Terraform/K8s identifiers** in the engineering post-mortem.
- **Always quote Mermaid node labels containing special characters** (`["..."]`) for Confluence Cloud compatibility.
- **Blameless.** Focus on shift-left policy gaps, architectural constraints, and automated guardrails.
