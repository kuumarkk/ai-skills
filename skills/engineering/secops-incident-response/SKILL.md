---
name: secops-incident-response
description: Execute AWS and Amazon EKS security incident response, threat hunting, blast-radius containment, forensic preservation, and vulnerability/supply-chain triage (KEV/EPSS/reachability). Covers GuardDuty/CloudTrail/Falco investigation, compromised IAM access key/role session revocation (`AWSRevokeOlderSessions`), EKS pod forensic isolation via deny-all `NetworkPolicy` and EBS snapshots, and WAF emergency mitigations. Trigger on security incidents, GuardDuty/Falco alerts, leaked credentials, suspicious IAM/EKS API activity, or CVE/supply-chain triage.
---

# SecOps Incident Response, Threat Hunting & Vulnerability Triage

Execute disciplined, evidence-preserving security containment and threat hunting across AWS and Amazon EKS while strictly respecting the **Mandatory Human-in-the-Loop Lock** before executing any state-mutating containment action.

---

## 1. Golden Rule of Cloud & Kubernetes Forensics

**ISOLATE AND SNAPSHOT BEFORE TERMINATING.**
- Never `kubectl delete pod` or `aws ec2 terminate-instances` as your first move on a suspected compromise—doing so destroys volatile memory, container writable layers (`/tmp`, `/dev/shm`), and unshipped attacker artifacts.
- Follow the strict sequence: **1) Identify Blast Radius (Read-Only) → 2) Preserve Evidence → 3) Contain Identity & Network → 4) Eradicate & Rotate → 5) Post-Mortem**.

---

## 2. Threat Hunting & Blast-Radius Triage (Autonomous Read-Only)

Immediately run read-only queries to map the attacker's entry point, principal ARN, source IP/ASN, and lateral movement:

### AWS IAM / STS / CloudTrail Investigation
- **Trace Principal Activity:**
  - `aws cloudtrail lookup-events --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=<AKIA.../ASIA...>`
  - `aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=<session-name>`
- **High-Signal Persistence & Exfiltration Indicators to Check in CloudTrail:**
  - Identity persistence: `CreateAccessKey`, `CreateUser`, `CreateLoginProfile`, `UpdateAssumeRolePolicy` (adding external AWS accounts or OIDC subjects), `AttachRolePolicy` / `PutRolePolicy`.
  - Defense evasion: `StopLogging`, `DeleteTrail`, `UpdateTrail`, `DeleteDetector` (GuardDuty), `PutEventSelectors`.
  - Data & secret exfiltration: `GetSecretValue`, `GetParameter`, `Decrypt`, `CreateSnapshot`, `ModifySnapshotAttribute` (sharing EBS/RDS snapshots externally), anomalous S3 `GetObject`/`PutBucketPolicy`.
- **GuardDuty Findings Check:**
  - `aws guardduty list-findings --detector-id <id>` and `get-findings` (pay critical attention to `PrivilegeEscalation:IAMUser/*`, `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS`, and `Execution:Runtime/*` on EKS).

### Amazon EKS & Container Runtime Investigation
- Check Kubernetes audit logs and Falco/GuardDuty Runtime Monitoring alerts for:
  - Interactive shells (`kubectl exec`), unexpected binaries spawned by web/app processes (`sh`, `bash`, `curl`, `wget`, `nc`, `socat`, `xmrig`), reading `/var/run/secrets/kubernetes.io/serviceaccount/token` or `169.254.169.254` / `169.254.170.23` (EKS Pod Identity agent).
  - Cluster RBAC escalation (`ClusterRoleBinding` creation, `system:masters`, `secrets` `list`/`watch`, privileged pod or `hostPath`/`hostPID`/`hostNetwork` creation).

---

## 3. Containment Playbooks (Propose First — Requires Human Confirmation)

Present the exact containment commands and blast radius to the user and wait for confirmation before executing:

