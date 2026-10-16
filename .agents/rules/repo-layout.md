---
trigger: always_on
description: Repository layout, skill bucket organization, and README/skills.json synchronization rules for the devops-skills repository.
---

# Repository Layout & Skill Rules

Skills are organized into bucket folders under `skills/`:

- `engineering/` — daily DevSecOps, IaC, Kubernetes/Karpenter, CI/CD, and security engineering work
- `productivity/` — daily incident/leadership communication and workflow management tools
- `misc/` — kept around but rarely used
- `personal/` — tied to my own setup, not promoted
- `in-progress/` — drafts not yet ready to ship
- `deprecated/` — no longer used

Every skill in `engineering/`, `productivity/`, or `misc/` must have a reference in the top-level `README.md` and be discoverable via `.agents/skills.json`. Skills in `personal/`, `in-progress/`, and `deprecated/` must not appear in either.

Each skill entry in the top-level `README.md` must link the skill name to its `SKILL.md`.

Each bucket folder has a `README.md` that lists every skill in the bucket with a one-line description, with the skill name linked to its `SKILL.md`.
