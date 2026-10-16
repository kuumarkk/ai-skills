# ai-skills (Senior DevSecOps Edition)

Agent skills for **Google Antigravity** (`agy` CLI, **Antigravity IDE**, Antigravity 2.0) and **Gemini**, tailored for a **Senior DevSecOps Specialist & Cloud Infrastructure Architect**.

## Layout

Skills live under `skills/`, grouped into buckets:

- `engineering/` — daily DevSecOps, IaC (Terraform/Terragrunt), AWS Zero-Trust security, EKS/Karpenter/GitOps, CI/CD, and troubleshooting
- `productivity/` — leadership/incident communication and multi-step workflow discipline
- `misc/` — kept around but rarely used
- `personal/` — tied to my own setup, not promoted
- `in-progress/` — drafts not yet ready to ship
- `deprecated/` — no longer used

Each skill is its own directory containing a `SKILL.md` (with YAML frontmatter — `name` and `description`) and any bundled scripts or reference files.

Workspace discovery is configured in [`.agents/skills.json`](./.agents/skills.json) and global persona & safety guardrails are defined in [`GEMINI.md`](./GEMINI.md).

## Install

### Global Symlink (Antigravity, Antigravity IDE & Gemini)

Symlink every shippable skill into `~/.gemini/config/skills/` (Antigravity / Antigravity IDE) and `~/.gemini/skills/` (Gemini CLI):

```bash
./scripts/link-skills.sh
```

### List Skills

List every `SKILL.md` in the repo:

```bash
./scripts/list-skills.sh
```

## Reference

### Engineering

- **[iac-aws-security](./skills/engineering/iac-aws-security/SKILL.md)** — Production Terraform & Terragrunt standards (DRY modularity, defensive HCL, `for_each`, `validation`, `prevent_destroy`, default tags) and AWS CIS / Zero-Trust security (least-privilege IAM, EKS Pod Identity/IRSA, OIDC, KMS CMK rotation, S3 hardening, private networking, WAF/CloudFront).
- **[k8s-karpenter-gitops](./skills/engineering/k8s-karpenter-gitops/SKILL.md)** — EKS workload & container hardening (multi-stage distroless, Pod Security Standards Restricted/Baseline, ESO secrets, HA PDB & `topologySpreadConstraints`), Karpenter v1+ GA (`karpenter.sh/v1` `NodePool` & `karpenter.k8s.aws/v1` `EC2NodeClass` with IMDSv2 and encrypted `gp3`), and Helm/ArgoCD GitOps.
- **[cicd-automation-diagrams](./skills/engineering/cicd-automation-diagrams/SKILL.md)** — Shift-left DevSecOps CI/CD pipelines (`gitleaks`, `tflint`, `checkov`, `trivy`, `kubeconform`, SHA-pinned actions, OIDC), macOS Apple Silicon (BSD)-compatible Bash/Zsh scripts, Python 3.11+ `boto3` automation, and Confluence Cloud-safe Mermaid.js diagrams.
- **[debug-mantra](./skills/engineering/debug-mantra/SKILL.md)** — Four-mantra DevSecOps debugging discipline: reproduce safely → trace control-plane/audit telemetry & IaC knobs → falsify hypotheses with read-only checks → cross-reference every breadcrumb while respecting the Human-in-the-Loop lock.
- **[scrutinize](./skills/engineering/scrutinize/SKILL.md)** — Outsider-perspective end-to-end DevSecOps architecture and security review of Terraform/Terragrunt PRs, K8s/Karpenter manifests, and CI/CD pipelines against AWS CIS, Zero-Trust, HA, and state-safety standards.
- **[post-mortem](./skills/engineering/post-mortem/SKILL.md)** — Write the canonical DevSecOps engineering record of a resolved production incident, security remediation, or infrastructure bug — blast radius, failure chain (with Confluence Cloud Mermaid diagram), fix, validation, and shift-left prevention action items.
- **[flash-agent](./skills/engineering/flash-agent/SKILL.md)** — Delegate mechanical, non-destructive DevSecOps tasks (running read-only linters/scanners `tflint`/`checkov`/`trivy`/`helm lint`, tag/variable compliance audits, CloudWatch/pod log summarization, Terragrunt scaffolding) to a fast Gemini Flash subagent (`flash` / `flash_lite`) via `invoke_subagent`.

### Productivity

- **[management-talk](./skills/productivity/management-talk/SKILL.md)** — Translate deep DevSecOps incidents, AWS/EKS/Karpenter changes, security compliance posture, and cost/reliability updates for engineering leadership across JIRA, Slack, async standup, email, and meeting talking-points.
- **[stay-on-track](./skills/productivity/stay-on-track/SKILL.md)** — Keeps long multi-step DevSecOps tasks (multi-environment Terragrunt refactors, EKS/Karpenter upgrades, compliance audits) on-track with loop breaking, one-edit-one-validation, subagent offloading, and clean `handoff.md` artifacts.

### Misc

_(none yet)_
