---
name: debug-mantra
description: Four-mantra DevSecOps debugging discipline — reproduce safely, trace the infrastructure/control-plane fail path, falsify the hypothesis, cross-reference every breadcrumb. Recite the mantra block verbatim at the start of any debugging session, then apply the four steps in order before proposing any fix or state change. Trigger on /debug-mantra and proactively whenever troubleshooting starts — EKS/Karpenter scheduling or pod crashes, Terraform/Terragrunt plan/apply failures, IAM/OIDC/Pod Identity AccessDenied errors, AWS network/TLS/WAF drops, or CI/CD pipeline failures.
---

# Debug Mantra (DevSecOps Edition)

Four-step discipline for any infrastructure, Kubernetes, security, or CI/CD debugging session. Recite verbatim, then apply in order.

## Recite this — verbatim, as the first thing in your first response

> **Mantra:**
> 1. **First is reproducibility.** Can the issue be reproduced reliably?
> 2. **Know the fail path.** Control-plane telemetry first; then IaC/config trace + knob enumeration; then targeted diagnostic probes.
> 3. **Question your hypothesis.** What would disprove it?
> 4. **Every run is a breadcrumb.** Cross-reference all of them.

Then begin work in concise, technical **English**.

---

## 1. Reproduce reliably (and safely)

Build a deterministic, non-destructive reproducer before proposing any fix.

- **Reliable repro** → capture the exact read-only command, input manifest, or check that demonstrates the failure (`terraform plan`, `helm template`, `kubectl get events`, `curl -vk`, `aws sts/iam` simulation, CI job log).
- **Flaky / intermittent issue** (e.g., intermittent 502/504 on ALB, sporadic Spot/Karpenter eviction, DNS timeout) → correlate timestamps across ALB access logs, Envoy/CoreDNS logs, VPC Flow Logs, and Kubernetes node events before guessing.
- **No repro / missing visibility** → stop. State explicitly what telemetry is missing (CloudTrail event, pod logs, `terraform plan` output, Security Group ID) and run read-only `describe`/`get`/`logs` commands or ask the user for access. Do **not** guess fixes blindly.

**Safety Lock:** Never use `terraform apply`, `kubectl delete`, or `helm upgrade` in production just to "see what happens." Reproduce via `plan`, dry-run (`--dry-run=server`), or non-prod isolation first.

## 2. Know the fail path

Once reproducible, isolate *where* in the stack (Edge → Network → IAM → Node/Karpenter → Pod → Downstream AWS Service) the failure originates. Escalate in this order:

1. **Control-plane & audit telemetry first.** Inspect authoritative events before touching code:
   - **Kubernetes / EKS / Karpenter:** `kubectl describe pod/node/nodepool/ec2nodeclass`, `kubectl get events --sort-by='.lastTimestamp'`, `kubectl logs -n kube-system` (Karpenter, AWS LBC, CoreDNS, CNI), ArgoCD sync status.
   - **AWS & IAM:** CloudTrail (`lookup-events` for `AccessDenied` / `Client.UnauthorizedOperation`), IAM Policy Simulator, VPC Reachability Analyzer, WAF blocked requests, RDS/MSK events.
   - **Terraform / Terragrunt:** `terraform plan`, `terraform validate`, state inspection (`terraform state list/show`).
2. **IaC / Configuration trace + knob enumeration.** Trace the request or provisioning path end-to-end and enumerate every security/infra knob on that path:
   - IAM trust policy conditions (`sub`, `aud`, EKS Pod Identity association, IRSA service account name/namespace, KMS key policy + grants).
   - Network hops (CloudFront → WAF → ALB Listener → Target Group health check → Security Group ingress/egress → NACL → Route Table → Pod `containerPort`).
   - Kubernetes constraints (`securityContext` `readOnlyRootFilesystem`/`runAsNonRoot`, `resources.limits` OOMKilled, `topologySpreadConstraints`, taints/tolerations, `NodePool` requirements, PDB locks).
3. **Targeted diagnostic probes.** When passive telemetry isn't enough:
   - Run an ephemeral debug container (`kubectl debug` with `nicolaka/netshoot` or read-only curl/dig check), enable verbose CLI output (`TF_LOG=DEBUG`, `kubectl --v=8`), or inspect rendered manifests (`helm template --debug`).

## 3. Falsify the hypothesis

When a candidate root cause surfaces, scrutinise it **before** proposing an IaC or cluster change.

- Does it explain the exact error code / symptom end-to-end? Walk the chain.
- What is the fastest **read-only disproof**? (e.g., checking `aws ec2 describe-security-group-rules` to prove whether port 5432 is actually blocked before blaming the Security Group).
- Run the **disproof first**. Generate 3–5 ranked hypotheses across layers (IAM, Network, K8s scheduling, App config, State drift) rather than anchoring on the first plausible guess.

## 4. Every run is a breadcrumb

Maintain a running **ledger** of every check and observation in this session: what was inspected, what output returned, and what layer/hypothesis it ruled in or out.

- When a new hypothesis surfaces, verify it holds against **every** prior observation in the ledger.
- Design the **single read-only check** whose outcome disambiguates the remaining hypotheses.

---

## Operating rules

- Recite the mantra block **once** per debug session, verbatim, in your first response.
- Apply the four steps **in order**:
  - Do not propose a fix before #1 is satisfied (clear symptom/repro confirmed).
  - Do not modify `.tf` or K8s manifests before #2 has isolated the failing layer and knob.
  - Do not commit to a root cause before #3 has tried to disprove it with read-only checks.
  - Do not declare the root cause confirmed until #4 matches every prior breadcrumb.
- **Mandatory Human-in-the-Loop Lock:** Never execute state-mutating commands (`terraform apply/destroy`, `kubectl apply/delete/patch`, `helm upgrade/install`, `aws kms decrypt`, `aws secretsmanager get-secret-value`) without explicit user confirmation in chat.
