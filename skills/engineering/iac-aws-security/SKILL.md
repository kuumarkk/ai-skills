---
name: iac-aws-security
description: Author, refactor, and review production-grade Terraform and Terragrunt infrastructure on AWS enforcing DRY modularity, defensive HCL coding, AWS CIS benchmarks, and Zero-Trust security (least-privilege IAM, EKS Pod Identity/IRSA, OIDC, KMS CMK rotation, S3 hardening, private networking, WAF/CloudFront). Trigger whenever writing, modifying, or reviewing `.tf` or `terragrunt.hcl` files, designing AWS cloud architecture, configuring IAM policies, KMS, S3, VPCs, Security Groups, or stateful AWS services (Aurora, MSK, ElastiCache, DynamoDB).
---

# IaC (Terraform & Terragrunt) & AWS Zero-Trust Security

Enforce "Secure-by-Design", High Availability, DRY modularity, and Production Readiness across every Terraform module, Terragrunt configuration, and AWS architectural design.

## Language & Communication Stance

- **Language:** Use **English** by default for all discussions, explanations, HCL code, inline comments, commit messages, resource names, and documentation for maximum token efficiency.
- **Tone:** Concise, direct, and technical. Skip basic definitions and introductory fluff. Focus immediately on implementation, blast radius, state safety, and security posture.

---

## 1. IaC Standards (Terraform & Terragrunt)

### Structure & Modularity
- **DRY Separation:** Use Terragrunt (`terragrunt.hcl`) to strictly separate environment-specific live state trees (`live/<env>/<region>/<service>/`) from reusable, versioned modules (`modules/<domain>/`).
- **Standard Module Layout:** Every Terraform module must organize resources across:
  - `main.tf` — primary resource declarations
  - `variables.tf` — input variables with explicit `type`, `description`, and `validation`
  - `outputs.tf` — exported attributes with descriptions (`sensitive = true` where applicable)
  - `versions.tf` — `required_version` and `required_providers` with pessimistic constraints
  - `locals.tf` — computed values, tag merging, and naming prefixes
- **Naming Convention:**
  - Use `lower_snake_case` exclusively for all resource identifiers, data sources, variables, locals, and outputs.
  - **Never repeat the resource type** in the resource logical name:
    - Correct: `resource "aws_s3_bucket" "audit_logs"`
    - Wrong: `resource "aws_s3_bucket" "s3_bucket_audit_logs"`

### Defensive HCL Coding
- **Version Pinning:** Pin Terraform and provider/module versions in `versions.tf` using pessimistic constraints (`~>`).
- **Index Stability:** Prefer `for_each` with static map keys (`toset()` or explicit `map(object(...))`) over `count` to prevent unintended resource destruction/recreation when list elements shift.
- **Safe Traversal:** Use `try()` and `can()` when traversing optional nested objects or dynamic maps.
- **Strict Variable Contracts:**
  - Every `variable` MUST declare an explicit `type` and `description`.
  - Add `validation` blocks for critical inputs (CIDR blocks via ` can(cidrhost(var.cidr, 0))`, allowed environment tiers, instance families, KMS key ARNs).
  - Mark secrets, tokens, passwords, and sensitive outputs with `sensitive = true`.
- **Dynamic Context Resolution:**
  - Never hardcode AWS Account IDs, regions, partition names, or credentials.
  - Resolve dynamically via `data "aws_caller_identity" "current" {}`, `data "aws_region" "current" {}`, and `data "aws_partition" "current" {}`, or inject via Terragrunt inputs.
- **Stateful Protection:** Set `lifecycle { prevent_destroy = true }` on critical stateful resources:
  - Aurora / RDS clusters and instances
  - S3 Terraform state and security audit buckets
  - KMS Customer Managed Keys (CMKs)
  - DynamoDB tables (including state-lock tables)
- **Mandatory Default Tags:** Enforce provider `default_tags` or module-level tag merging containing:
  - `Environment`
  - `Project`
  - `Owner`
  - `ManagedBy = "Terraform"`
  - `SecurityTier`

---

## 2. Cloud & Infrastructure Security (AWS CIS & Zero-Trust)

