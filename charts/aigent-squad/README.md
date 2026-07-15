# aigent-squad

Helm chart for **AIgent-Squad** — a config-driven multi-agent platform for
AWS/Kubernetes operations (supervisor + specialist agents, Bedrock-direct,
read-only by default).

One chart, two topologies:

| Topology | What it deploys | Matches |
|----------|-----------------|---------|
| `inProcess` (default) | An edge **gateway** (public front door) + a single **supervisor** process that runs all agents from config. | ADR-001, spec `02`, spec `31-edge-gateway-worker-pool` |
| `distributed` | **supervisor + 5 specialist agents + mcp-server**, each its own Deployment/Service/ServiceAccount, autoscaled (HPA or KEDA), NetworkPolicy-isolated. | spec `05-helm-chart` |

**Two-tier front door (spec 31)**: the `gateway` service is the only externally
exposed tier — it does edge auth, a worker pool with backpressure, and global
rate/budget admission, then forwards to the `supervisor` backend over
`/internal/process` (port 8001, gateway-only via NetworkPolicy + a distinct
`SUPERVISOR_INTERNAL_TOKEN`). The gateway is also the entrypoint for in-cluster
callers (Alertmanager, anomaly-detection, Falco …) — add them to
`services.gateway.networkPolicy.allowFrom`. The supervisor never accepts traffic
directly (the `/internal/*` trust boundary).

> ⚠️ Requires an app image that contains `src/gateway` (spec 31). Until the app
> cuts a release with the gateway, pin `services.gateway.image.tag` /
> `services.supervisor.image.tag` to a dev tag that includes it.

Everything CRD-dependent (KEDA, External Secrets, NetworkPolicy, Gateway API)
is **opt-in and off by default**, so `helm lint`/`template` and a bare
`ct install` stay green on a vanilla cluster.

> Backing services (DynamoDB, ElastiCache Redis, Bedrock) are **managed** and not
> deployed by this chart — they are consumed via env + secret. An optional
> in-cluster Redis exists for DEV only (`redis.inCluster.enabled`).

## Install

```bash
# Via Helm repo (recommended)
helm repo add staffops https://StaffOps.github.io/helm-charts
helm repo update

helm install aigent-squad staffops/aigent-squad \
  --namespace aigent-squad --create-namespace \
  --set redis.host=my-elasticache.cache.amazonaws.com

# Full distributed topology
helm install aigent-squad staffops/aigent-squad \
  --namespace aigent-squad --create-namespace \
  -f https://raw.githubusercontent.com/StaffOps/helm-charts/main/charts/aigent-squad/values-distributed.yaml \
  --set redis.host=my-elasticache.cache.amazonaws.com
```

