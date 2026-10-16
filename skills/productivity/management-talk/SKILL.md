---
name: management-talk
description: Rewrite deep DevSecOps, cloud infrastructure, Kubernetes/Karpenter, or security incident content for engineering-org leadership (VPs, directors, PMs, release managers, CISO/SecOps leads) and shape it for the target channel — JIRA comment, Slack post, async standup line, email, or meeting talking-points. Trigger when the user asks to write/rewrite for management / exec / VP / director / PM / release manager, asks for an "executive summary / leadership update / incident status update", says "make this less technical / less jargony", or asks for a Slack / email / standup / meeting version of DevSecOps work.
---

# Management Talk (DevSecOps Leadership Comms)

Translate deep DevSecOps, cloud architecture, Kubernetes/Karpenter, and security posture updates for **engineering-org leadership** — VPs of Engineering, Infrastructure Directors, Product Managers, Release Managers, and CISO/SecOps stakeholders — shaped for the exact channel it is going to.

## Language & Register

- **Default Language:** Write in concise, direct **English** by default for maximum token efficiency (only output in another language if explicitly requested by the user).
- **Audience:** Engineering-savvy leaders. They know service/platform names (`EKS`, `Aurora PostgreSQL`, `Karpenter`, `CloudFront`, `WAF`, `Terraform`, `ArgoCD`), SLA/SLO numbers, AWS account/region tiers, compliance frameworks (`CIS`, `ISO 27001`, `SOC2`), JIRA keys, and PR numbers. They do **not** read HCL expressions, IAM JSON policy documents, or `kubectl` stack traces.

## Tone & Translation Rules

- **Keep:** Service names, workload/customer impact, SLA/availability metrics, cost delta (`$/month` or `%`), security risk severity (`CRITICAL`/`HIGH`), JIRA keys, Incident IDs, PR numbers, and owners.
- **Strip:** Terraform resource addresses (`aws_s3_bucket_public_access_block.audit_logs`), HCL syntax (`for_each`, `try()`), IAM condition keys (`sts:ExternalId`), K8s manifest paths (`spec.template.spec.securityContext.readOnlyRootFilesystem`), commit SHAs, and CLI flags.
- **Translate mechanism into business/operational cause-and-effect:**
  - *Instead of:* "`NodePool` `general-spot` had no `disruption.budgets` and `checkout-svc` lacked a `PodDisruptionBudget`, causing simultaneous eviction while `eks-pod-identity-agent` wasn't ready."
  - *Write:* "Karpenter scaled down underutilized nodes simultaneously during a traffic dip, and because `checkout-svc` lacked a disruption budget and node identity startup ordering, replacement pods failed AWS authentication for 14 minutes."
- **Active voice, concrete owners, zero hedging.**

## Channel shapes

### 1. JIRA comment / Written incident or project status report
Structured with bolded section labels:
- **Status / TL;DR:** One bolded line (*"Mitigated; permanent GitOps fix in review."* / *"CIS S3 & KMS remediation complete across prod."*).
- **Customer / Security Impact:** Who was affected, SLA/error-rate impact, or compliance risk closed.
- **What Happened / What Changed:** Plain-language mechanism (2–3 sentences, zero HCL/YAML identifiers).
- **Owner & Artifact:** Engineer + team + single PR/JIRA link.
- **Next Steps & ETA:** Ordered milestones (*"Merge PR #812 → deploy to staging → prod rollout during 02:00 maintenance window"*).
- **Risk / Mitigation:** Any temporary guardrails currently in place.

### 2. Slack — channel post (`#inc-prod`, `#platform-updates`) or DM
- One **bolded TL;DR** on line 1 with the Incident/JIRA key.
- 2–4 tight bullets: Impact/Scope, Root Cause/Change in plain language, Owner + PR, Next Step/Workaround.
- Under ~80 words for a channel post; under ~40 words for a thread reply.

### 3. Async standup note
- 1–3 sentences max, verb-first:
  - *"Resolved `checkout-svc` 503 incident on prod EKS (INC-4092). Root cause was concurrent Karpenter node consolidation without a pod disruption budget; permanent Helm + NodePool fix in PR #812. Rolling out Kyverno policy check next."*

### 4. Email — Exec / Cross-Team / Release Broadcast
- **Subject:** Noun-phrase TL;DR with key (`"[Resolved] Prod Checkout 503 during EKS Node Consolidation (INC-4092)"`).
- **Body:** 2–3 clean paragraphs (Impact & current state → Cause & fix → Prevention & next steps).
- **Sign-off:** Highlight any decision needed from leadership (e.g., maintenance window approval).

### 5. Meeting talking-points
- Short spoken clauses, ordered for delivery, with exact numbers (`14 mins`, `38% error rate`, `PR #812`, `22% EC2 savings`) inline so you can read them at a glance.

## Rules

- **Never invent metrics, SLAs, root causes, or owners.** If the engineering source says root cause is still under investigation, state that clearly.
- **Never strip JIRA keys, Incident IDs, PR numbers, or service/customer names.**
- **Never auto-post to Slack, email, or external systems.** Produce the draft in chat for the user to review and copy (or ask for explicit confirmation before posting to JIRA if an MCP tool is configured).