### IAM & Identity (Least Privilege)
- **Strict Least Privilege:** Scope every IAM statement to the exact required actions and resource ARNs. Avoid `"Action": "*"` or `"Resource": "*"` unless an AWS API strictly requires wildcard resources (e.g., certain `ec2:Describe*` or `kms:` actions)—when required, document the exact justification in an inline comment above the statement.
- **Short-Lived Credentials Only:**
  - Kubernetes workloads: Use **EKS Pod Identity** (`aws_eks_pod_identity_association`, preferred) or **IRSA** (IAM Roles for Service Accounts) with strict condition keys (`StringEquals` on namespace and service account).
  - CI/CD pipelines: Use **IAM OIDC Identity Providers** (`token.actions.githubusercontent.com` / GitLab OIDC) with scoped `sub` / `aud` conditions.
  - **Never** provision IAM users with static `aws_iam_access_key` (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) for workloads or pipelines.

### Data Protection & Encryption
- **Encryption at Rest:** Enable KMS Customer Managed Keys (CMKs) with `enable_key_rotation = true` across all stateful services:
  - Aurora PostgreSQL / RDS (`storage_encrypted = true`, `kms_key_id`)
  - Amazon MSK (encryption at rest + TLS in transit)
  - ElastiCache for Redis (`at_rest_encryption_enabled = true`, `transit_encryption_enabled = true`)
  - S3, EBS volumes, EFS file systems, SQS queues, SNS topics, CloudWatch Log Groups.
- **Encryption in Transit:** Enforce TLS 1.2+ minimum across all listeners, databases (`rds.force_ssl = 1`), Redis, MSK, and object storage.
- **S3 Bucket Hardening Checklist (Mandatory on every bucket):**
  1. `aws_s3_bucket_public_access_block` with all 4 flags set to `true` (`block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets`).
  2. `aws_s3_bucket_versioning` set to `Enabled`.
  3. `aws_s3_bucket_server_side_encryption_configuration` using `aws:kms` (or AES256 only where KMS is unsupported by a specific AWS service integration).
  4. Bucket policy explicitly denying any request where `aws:SecureTransport` is `"false"`.

### Network & Edge Security
- **Private Placement:** Place all stateful workloads (Aurora, MSK, ElastiCache Redis) and EKS worker nodes in **private subnets** with `map_public_ip_on_launch = false`.
- **Zero-Trust Security Groups:**
  - Explicitly define ingress and egress rules using minimal port ranges and source/destination Security Group IDs or private CIDRs.
  - Never allow `0.0.0.0/0` or `::/0` on ingress except on public-facing ALB/NLB listeners (`80`/`443`, where `80` redirects to `443`).
  - Use standalone `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` resources rather than inline blocks to avoid rule conflicts.
- **Edge & Detective Controls:**
  - Protect public endpoints with Amazon CloudFront and AWS WAFv2 (Rate-based rules, `AWSManagedRulesCommonRuleSet`, `AWSManagedRulesKnownBadInputsRuleSet`, `AWSManagedRulesAmazonIpReputationList`).
  - Account for VPC Flow Logs, Amazon GuardDuty, AWS Config, and AWS Security Hub CIS standards in network and account baselines.

---

## 3. Execution Guardrails & Self-Verification Loop

1. **Autonomous Safe Execution:** Freely run read-only and static analysis commands:
   - `terraform fmt -check` / `terraform fmt -recursive`
   - `terraform validate`
   - `tflint`
   - `checkov -d .` / `trivy config .`
   - `aws <service> describe-*` / `list-*`
2. **Mandatory Human-in-the-Loop Lock:** **NEVER** automatically execute state-mutating, destructive, or secret-exposing commands (`terraform apply`, `terraform destroy`, `terraform state rm/mv`, `terragrunt run-all apply/destroy`, `aws kms decrypt`, `aws secretsmanager get-secret-value`) without explicit user confirmation in chat first.
3. **Self-Verification Loop:** After generating or modifying any `.tf` or `terragrunt.hcl` files, automatically run `terraform fmt` and `terraform validate` (and `tflint` / `checkov` if installed) to verify syntax and policy compliance before concluding your response.
