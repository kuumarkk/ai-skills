---
name: stay-on-track
description: Keeps a long Antigravity / Gemini DevSecOps task on-track — breaks out of looping/circular thinking, enforces one-edit-one-validation (`terraform validate`, `helm lint`), watches the context budget, bounds internal reasoning, and triggers a clean artifact-backed handoff before the context window fills. Use when the agent is repeating steps, re-reading the same files, stuck on an IaC/K8s/pipeline error, or running a large multi-module/multi-environment refactor at risk of exhausting context.
---

# Staying on Track (Long DevSecOps Tasks)

Large infrastructure migrations, multi-environment Terragrunt refactors, EKS/Karpenter upgrades, and security compliance audits fail three ways: **looping**, **over-thinking**, and **running out of context**. Run the checklist below **before each step**.

## Before each step — run this

| Check | Trigger fires when... | Do this |
|---|---|---|
| **Looping?** | You're about to repeat a failing command or re-read an unchanged file | Break the loop — pick one fix below |
| **Over-thinking?** | You've reasoned past ~1000 words without acting | Stop. Act on your current best decision, or ask the user one question |
| **Context tight?** | 2+ context budget signals hold (or multi-module audit ahead) | Offload to a `flash` subagent, or finish this unit and write a handoff artifact |

If nothing fires, take the step.

## 1. Loops — detect and break

A step is a loop if **any** of these is true:

- You're re-reading a `.tf`, `terragrunt.hcl`, or manifest file you already read this session (and it has **not** changed since).
- You're re-running a failing CLI command (`terraform validate`, `tflint`, `checkov`, `helm template`, `aws ...`) with the same inputs expecting a different result.
- You're returning to an architectural or debugging hypothesis you already falsified.
- The last 2 steps produced no new telemetry or verified progress.

**Re-reading a file you just edited or running `terraform fmt && terraform validate` / `helm lint` after an edit is NOT a loop** — that is the mandatory Self-Verification Loop.

When a loop fires, **stop** and do exactly one:

1. State the blocker in one sentence and ask the user a specific question (e.g., missing AWS account context, VPC CIDR, or permission boundary).
2. Write what is confirmed vs. unknown, then take a **different** diagnostic action.
3. Looped 2+ times on the same sub-problem? Mark it blocked and move to the next independent module or hand off.

**Retry cap:** Never run the same failing command a 3rd time. If a CLI tool, provider plugin, or credential check fails after ~3 attempts, STOP and ask the user.

**One Edit → One Validation:** Never chain blind edits across 5 Terraform modules without validating. Edit one logical unit → run `terraform fmt` / `terraform validate` / `helm lint` → confirm clean → proceed to the next unit.

## 2. Thinking — keep it bounded

Cap internal reasoning at **~1000 words per step**.

- Decide → implement → validate. Don't re-derive architectural decisions already settled in this session.
- If requirements are ambiguous (e.g., whether a workload requires public ALB vs. internal NLB, or KMS CMK vs. AWS-managed key), **ask the user one sharp question**.

## 3. Context budget — count signals, don't estimate

**Count how many of these are true right now:**

- [ ] 20+ assistant turns into the task.
- [ ] Read 5+ infrastructure modules/charts, or any one huge `terraform plan` / CloudWatch / CI log dump.
- [ ] Large scanner outputs (`checkov`, `trivy`, `kubectl describe`) accumulating in conversation history.
- [ ] 3+ modules, environments, or plan steps still remaining.

**Map the count to an action:**

- **Count is 0 or 1 → CONTINUE** working normally. (Proactively delegate repetitive module audits or log summarization to [`flash-agent`](../../engineering/flash-agent/SKILL.md) via `invoke_subagent` so your main context stays lean.)
- **Count is 2, 3, or 4 → HAND OFF** — finish validating the current module/manifest, then go to section 4.

## 4. Hand off cleanly

When context is tight or the user asks for a handoff:

1. **Leave the repo in a valid state first** — run `terraform fmt`, `terraform validate`, or `helm lint` on touched files and check `git status -s` so no half-edited syntax errors remain.
2. **Write a Handoff Artifact** (`handoff.md` in `<appDataDir>/brain/<conversation-id>/handoff.md` or workspace root) containing:
   - **Goal & Current Architecture State**: One-paragraph summary of the DevSecOps task and current progress.
   - **Completed & Validated Changes**: Exact modules/manifests updated and which static checks (`terraform validate`, `tflint`, `checkov`, `helm lint`) passed.
   - **Pending Human-in-the-Loop Actions**: Any `terraform apply`, `terragrunt run-all apply`, or `kubectl apply` commands awaiting user execution.
   - **Next Steps**: Ordered checklist of remaining modules/environments with exact file paths.
3. Tell the user plainly: *"Context is getting tight — I've saved a handoff summary to `handoff.md` so you can continue cleanly in a fresh conversation."*
