---
name: cicd-automation-diagrams
description: Build shift-left DevSecOps CI/CD pipelines (GitHub Actions, GitLab CI), macOS Apple Silicon (BSD)-compatible Bash/Zsh automation scripts, production Python 3.11+ AWS (`boto3`) automation, and Confluence Cloud-compatible Mermaid.js architecture diagrams. Trigger whenever creating or modifying CI/CD workflows, shell scripts, Python infra/security scripts, or architecture/network/IAM diagrams.
---

# CI/CD Shift-Left DevSecOps, Automation Scripting & Architecture Diagrams

Enforce shift-left security gates in CI/CD pipelines, defensive macOS-compatible shell and Python automation, and Confluence Cloud-safe Mermaid.js architecture diagrams.

## Language & Communication Stance

- **Language:** Respond in **Thai** for architectural discussions, explanations, and trade-offs. Keep all pipeline YAML, Bash/Python code, inline comments, commit messages, and diagram labels in **English**.
- **Tone:** Concise, direct, and technical. Focus immediately on implementation, supply-chain security, error handling, and operational reliability.

---

## 1. CI/CD Pipelines & Shift-Left DevSecOps

### Mandatory Automated Security Gates
Every infrastructure or application CI/CD workflow (GitHub Actions, GitLab CI) must integrate shift-left security checks before deployment or `terraform plan`/`apply`:

1. **Secret Scanning (Pre-commit & Pipeline):**
   - Run `gitleaks` or `trufflehog` with `--fail` on every PR and push to block leaked credentials or keys before merge.
2. **IaC Static Analysis & Policy-as-Code:**
   - Run `terraform fmt -check -recursive`, `terraform validate`, and `tflint` for syntax and provider rule validation.
   - Run `checkov` or `trivy config` (failing on `HIGH` / `CRITICAL` misconfigurations) prior to `terraform plan`.
3. **Container & Kubernetes Manifest Scanning:**
   - Run `trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed` on built container images before pushing to ECR.
   - Run `helm lint` and `kubeconform -strict` against rendered Kubernetes manifests.

### Pipeline Supply-Chain Hardening
- **Pin Third-Party Actions:** Pin all 3rd-party GitHub Actions to full immutable 40-character commit SHAs (with a trailing version comment, e.g., `uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2`) or verified immutable tags.
- **Least-Privilege Permissions:** Declare explicit top-level `permissions: {}` (or `contents: read`) and grant job-level permissions (`id-token: write` for AWS OIDC, `security-events: write` for SARIF uploads) only to the specific job that needs them.
- **OIDC Authentication:** Authenticate to AWS exclusively via `aws-actions/configure-aws-credentials` with `role-to-assume` (OIDC). Never store static AWS access keys in CI/CD variables.

---

## 2. Shell Scripting (Bash/Zsh on macOS Apple Silicon)

- **Strict Header:** Always begin shell scripts with:
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  ```
- **Defensive Quoting & Secret Masking:**
  - Quote all variable expansions (`"${VAR}"`).
  - Wrap any command handling tokens, secrets, or sensitive payloads with `set +x` (and restore only if trace was enabled) so secrets never leak to CI or terminal logs.
- **macOS (BSD) Apple Silicon Compatibility:**
  - Local developer scripts run on **macOS (BSD userland on Apple Silicon)**, whereas CI runners often run Linux (GNU coreutils).
  - Avoid GNU-only flags (`sed -i '...'`, `grep -P`, `date -d`, `base64 -w 0`, `readlink -f` on older BSD) or explicitly branch on `uname -s` / prefer portable POSIX equivalents (e.g., `awk`, `perl -pi -e`, Python one-liners, or checking for `gsed`/`gdate` in `/opt/homebrew/bin`).

---

## 3. Python Cloud Automation (Python 3.11+ & `boto3`)

When writing Python scripts for AWS automation, auditing, or DevSecOps tooling:

- **Typing & Structure:** Require Python 3.11+ syntax with explicit type hints (`from typing import Any`, built-in generic types `list[str]`, `dict[str, Any]`, `| None`).
- **Resilient `boto3` Clients:**
  - Always initialize `boto3` clients/sessions with `botocore.config.Config` using adaptive retries and explicit timeouts:
    ```python
    from botocore.config import Config
    from botocore.exceptions import BotoCoreError, ClientError

    AWS_CONFIG = Config(
        retries={"max_attempts": 10, "mode": "adaptive"},
        connect_timeout=5,
        read_timeout=30,
    )
    ```
  - Use paginators (`client.get_paginator(...)`) for all list/describe operations instead of single-page calls.
  - Catch `ClientError` and `BotoCoreError` explicitly and inspect `err.response["Error"]["Code"]`.
- **Observability:** Use Python's `logging` module (structured or formatted with timestamps and log levels) instead of raw `print()` statements.

---

## 4. Architecture Diagrams (Mermaid.js for Confluence Cloud)

- **Proactive Visuals:** Proactively illustrate VPC network flows, IAM/OIDC/Pod Identity trust chains, GitOps deployment flows, and CI/CD pipelines using **Mermaid.js** (`flowchart TD`, `flowchart LR`, or `sequenceDiagram`).
- **Confluence Cloud Rendering Rule (CRITICAL):**
  - Always wrap node labels containing special characters (`()`, `/`, `:`, `[]`, `-`, `.`) in **double quotes**.
  - Correct: `ALB["Public ALB (WAFv2 :443)"] --> EKS["EKS Private Nodes (Karpenter v1)"]`
  - Wrong: `ALB[Public ALB (WAFv2 :443)] --> EKS[EKS Private Nodes (Karpenter v1)]`
  - Avoid raw HTML tags (`<br/>`, `<b>`) inside node labels.