The image `karlipegomes/aigent-squad` is built and published to Docker Hub by
the project's CI/CD pipeline (multi-arch: amd64 + arm64), versioned by
`Chart.appVersion` (don't hardcode a tag). Local development overrides
`global.image.registry` to a Harbor project (Harbor is used locally only);
GitHub CI keeps publishing to Docker Hub unchanged.

For production, override IRSA role ARNs, the ingress host, the ElastiCache
endpoint, and the SecretStore via `--set` or a custom values file. Deploy via ArgoCD.

## Topology selection

`topology` is a documentation/intent flag; the actual workloads are driven by the
`services` map. The bundled `values-distributed.yaml` enables the 7 services and
turns on KEDA, NetworkPolicy, ExternalSecret and Ingress.

## The `services` map

Each key renders a workload (Deployment or StatefulSet) + Service + ServiceAccount. The map is
**user-extensible** — every per-service field has a safe default, so adding an
agent needs only the keys you care about:

```yaml
services:
  my-agent:
    enabled: true
    image: { repository: aigent-squad/my-agent, tag: "0.1.0" }
    port: 8007
    mountAgents: true          # load agent configs via projected volume
    expose: false              # true → routed by Ingress (supervisor/mcp only)
    rbac: { readOnly: true }   # opt-in read-only ClusterRole (K8s API access)
    serviceAccount:
      create: true
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/my-agent   # IRSA
    resources:
      requests: { cpu: 100m, memory: 256Mi }
      limits: { memory: 512Mi }
    workload:
      kind: Deployment         # Deployment | StatefulSet
    scaling:
      replicas: 1
      autoscaling:
        kind: none             # none | hpa | keda
        minReplicas: 1
        maxReplicas: 10
        targetCPUUtilizationPercentage: 70
    networkPolicy: { enabled: true, allowFrom: [] }
```

## Workload & autoscaling

Native Kubernetes workloads only — **no Argo Rollout**.

| Setting | Values | Notes |
|---------|--------|-------|
| `workload.kind` | `Deployment` (default) \| `StatefulSet` | StatefulSet also gets a headless Service + `volumeClaimTemplates`. |
| `scaling.autoscaling.kind` | `none` (default) \| `hpa` \| `keda` | `hpa` → `autoscaling/v2` HPA (CPU, optional memory); `keda` → `ScaledObject` (needs KEDA CRDs). When autoscaled, `replicas` is omitted. |

```yaml
# Plain HPA on CPU
scaling: { autoscaling: { kind: hpa, minReplicas: 2, maxReplicas: 10, targetCPUUtilizationPercentage: 70 } }

# KEDA (custom triggers; defaults to CPU when triggers: [])
scaling: { autoscaling: { kind: keda, minReplicas: 1, maxReplicas: 20, triggers: [ ... ] } }

# StatefulSet with a persistent volume
workload:
  kind: StatefulSet
  volumeClaimTemplates:
    - metadata: { name: data }
      spec: { accessModes: [ReadWriteOnce], resources: { requests: { storage: 1Gi } } }
```

## Routing

External access to `expose: true` services — pick the type via `routing.type`:

| `routing.type` | Renders | Use when |
|----------------|---------|----------|
| `none` (default) | nothing | port-forward / in-cluster only |
| `ingress` | `networking.k8s.io/v1` Ingress | nginx, traefik, ALB, etc. |
| `gatewayapi` | `gateway.networking.k8s.io/v1` HTTPRoute | Istio, Cilium, any Gateway API impl |

```yaml
# Ingress (nginx)
routing:
  type: ingress
  host: aigent-squad.example.com
  tls: { enabled: true, secretName: aigent-squad-tls }
  ingress:
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt

# Gateway API (Istio) — references an EXISTING Gateway (chart does not create it)
routing:
  type: gatewayapi
  host: aigent-squad.example.com
  gatewayapi:
    parentRef: { name: istio, namespace: istio-gateway }
```

Path per exposed service is `/<service>` by default; override via `routing.paths`.

## Key values

| Key | Default | Description |
|-----|---------|-------------|
| `topology` | `inProcess` | `inProcess` or `distributed` (intent flag). |
| `global.image.registry` | `""` | Empty = Docker Hub as-is (`karlipegomes/aigent-squad`, the CI target). Local dev overrides to a Harbor project (e.g. `harbor.bigdatacorp.com.br/labs`). |
| `global.env` | region/model/env/log | Non-sensitive shared env (12-factor III). |
| `global.otel.enabled` / `.endpoint` | `true` / collector | OTel export (App→Collector→Backend). |
| `global.otel.metricsPrometheusScrape` | `true` | Also expose `/metrics` on each service's own port for direct Prometheus/VictoriaMetrics scrape (otel-helper v0.2.0+ runs OTLP push + Prometheus export on the same MeterProvider). Pairs with `serviceMonitor.enabled`. |
| `serviceMonitor.enabled` | `false` | Create a Prometheus Operator `ServiceMonitor` per enabled service (targets the existing `http` port + `/metrics`). Off by default — the CRD isn't guaranteed to exist on every cluster. |
| `global.labels` | `{}` | Optional extra labels on every workload/pod (cost tags, env, team…). |
| `global.securityContext` | non-root, RO rootfs, drop ALL | Restricted container context. |
| `global.probes.{liveness,readiness}.path` | `/healthz` / `/ready` | Probe paths (spec 07 code target). |
| `agentsSource.type` | `configmap` | `configmap` (inline) or `git` (initContainer clone). |
| `agents[]` | 5 agents | Inline `config` + `prompt` per agent. |
| `redis.host` | `""` | Managed ElastiCache endpoint. |
| `redis.inCluster.enabled` | `false` | DEV-only in-cluster Redis. |
| `dynamodb.sessionsTable` | `agent-sessions` | DynamoDB table name. |
| `routing.type` | `none` | External routing: `none` \| `ingress` \| `gatewayapi`. |
| `networkPolicy.enabled` | `false` | Specialists accept ingress only from supervisor. |
| `externalSecrets.enabled` | `false` | Secrets via External Secrets Operator → AWS SM. |

## Secrets

Secrets are **never** stored in values/ConfigMap. When `externalSecrets.enabled`,
each entry creates an `ExternalSecret` (External Secrets Operator → AWS Secrets
Manager) producing a K8s Secret consumed via `envFrom`. Expected keys:
`INTERNAL_API_TOKEN`, `REDIS_PASSWORD`, `GITLAB_TOKEN`, `SLACK_*`,
`DOCS_PORTAL_TOKEN`.

## Validate locally

```bash
helm lint charts/aigent-squad
helm template r charts/aigent-squad                                         # inProcess
helm template r charts/aigent-squad -f charts/aigent-squad/values-distributed.yaml   # distributed
```

## Compliance notes

- Restricted `securityContext` (non-root, `readOnlyRootFilesystem`, drop ALL) +
  `emptyDir` for `/tmp`.
- `resources.requests` on every container; mandatory labels on every pod.
- Per-service ServiceAccount with IRSA annotation (no mounted credentials).
- Liveness `/healthz` + readiness `/ready`; `preStop` sleep + graceful shutdown.
- Autoscaling is your choice: none, `autoscaling/v2` HPA, or KEDA `ScaledObject`.
  Workload is a native Deployment or StatefulSet — no Argo Rollout.
- NetworkPolicy isolates specialists; only supervisor + mcp-server are exposed.