### Playbook A: Compromised IAM Role / Temporary STS Session (IRSA / Pod Identity / SSO / OIDC)
1. **Revoke all active temporary sessions issued before right now** by attaching an inline `AWSRevokeOlderSessions` policy to the IAM Role:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "RevokeOlderSessions",
         "Effect": "Deny",
         "Action": "*",
         "Resource": "*",
         "Condition": {
           "DateLessThan": {
             "aws:TokenIssueTime": "2026-10-17T00:00:00Z"
           }
         }
       }
     ]
   }
   ```
2. If the workload itself is actively exploited, attach an explicit `Deny *` inline policy or restrict the Role Trust Policy (`AssumeRolePolicyDocument`) to block new token minting until the workload is patched.

### Playbook B: Leaked Static IAM Access Key (`AKIA...`)
1. **Deactivate first (`Inactive`), do NOT delete immediately** (so you can confirm which legitimate services break and correlate CloudTrail logs):
   `aws iam update-access-key --user-name <user> --access-key-id <AKIA...> --status Inactive`
2. Attach an explicit `Deny *` policy to the user, audit all created resources/keys since compromise timestamp, and migrate the workload to OIDC / EKS Pod Identity so static keys are permanently eliminated.

### Playbook C: Compromised EKS Pod / Worker Node
1. **Quarantine the Pod via `NetworkPolicy` (Do NOT delete the pod yet):**
   - Relabel the compromised pod (`kubectl label pod <pod> -n <ns> quarantine=isolated --overwrite` — removes it from `Service` endpoints so user traffic stops routing to it while keeping the process alive for forensics).
   - Apply a default-deny ingress + egress `NetworkPolicy` matching `quarantine: isolated` to cut C2/exfiltration immediately.
2. **Capture Forensic Snapshot:**
   - Identify the underlying EC2 node (`kubectl get pod <pod> -n <ns> -o wide`), cordoning the node (`kubectl cordon <node>`) so Karpenter/scheduler places no new pods on it.
   - Trigger an EBS snapshot (`aws ec2 create-snapshot`) of the node's root/data volumes tagged `ForensicHold = true` for offline analysis.
   - Capture volatile state (`kubectl logs <pod> --all-containers`, `kubectl get pod <pod> -o yaml`, active network sockets).
3. **Eradicate:** Only after forensic capture is confirmed, delete the compromised pod/node and deploy the patched, immutable-digest image.

---

## 4. Vulnerability & Supply-Chain Triage (Risk-Based Prioritization)

Never treat every scanner finding equally. Prioritize CVEs (`trivy`, `grype`, AWS Inspector, GitHub Dependabot) using a 4-factor decision matrix:

1. **CISA KEV (Known Exploited Vulnerabilities) & EPSS (`> 0.10` / 10%):** Active exploitation in the wild takes immediate priority over theoretical high-CVSS bugs.
2. **Runtime Reachability & Package Usage:**
   - Is the vulnerable function actually imported and reachable on the network path, or is it an unused OS build tool (`curl`, `libsqlite`, `ncurses`) inside a base image?
   - Prefer migrating the Dockerfile to `distroless` / `chainguard` to eliminate 90%+ of OS-layer CVEs in a single move rather than chasing individual `apt-get upgrade` patches.
3. **Exposure & Compensating Controls:**
   - Internet-facing (`Public ALB` / `Ingress`) + unauthenticated = **P0 Emergency (< 24h)**.
   - Internal private subnet + mTLS / Security Group locked + `readOnlyRootFilesystem: true` + non-root = **Scheduled Sprint Remediation**.
4. **Virtual Patching:** When an upstream patch is not yet available for an exploited web/API vulnerability (e.g., Log4Shell, HTTP/2 Rapid Reset, path traversal), deploy an immediate **AWS WAFv2 Custom Rule / Managed Rule Group** at the CloudFront/ALB edge while engineering builds the permanent fix.
