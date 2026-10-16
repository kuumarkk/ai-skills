---
name: post-mortem
description: Write the canonical DevSecOps engineering record of a resolved infrastructure incident, security finding remediation, or production bug — blast radius, root cause, mechanism, fix, validation, detection/CI-CD gap, and shift-left prevention items. Engineer-audience, AWS/Terraform/K8s identifiers and Confluence Cloud Mermaid diagrams welcome. Trigger on /post-mortem, when the user says "write the post-mortem / postmortem / RCA / root cause analysis", "document this incident/fix", "write up the root cause", or hands you a resolved and validated infra/security issue.
---

# Post-mortem & Incident RCA (DevSecOps Edition)

The canonical engineering record of a resolved production incident, infrastructure bug, or security remediation. Written **after** the fix/mitigation is validated, **for** DevSecOps/Platform engineers. Exact Terraform resource addresses, Kubernetes object names, IAM role ARNs, AWS error codes, and commit SHAs belong here.

For the executive / leadership version of this same incident, hand the finished post-mortem to [`management-talk`](../../productivity/management-talk/SKILL.md).

## Language & Communication Stance

- **Language:** Write prose explanations in **Thai** (unless the user explicitly requests an English-only document for external auditors/vendors). Keep all technical identifiers, resource names, log lines, commands, and Mermaid node labels in **English**.
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

> **Summary.** Checkout API (`checkout-svc`) บน `prod-ap-southeast-1` EKS cluster เกิด HTTP 503 เป็นเวลา 14 นาที (02:10–02:24 UTC) เนื่องจาก Karpenter ทำการ consolidate underutilized nodes พร้อมกันโดยที่ `checkout-svc` ไม่มี `PodDisruptionBudget` และ container image ดึง secret จาก AWS Secrets Manager ล้มเหลวตอนขยับไปรันบน `NodePool` ชุดใหม่ที่ไม่ได้ผูก EKS Pod Identity Agent DaemonSet priority. แก้ไขโดยการเพิ่ม `PodDisruptionBudget`, กำหนด `disruption.budgets` บน `NodePool`, และปรับ `priorityClassName: system-node-critical` ให้ `eks-pod-identity-agent`. Incident: INC-4092, PR `infra-gitops#812`, Owner: Somchai (Platform DevSecOps).
>
> **Blast Radius & Symptom.**
> - **Affected:** `checkout-svc` (production, `ap-southeast-1`), 38% ของ checkout requests ได้รับ `503 Service Temporarily Unavailable` จาก ALB (`arn:aws:elasticloadbalancing:...:loadbalancer/app/prod-public-alb/...`).
> - **Symptom:** Pods ใหม่ติดสถานะ `CreateContainerConfigError` จาก `ExternalSecret` sync error (`AccessDeniedException: User: arn:aws:sts::...:assumed-role/karpenter-node-role/... is not authorized to perform: secretsmanager:GetSecretValue`) เนื่องจาก traffic หลุดไปใช้ Node IAM Role แทน Pod Identity Role ขณะที่ `eks-pod-identity-agent` DaemonSet ยังไม่ `Ready` บน Node ใหม่.
>
> **Root Cause & Failure Chain.**
> 1. `NodePool` `general-spot` (`karpenter.sh/v1`) ตั้งค่า `consolidationPolicy: WhenEmptyOrUnderutilized` โดยไม่ได้ระบุ `disruption.budgets` (ค่าเริ่มต้นอนุญาตให้ disrupt ได้ 10% แต่เมื่อรวมกับ empty nodes ทำให้ drain 3 nodes ที่มี `checkout-svc` พร้อมกัน).
> 2. `checkout-svc` Helm release ไม่ได้เปิด `pdb.enabled: true` และไม่มี `topologySpreadConstraints` ทำให้ทั้ง 4 replicas ถูก evict พร้อมกัน.
> 3. บน Node ใหม่ที่ Karpenter provision ขึ้นมา Application pods ถูก schedule ทันทีพร้อมกับ `eks-pod-identity-agent` DaemonSet ส่งผลให้ช่วง 8 วินาทีแรก SDK fallback ไปหา IMDS / Node Role และถูกปฏิเสธด้วย Zero-Trust IAM policy.
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
> - **Immediate mitigation (02:21 UTC):** Paused Karpenter consolidation ชั่วคราวโดยตั้ง `disruption.budgets: [{ nodes: "0" }]` และ restart `checkout-svc` pods หลัง `eks-pod-identity-agent` พร้อมใช้งาน.
> - **Permanent Fix (PR `infra-gitops#812` & `terraform-live#1405`):**
>   1. เปิดใช้งาน `PodDisruptionBudget` (`minAvailable: "75%"`) และ `topologySpreadConstraints` (`topology.kubernetes.io/zone` & `kubernetes.io/hostname`, `maxSkew: 1`) ใน `checkout-svc` Helm values.
>   2. กำหนด `disruption.budgets` บน `karpenter.sh/v1` `NodePool` จำกัด `nodes: "10%"` และบล็อกการ consolidate ช่วง peak traffic.
>   3. เพิ่ม node readiness gate / taint สำหรับ critical CNI & Pod Identity daemonsets ก่อนรับ application workloads.
>
> **Validation.**
> - ตรวจสอบด้วย `helm lint` และ `kubeconform -strict` บน `infra-gitops#812` ผ่านทั้งหมด.
> - ทดสอบจำลอง `kubectl drain` บน `staging-ap-southeast-1`: `PodDisruptionBudget` บล็อกการ evict เกิน 1 pod ต่อครั้ง และ `checkout-svc` รักษา zero-dropped requests ตลอด 30 นาทีของ load test.
>
> **Action Items.**
> - เพิ่ม Kyverno / Checkov policy บังคับให้ทุก production `Deployment` (`replicas >= 2`) ต้องมี `PodDisruptionBudget` และ `topologySpreadConstraints`. (Owner: Somchai, DEVSEC-1102)
> - เพิ่ม CI check ตรวจสอบว่าทุก `karpenter.sh/v1` `NodePool` ต้องระบุ `disruption.budgets` และ `limits` เสมอ. (Owner: Somchai, DEVSEC-1103)

## Rules

- **Refuse to draft without all four required inputs.**
- **Never invent root causes, metrics, commit SHAs, or validation results.** Ask if facts are missing.
- **Keep exact AWS/Terraform/K8s identifiers** in the engineering post-mortem.
- **Always quote Mermaid node labels containing special characters** (`["..."]`) for Confluence Cloud compatibility.
- **Blameless.** Focus on shift-left policy gaps, architectural constraints, and automated guardrails.
