---
name: observability-slo-alerting
description: Design, audit, and implement production observability, OpenTelemetry (OTel) Collector pipelines, Prometheus/VictoriaMetrics/AMP metrics, Loki/CloudWatch logs, Grafana-as-Code, and Google SRE multi-window multi-burn-rate SLO alerting on AWS and Amazon EKS. Enforces PII/secret redaction in telemetry, high-cardinality label governance, tail-based sampling, and actionable runbook-linked alerts. Trigger whenever working with OpenTelemetry, Prometheus (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`), Grafana dashboards, Alertmanager, SLOs/error budgets, CloudWatch Alarms, or telemetry pipelines.
---

# Observability, OpenTelemetry & Multi-Burn-Rate SLO Alerting

Enforce high-signal, cost-bounded, and PII-safe observability across Amazon EKS and AWS services. Eliminate alert fatigue by replacing noisy static threshold pages with symptom-driven, multi-window, multi-burn-rate SLO alerts.

---

## 1. OpenTelemetry (OTel) Collector Hardening & Resiliency

Every production OTel Collector deployment (`DaemonSet` for node/pod logs & host metrics, `Deployment`/`StatefulSet` gateway for tail-sampling & routing) MUST enforce:

### Processor Ordering (CRITICAL)
Order processors in `service.pipelines.*` strictly as:
1. **`memory_limiter` (MUST be first):** Prevents collector OOMKills during traffic/log spikes (`check_interval: 1s`, `limit_percentage: 80`, `spike_limit_percentage: 15`). Pair with `GOMEMLIMIT` set to 80–85% of container memory limit.
2. **`k8sattributes` / `resourcedetection`:** Enrich telemetry with `k8s.namespace.name`, `k8s.deployment.name`, `k8s.node.name`, and AWS AZ/instance metadata.
3. **`transform` / `attributes` (PII & Secret Redaction):**
   - Strip `Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, `X-Amz-Security-Token`, and JWT/Bearer tokens from span/log attributes before batching or export.
   - Redact regex patterns matching credit cards, national IDs, emails, or AWS access keys (`AKIA[0-9A-Z]{16}`, `ASIA[0-9A-Z]{16}`).
4. **`filter` (Drop Health & Readiness Noise):**
   - Drop spans and access logs for `/healthz`, `/livez`, `/readyz`, and `/metrics` where `http.status_code == 200` to cut ingestion cost by 30–60%.
5. **`tail_sampling` (Gateway tier for traces):**
   - Always sample `100%` of error traces (`status_code == ERROR` or `http.status_code >= 500`), high-latency traces (`latency > p99 threshold`), and security-flagged spans; sample `1–5%` of baseline `2xx` traffic.
6. **`batch` (MUST be last before exporter):** Optimize network payload compression (`compression: zstd` or `gzip`) and retry queues (`sending_queue` + `retry_on_failure`).

---

## 2. Prometheus / VictoriaMetrics / AWS Managed Prometheus (AMP) Governance

### High-Cardinality Protection (The #1 Time-Series Killer)
- **Forbidden Labels:** **NEVER** allow unbounded values in metric labels: `user_id`, `request_id`, `trace_id`, `session_id`, `ip_address`, `email`, full URL paths with IDs (`/orders/94812`), or raw SQL queries.
- Use **Exemplars** to link aggregated Prometheus latency histograms (`http_request_duration_seconds_bucket`) to specific `trace_id`s in Tempo/X-Ray instead of putting `trace_id` in metric labels.
- Configure `sampleLimit` and `labelLimit` on every `ServiceMonitor` and `PodMonitor` so a single rogue microservice deployment cannot blow up TSDB memory or AMP bill:
  ```yaml
  apiVersion: monitoring.coreos.com/v1
  kind: ServiceMonitor
  metadata:
    name: checkout-svc
  spec:
    sampleLimit: 10000
    labelLimit: 30
    labelNameLengthLimit: 64
    labelValueLengthLimit: 128
    endpoints:
      - port: http-metrics
        interval: 30s
        scrapeTimeout: 10s
        metricRelabelings:
          - sourceLabels: [__name__]
            regex: "go_gc_.*|promhttp_metric_handler_errors_.*"
            action: drop
  ```

---

## 3. SLO Engineering & Multi-Window, Multi-Burn-Rate Alerting

### Alerting Philosophy
- **Page on Symptoms (SLIs), Ticket on Causes:**
  - **Page (`severity: critical` → PagerDuty/Opsgenie):** User-visible availability drop, latency SLO burn, payment/checkout failure spike, Kafka consumer lag threatening SLA, or disk/cert exhaustion `< 24h` via `predict_linear()`.
  - **Ticket / Slack (`severity: warning`):** High CPU, single-pod OOMKill (when replicas > 1 and SLO is healthy), Karpenter node replacement, or slow disk fill (`< 7d`).
  - **Never page on raw CPU% or memory%** unless directly causing user-visible saturation or eviction loops.

### Google SRE Multi-Window, Multi-Burn-Rate Standard
For a 30-day rolling SLO (e.g., `99.9%` availability → `0.1%` error budget = `43.2m` downtime/month):

| Severity | Burn Rate | Long Window | Short Window | Budget Consumed | Action |
|---|---|---|---|---|---|
| **Critical (Fast Burn)** | `14.4x` | `1h` | `5m` | `2%` in 1 hour | **Page immediately** (2m `for:` duration) |
| **Critical (Medium Burn)** | `6x` | `6h` | `30m` | `5%` in 6 hours | **Page immediately** (15m `for:` duration) |
| **Warning (Slow Burn)** | `1x–3x` | `3d` | `6h` | `10%` in 3 days | **Slack / JIRA ticket** (next business day) |

- Require **both** the long window (`1h` / `6h`) and the short window (`5m` / `30m`) to exceed the burn-rate threshold simultaneously—this prevents false alerts after a brief spike has already recovered.
- Pre-compute numerator and denominator ratios via `PrometheusRule` **recording rules** (`job:slo_http_requests:ratio_rate5m`, `rate30m`, `rate1h`, `rate6h`) so alert evaluation is fast and low-cost.
- Every alerting rule MUST include `annotations.runbook_url`, `annotations.summary`, `annotations.dashboard_url`, and `labels.team` / `labels.service`.

---

## 4. AWS Native & Security Telemetry Baselines

- **EKS Control Plane & Node Telemetry:** Enable EKS control plane audit & authenticator logs (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`), AWS VPC Flow Logs (enriched with EKS pod IPs or queried via Athena), and Karpenter interruption/consolidation metrics (`karpenter_nodes_created_total`, `karpenter_pods_startup_duration_seconds`, `karpenter_interruption_received_messages_total`).
- **Stateful Saturation Signals (USE Method — Utilization, Saturation, Errors):**
  - **Aurora/RDS:** `DatabaseConnections` vs `max_connections`, `FreeableMemory`, `ReadLatency`/`WriteLatency`, `BufferCacheHitRatio`, `ACUUtilization`, `ReplicaLag`.
  - **MSK (Kafka):** `OfflinePartitionsCount` (page on `> 0`), `UnderReplicatedPartitions`, `UncleanLeaderElectionsPerSec`, `CpuUser`/`MemoryUsed`, consumer group lag (`aws_kafka_estimated_max_time_lag`).
  - **ElastiCache Redis:** `EngineCPUUtilization` (keep `< 75%` due to single-threaded main loop), `Evictions`, `CurrConnections`, `ReplicationLag`, `DatabaseMemoryUsagePercentage`.
