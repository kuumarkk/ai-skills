---
name: flash-agent
description: Delegate mechanical, well-scoped DevSecOps coding and read-only auditing tasks to a fast, lightweight Gemini Flash subagent (`flash` or `flash_lite`) via `invoke_subagent` instead of burning primary model tokens/context. Use for running read-only static analysis (`terraform fmt`, `terraform validate`, `tflint`, `checkov`, `trivy`, `helm lint`, `kubeconform`), auditing modules for missing variable types/descriptions/default tags, summarizing large CloudWatch/kubectl/CI logs, or scaffolding standard Terraform/Terragrunt/Helm boilerplate. Do NOT use for architecture design, IAM/Zero-Trust security judgment, incident RCA, or any state-mutating commands.
---

# flash-agent (DevSecOps Subagent Delegation)

Offload **mechanical, self-contained, non-destructive** DevSecOps tasks to a fast Gemini model (`flash` or `flash_lite`) using Antigravity's `invoke_subagent` tool. This keeps the primary reasoning model's context window clean for cloud architecture, security review, and root-cause analysis.

## How to invoke

Use the `invoke_subagent` tool with one or more entries in the `Subagents` array:

- **Read-only auditing, log condensation & search tasks** → use `TypeName: "research"` with `Model: "flash"` (or `"flash_lite"` for simple file lookups):
  - Auditing `.tf` modules across directories for missing `type`, `description`, `sensitive = true`, or mandatory default tags (`Environment`, `Project`, `Owner`, `ManagedBy`, `SecurityTier`).
  - Scanning Kubernetes manifests for deprecated Karpenter APIs (`v1alpha5` / `v1beta1`), `:latest` image tags, or missing `securityContext` fields.
  - Condensing large `terraform plan` outputs, CloudWatch / `kubectl logs`, or CI/CD pipeline logs into structured failure summaries.
- **Boilerplate scaffolding & static validation tasks** → use `TypeName: "self"` with `Model: "flash"`:
  - Scaffolding standard Terraform module files (`main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `locals.tf`) or `terragrunt.hcl` wrappers from an explicit specification.
  - Running read-only formatters, linters, and scanners (`terraform fmt`, `terraform validate`, `tflint`, `checkov`, `trivy config`, `helm lint`, `kubeconform`) and reporting findings.
  - Updating pinned image digests or GitHub Action commit SHAs across workflow files.

### Parallel delegation

When auditing or updating 2+ independent modules, environments (`live/dev`, `live/staging`, `live/prod`), or Helm charts, pass multiple entries in a single `invoke_subagent` call so they run concurrently.

## Writing the task prompt (most important step)

A newly invoked subagent has **zero** context from your current conversation. Every `Prompt` must be completely standalone:

- **Absolute paths** for every target file or directory (`/Users/name/proj/live/prod/vpc/terragrunt.hcl`, not `terragrunt.hcl`).
- **Explicit DevSecOps rules & acceptance criteria** — specify `lower_snake_case` naming, pessimistic version constraints (`~>`), required validation commands (`terraform fmt && terraform validate`), and expected output format.
- **Explicit Safety Guardrail in every `self` prompt:** Always include:
  > *"Do NOT run any state-mutating or secret-exposing commands (`terraform apply`, `terraform destroy`, `kubectl apply/delete`, `helm upgrade/install`, `aws kms decrypt`, `aws secretsmanager get-secret-value`). Run only read-only validation commands."*

Bad: `clean up the variables in the rds module`
Good: `In /Users/name/infra/modules/aurora_postgresql/variables.tf, ensure every variable has an explicit 'type' and 'description', mark secret/password variables with 'sensitive = true', and use lower_snake_case. Do not change variable names already referenced in main.tf. Run 'terraform fmt' and 'terraform validate' in /Users/name/infra/modules/aurora_postgresql and report the output. Do NOT run terraform apply or destroy.`

## Reactive wakeup & verification

1. **Do NOT poll in a loop** after calling `invoke_subagent`. The system automatically wakes and notifies you when each subagent finishes.
2. **Verify the output yourself** — inspect the diff or scanner report returned by the `flash` subagent to confirm zero security regressions before presenting results to the user.

## When NOT to delegate

Never delegate cloud architecture design, IAM policy least-privilege scoping, KMS/network Zero-Trust design, production incident debugging, or any operation requiring the Mandatory Human-in-the-Loop Lock. Keep those in the primary agent.
