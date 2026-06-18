# anomaly-detection

**Chart:** `staffops/anomaly-detection`  
**Version:** `0.1.0` · **App Version:** `0.7.0`  
**Source:** [StaffOps/helm-charts](https://github.com/StaffOps/helm-charts/tree/main/charts/anomaly-detection)

Distributed anomaly detection for Kubernetes workloads. Correlates metrics (VictoriaMetrics), logs (Loki), and K8s events; fires enriched alerts to Alertmanager. Ships a Go controller with HA leader election, stateless gRPC workers, a Python ML service (Prophet + Isolation Forest), and an optional in-cluster Redis for baselines.

---

## TL;DR

```bash
helm repo add staffops https://staffops.github.io/helm-charts/
helm repo update
helm install ad staffops/anomaly-detection \
  --namespace monitoring --create-namespace \
  --set clusterName=my-cluster \
  --set datasources.victoriametrics.url=https://vm.example.com/select/0/prometheus \
  --set datasources.loki.url=https://loki.example.com \
  --set datasources.alertmanager.url=https://alertmanager.example.com
```

!!! info "Dry-run mode is ON by default"
    `controller.dryRun=true` is the default. Detected anomalies are logged but **not** sent to Alertmanager. Set `--set controller.dryRun=false` once you have validated detection quality in your environment.

---

## Prerequisites

- Kubernetes **1.24+**
- Helm **3.10+**
- **VictoriaMetrics** read endpoint (PromQL-compatible)
- **Loki** read endpoint (LogQL)
- **Alertmanager** v2 endpoint

Optional integrations (all opt-in, off by default):

| Feature | Required operator / CRD |
|---|---|
| `vmServiceScrape` | [VictoriaMetrics Operator](https://docs.victoriametrics.com/operator/) ≥ 0.33 |
| `vmRule` | VictoriaMetrics Operator ≥ 0.33 |
| `grafanaDashboard` | [Grafana Operator sidecar](https://github.com/grafana/helm-charts/tree/main/charts/grafana) or kube-prometheus-stack sidecar |

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Controller (Go, 2 replicas — HA Lease)                  │
│  - Evaluates static rules + adaptive metrics every 30s   │
│  - Fans out enrichment queries per fired alert           │
│  - Calls ML service for Prophet / Isolation Forest       │
│  - Dispatches to Alertmanager (when dryRun=false)        │
└───────────┬──────────────────────────┬───────────────────┘
            │  gRPC (round_robin)       │  gRPC
            ▼                          ▼
┌───────────────────────┐   ┌──────────────────────────┐
│  Workers (Go, 3 pods) │   │  ML Service (Python, 1)  │
│  - Execute PromQL /   │   │  - Prophet forecasting   │
│    LogQL queries       │   │  - Isolation Forest      │
│  - Stateless, headless│   │  - Z-Score / EWMA        │
└───────────────────────┘   └──────────────────────────┘
            │
            ▼
┌───────────────────────┐
│  Redis                │
│  - EWMA baselines     │
│  - Dedup TTL (cooldown│
│  - Seasonal profiles  │
└───────────────────────┘
```

---

## Values reference

### Global

| Key | Type | Default | Description |
|---|---|---|---|
| `clusterName` | string | `default` | Unique cluster identifier added to all alert labels |
| `nameOverride` | string | `""` | Override chart name component |
| `fullnameOverride` | string | `""` | Override fully-qualified resource name |
| `image.registry` | string | `ghcr.io` | Shared registry for all components |
| `image.tag` | string | `""` | Shared tag (defaults to `appVersion`) |
| `image.pullPolicy` | string | `IfNotPresent` | Shared pull policy |

### Datasources (required)

| Key | Type | Default | Description |
|---|---|---|---|
| `datasources.victoriametrics.url` | string | `""` | VictoriaMetrics PromQL endpoint |
| `datasources.victoriametrics.timeout` | string | `30s` | Query timeout |
| `datasources.loki.url` | string | `""` | Loki base URL (without `/loki/api/v1/...`) |
| `datasources.loki.timeout` | string | `30s` | Query timeout |
| `datasources.alertmanager.url` | string | `""` | Alertmanager v2 base URL |

### Controller

| Key | Type | Default | Description |
|---|---|---|---|
| `controller.replicaCount` | int | `2` | Replicas — `>1` enables HA via K8s Lease |
| `controller.dryRun` | bool | `true` | Log alerts without dispatching to Alertmanager |
| `controller.jobInterval` | string | `30s` | Detection cycle interval |
| `controller.correlationWindow` | string | `2m` | Time window for cross-signal correlation |
| `controller.cooldown` | string | `5m` | Suppression window after an alert fires |
| `controller.leaderElection.enabled` | bool | `true` | Enable K8s Lease-based leader election |
| `controller.leaderElection.leaseDuration` | string | `15s` | Lease duration |
| `controller.leaderElection.renewDeadline` | string | `10s` | Leader renew deadline |
| `controller.resources.requests.cpu` | string | `100m` | CPU request |
| `controller.resources.requests.memory` | string | `128Mi` | Memory request |
| `controller.resources.limits.memory` | string | `256Mi` | Memory limit (no CPU limit to avoid throttling) |

### Workers

| Key | Type | Default | Description |
|---|---|---|---|
| `worker.replicaCount` | int | `3` | Stateless worker replicas |
| `worker.grpcPort` | int | `50052` | gRPC listen port |
| `worker.concurrency` | int | `5` | Max concurrent queries per worker |
| `worker.resources.requests.memory` | string | `128Mi` | Memory request |
| `worker.resources.limits.memory` | string | `512Mi` | Memory limit |

### ML service

| Key | Type | Default | Description |
|---|---|---|---|
| `ml.enabled` | bool | `true` | Deploy the Python ML service |
| `ml.replicaCount` | int | `1` | ML service replicas |
| `ml.grpcPort` | int | `50051` | gRPC listen port |
| `ml.timeout` | string | `5s` | Controller→ML call timeout |
| `ml.resources.requests.cpu` | string | `200m` | CPU request |
| `ml.resources.requests.memory` | string | `512Mi` | Memory request |
| `ml.resources.limits.memory` | string | `1Gi` | Memory limit |

### Redis

| Key | Type | Default | Description |
|---|---|---|---|
| `redis.enabled` | bool | `true` | Deploy in-cluster Redis (single-node, no HA) |
| `redis.persistence.enabled` | bool | `false` | Persist Redis data via PVC |
| `redis.persistence.size` | string | `1Gi` | PVC size when persistence is enabled |
| `redis.external.addr` | string | `""` | External Redis address (`host:port`) — used when `redis.enabled=false` |
| `redis.external.existingSecret` | string | `""` | Secret holding `redis-password` key |

### Detection

| Key | Type | Default | Description |
|---|---|---|---|
| `detection.staticRules` | list | 3 rules | Static threshold rules (PromQL + threshold + operator) |
| `detection.adaptiveMetrics` | list | 2 metrics | Metrics evaluated with EWMA + Z-Score |
| `detection.logPatterns` | list | 1 pattern | Loki-based log rate patterns |
| `detection.eventPatterns` | list | 4 reasons | K8s event reasons that trigger detection |
| `baseline.ewmaAlpha` | float | `0.3` | EWMA smoothing factor (0–1) |
| `baseline.zscoreThreshold` | float | `3.0` | Z-Score threshold for adaptive anomaly detection |
| `baseline.warmUpSamples` | int | `60` | Samples required before adaptive rules fire |
| `baseline.seasonalMinDays` | int | `7` | Minimum days of data for seasonal baseline |

### Suppression

| Key | Type | Default | Description |
|---|---|---|---|
| `suppression.excludeNamespaces` | list | `[kube-system, kube-public, kube-node-lease]` | Fully excluded namespaces |
| `suppression.excludeStaticOnly` | list | `[]` | Namespaces where static rules are skipped but adaptive still fires |

### Observability integrations

| Key | Type | Default | Description |
|---|---|---|---|
| `vmServiceScrape.enabled` | bool | `false` | Create VMServiceScrape for VictoriaMetrics Operator |
| `vmServiceScrape.interval` | string | `30s` | Scrape interval |
| `vmRule.enabled` | bool | `false` | Create VMRule with health alerts and recording rules |
| `grafanaDashboard.enabled` | bool | `false` | Create ConfigMap with Grafana dashboard JSON |
| `serviceMonitor.enabled` | bool | `false` | Create Prometheus Operator ServiceMonitor |

---

## Production install

```yaml
# values-prod.yaml
clusterName: "eks-prod-us-east-1"

datasources:
  victoriametrics:
    url: "https://vm.example.com/select/0/prometheus"
    timeout: 30s
  loki:
    url: "https://loki.example.com"
    timeout: 30s
  alertmanager:
    url: "https://alertmanager.example.com"

controller:
  replicaCount: 2
  dryRun: false
  jobInterval: 30s
  correlationWindow: 2m
  cooldown: 5m
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      memory: 512Mi

worker:
  replicaCount: 3
  concurrency: 10
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      memory: 1Gi

ml:
  enabled: true
  replicaCount: 1
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      memory: 2Gi

redis:
  enabled: false
  external:
    addr: "redis.example.com:6379"
    existingSecret: "ad-redis-secret"
    secretKey: "redis-password"
  persistence:
    enabled: false

baseline:
  ewmaAlpha: 0.3
  zscoreThreshold: 3.0
  warmUpSamples: 60
  seasonalMinDays: 7

suppression:
  excludeNamespaces:
    - kube-system
    - kube-public
    - kube-node-lease
  excludeStaticOnly:
    - batch-jobs
    - data-pipeline

links:
  grafanaBaseUrl: "https://grafana.example.com"
  tempoBaseUrl: "https://tempo.example.com"
  lokiBaseUrl: "https://loki.example.com"
  runbookBaseUrl: "https://wiki.example.com/runbooks"
  grafanaVMDatasourceUid: "victoriametrics"
  grafanaTempoDatasourceUid: "tempo"
  grafanaLokiDatasourceUid: "loki"

vmServiceScrape:
  enabled: true
  interval: 30s

vmRule:
  enabled: true

grafanaDashboard:
  enabled: true

podDisruptionBudget:
  controller:
    enabled: true
    minAvailable: 1
  worker:
    enabled: true
    minAvailable: 2
```

```bash
helm upgrade --install ad staffops/anomaly-detection \
  --namespace monitoring --create-namespace \
  -f values-prod.yaml
```

---

## Upgrade

```bash
helm repo update
helm upgrade ad staffops/anomaly-detection \
  --namespace monitoring \
  -f values-prod.yaml
```

!!! tip
    The controller and workers perform a rolling update by default. Leader election ensures that detection continues without interruption during the rollout — the standby controller replica becomes the leader immediately.

---

## Uninstall

```bash
helm uninstall ad --namespace monitoring
```

This removes all chart-managed resources. It does **not** delete the namespace, PersistentVolumeClaims (if `redis.persistence.enabled=true`), or any data in an external Redis. Delete those manually if needed:

```bash
kubectl delete pvc -l app.kubernetes.io/instance=ad -n monitoring
kubectl delete namespace monitoring
```

---

## Troubleshooting

### Controller is not dispatching alerts

1. Check `dryRun` — it defaults to `true`:
   ```bash
   kubectl get configmap -n monitoring -l app.kubernetes.io/instance=ad -o yaml | grep dryRun
   ```
2. Check controller logs:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/component=controller --tail=100
   ```
3. Verify Alertmanager connectivity from within the cluster:
   ```bash
   kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
     curl -s https://alertmanager.example.com/api/v2/status
   ```

### Workers are not receiving queries

The worker Service is headless (`clusterIP: None`). The controller uses the gRPC `round_robin` balancer against the headless DNS. Check that DNS resolves to individual pod IPs:

```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup <release>-anomaly-detection-worker.monitoring.svc.cluster.local
```

### ML service crashes on startup

The ML image requires at least **512 Mi** of memory to load Prophet and scikit-learn models. Check actual memory usage:

```bash
kubectl top pod -n monitoring -l app.kubernetes.io/component=ml
```

Increase `ml.resources.requests.memory` and `ml.resources.limits.memory` if the pod is OOMKilled.

### Baseline not warming up

The adaptive detection rules require `baseline.warmUpSamples` (default: 60) cycles before firing. With `controller.jobInterval=30s` that is **30 minutes** of data. During warmup, only static threshold rules are evaluated. Check the current sample count in controller logs:

```bash
kubectl logs -n monitoring -l app.kubernetes.io/component=controller | grep "warmup"
```

### Leader election is flapping

Check Lease events:

```bash
kubectl describe lease staffops-ad-controller -n monitoring
```

If the controller cannot renew the Lease within `renewDeadline` (default: 10s), verify that the controller pod has sufficient CPU and that the API server is reachable from within the namespace.
