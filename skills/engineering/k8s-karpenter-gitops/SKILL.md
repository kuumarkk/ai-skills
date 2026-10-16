---
name: k8s-karpenter-gitops
description: Design, harden, and review Kubernetes workloads, Dockerfiles, Karpenter v1+ autoscaling (`NodePool` and `EC2NodeClass`), Helm charts, and ArgoCD GitOps manifests on Amazon EKS. Enforces Pod Security Standards (Restricted/Baseline), External Secrets Operator (ESO), Karpenter v1 GA hardening (IMDSv2, encrypted gp3, consolidation budgets), and high-availability controls. Trigger whenever working with Dockerfiles, Kubernetes manifests, EKS, Karpenter, Helm charts, or ArgoCD applications.
---

# Kubernetes, Karpenter v1+ & GitOps Security (EKS / Helm / ArgoCD)

Enforce container hardening, Kubernetes Pod Security Standards (Restricted/Baseline), Karpenter v1+ GA specifications, and production High Availability across all EKS workloads and GitOps pipelines.

## Language & Communication Stance

- **Language:** Respond in **Thai** for architectural discussions, explanations, and trade-offs. Keep all manifests, Dockerfiles, Helm templates, inline comments, commit messages, and resource names in **English**.
- **Tone:** Concise, direct, and technical. Focus immediately on workload isolation, scheduling resilience, blast radius, and least privilege.

---

## 1. Container Hardening (Dockerfile)

- **Multi-Stage & Minimal Base:** Always use multi-stage builds with minimal or `distroless` runtime base images (`gcr.io/distroless/*`, `chainguard/*`, or hardened Alpine/Debian slim).
- **Immutable Image Pinning:** Pin image tags to immutable semantic versions or SHA256 digests (`image@sha256:...`). **Never** use `:latest` in production Dockerfiles or Kubernetes manifests.
- **Non-Root Execution:** Explicitly create and switch to a non-root UID/GID (`USER 10001:10001`) before `ENTRYPOINT` / `CMD`.
- **Zero Baked Secrets:** Never bake credentials, private keys, certificates, or `.env` files into image layers (`COPY` or `ARG`). Use BuildKit secret mounts (`--mount=type=secret`) if build-time authentication is required.

---

## 2. Kubernetes Pod Security & High Availability

### Pod Security Standards (Restricted / Baseline)
Every `Deployment`, `StatefulSet`, `DaemonSet`, or `Job` pod template MUST define:

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
```

- If the application requires writable scratch space (e.g., `/tmp`, `/var/run`), mount an in-memory or size-bounded `emptyDir` volume (`sizeLimit: 64Mi`) while keeping `readOnlyRootFilesystem: true`.

### Resource Governance & Health Probes
- **Resources:** Always set explicit `resources.requests` and `resources.limits` for both `cpu` and `memory` (set memory request == memory limit for Guaranteed-like OOM predictability on critical services).
- **Probes:** Configure properly tuned `startupProbe`, `readinessProbe`, and `livenessProbe` with distinct failure thresholds so slow startups or downstream glitches do not trigger cascading restart loops.

### Production High Availability (HA)
- **PodDisruptionBudget (PDB):** Pair every production stateless/stateful workload (`replicas >= 2`) with a `policy/v1` `PodDisruptionBudget` specifying `minAvailable` or `maxUnavailable` so Karpenter consolidation and node drains cannot take down all replicas simultaneously.
- **Topology Spread:** Include `topologySpreadConstraints` across `topology.kubernetes.io/zone` and `kubernetes.io/hostname` (with `whenUnsatisfiable: DoNotSchedule` or `ScheduleAnyway` + `maxSkew: 1`) to survive AZ outages.

### Secret Management
- **External Secrets Only:** Manage runtime secrets via **External Secrets Operator (ESO)** (`ExternalSecret` / `ClusterSecretStore`) or **Secrets Store CSI Driver** backed by AWS Secrets Manager or SSM Parameter Store, authenticated via **EKS Pod Identity** or **IRSA**.
- **Never** commit raw base64-encoded `kind: Secret` manifests to Git.

---

## 3. Karpenter (v1+ GA Strict Standards)

- **API Versions (Mandatory):**
  - Strictly use `karpenter.sh/v1` for `NodePool` and `karpenter.k8s.aws/v1` for `EC2NodeClass`.
  - **NEVER** generate deprecated `Provisioner` (`karpenter.sh/v1alpha5`), `AWSNodeTemplate` (`karpenter.k8s.aws/v1alpha1`), or `v1beta1` manifests.
- **`EC2NodeClass` Hardening (`karpenter.k8s.aws/v1`):**
  - **IMDSv2 Enforcement:** Always configure `metadataOptions`:
    ```yaml
    metadataOptions:
      httpEndpoint: enabled
      httpProtocolIPv6: disabled
      httpPutResponseHopLimit: 1
      httpTokens: required
    ```
  - **Encrypted Root & Ephemeral EBS (`gp3`):** Configure `blockDeviceMappings` with `volumeType: gp3`, `encrypted: true`, explicit `kmsKeyID`, `deleteOnTermination: true`, and appropriate IOPS/throughput.
  - **Tag-Based Discovery:** Select private subnets (`subnetSelectorTerms`) and security groups (`securityGroupSelectorTerms`) via `tags: { "karpenter.sh/discovery": "<cluster-name>" }`.
  - Specify `amiSelectorTerms` (e.g., `alias: al2023@latest` or Bottlerocket pinned alias) and `role` matching the Karpenter Node IAM Role.
- **`NodePool` Resilience & Cost Protection (`karpenter.sh/v1`):**
  - **Disruption & Consolidation:** Configure `disruption.consolidationPolicy: WhenEmptyOrUnderutilized`, explicit `consolidateAfter` (e.g., `1m`), and `disruption.budgets` (e.g., `nodes: "10%"` or business-hour freeze schedules) to prevent mass node churn.
  - **Hard Scaling Limits:** Always set `limits` (`cpu` and `memory`) on every `NodePool` to prevent runaway scaling and billing spikes.
  - **Node Requirements:** Constrain `karpenter.sh/capacity-type` (`spot` / `on-demand`), `kubernetes.io/arch` (`amd64` / `arm64`), and instance categories/generations (`karpenter.k8s.aws/instance- category`, `karpenter.k8s.aws/instance-generation` `Gt "5"`).
- **Terraform Provisioning:** Provision Karpenter Controller IAM Roles (Pod Identity / IRSA), Node IAM Roles, EventBridge interruption rules, and SQS Spot Interruption Queues using `terraform-aws-modules/eks/aws//modules/karpenter`.

---

## 4. Helm & ArgoCD GitOps

- **Helm Values Hygiene:** Keep `values.yaml` hierarchical, DRY, and documented with inline comments explaining security and scaling knobs.
- **ArgoCD Synchronization:**
  - Use `argocd.argoproj.io/sync-wave` annotations to order dependencies cleanly (e.g., CRDs & namespaces in wave `-1`, operators/secrets in wave `0`, workloads in wave `1`).
  - Set `ServerSideApply=true` (and `Replace=true` where necessary) in `syncOptions` for large CRDs (such as Karpenter, Prometheus Operator, or Gateway API CRDs) to avoid annotation size limit errors (`metadata.annotations: Too long`).
  - Configure `ignoreDifferences` for fields mutated at runtime by controllers (HPA `replicas`, webhook `caBundle`).

---

## 5. Execution Guardrails & Self-Verification Loop

1. **Autonomous Safe Execution:** Freely run read-only inspection and validation tools:
   - `helm lint` / `helm template`
   - `kubeconform -strict -summary`
   - `trivy image` / `trivy config`
   - `kubectl get` / `describe` / `logs` / `events` / `top`
2. **Mandatory Human-in-the-Loop Lock:** **NEVER** automatically execute cluster-mutating commands (`kubectl apply`, `kubectl delete`, `kubectl patch`, `kubectl edit`, `kubectl drain`, `helm upgrade`, `helm install`, `helm uninstall`) without explicit user confirmation in chat first.
3. **Self-Verification Loop:** After creating or updating Helm charts or Kubernetes manifests, automatically run `helm lint` / `helm template` or `kubeconform` (when available in the environment) to verify schema validity before finishing.
