# aigent-squad

Helm chart for **AIgent-Squad** — a config-driven multi-agent platform for
AWS/Kubernetes operations (supervisor + specialist agents, Bedrock-direct,
read-only by default).

One chart, two topologies:

| Topology | What it deploys | Matches |
|----------|-----------------|---------|
| `inProcess` (default) | A single **supervisor** process that runs all agents from config. | ADR-001, spec `02-unify-agent-architecture` |
| `distributed` | **supervisor + 5 specialist agents + mcp-server**, each its own Deployment/Service/ServiceAccount, KEDA-scaled, NetworkPolicy-isolated. | spec `05-helm-chart` |

Everything CRD-dependent (KEDA, Argo Rollouts, External Secrets, NetworkPolicy,
Ingress) is **opt-in and off by default**, so `helm lint`/`template` and a bare
`ct install` stay green on a vanilla cluster.

> Backing services (DynamoDB, ElastiCache Redis, Bedrock) are **managed** and not
> deployed by this chart — they are consumed via env + secret. An optional
> in-cluster Redis exists for DEV only (`redis.inCluster.enabled`).

## Install

```bash
# Default lean topology (supervisor runs all agents in-process)
helm install aigent-squad ./charts/aigent-squad \
  --namespace aigent-squad --create-namespace \
  --set redis.host=my-elasticache.cache.amazonaws.com

# Full distributed topology (spec 05)
helm install aigent-squad ./charts/aigent-squad \
  --namespace aigent-squad --create-namespace \
  -f ./charts/aigent-squad/values-distributed.yaml \
  --set redis.host=my-elasticache.cache.amazonaws.com
```

For PRD/HML/BTC, supply a `values-<env>.yaml` with real IRSA role ARNs, the
ingress host, the ElastiCache endpoint, and the SecretStore. Deploy via ArgoCD.

## Topology selection

`topology` is a documentation/intent flag; the actual workloads are driven by the
`services` map. The bundled `values-distributed.yaml` enables the 7 services and
turns on KEDA, NetworkPolicy, ExternalSecret and Ingress.

## The `services` map

Each key renders a Deployment (or Rollout) + Service + ServiceAccount. The map is
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
    scaling:
      replicas: 1
      keda: { enabled: true, minReplicas: 1, maxReplicas: 10, triggers: [] }
    rollout: { enabled: false }   # true → Argo Rollout (canary)
    networkPolicy: { enabled: true, allowFrom: [] }
```

## Key values

| Key | Default | Description |
|-----|---------|-------------|
| `topology` | `inProcess` | `inProcess` or `distributed` (intent flag). |
| `global.image.registry` | `harbor.bdc.app.br` | Registry prefix (Kyverno may still rewrite). |
| `global.env` | region/model/env/log | Non-sensitive shared env (12-factor III). |
| `global.otel.enabled` / `.endpoint` | `true` / collector | OTel export (App→Collector→Backend). |
| `global.labels` | CostCenter, Environment | Mandatory Kyverno labels. |
| `global.securityContext` | non-root, RO rootfs, drop ALL | Restricted container context. |
| `global.probes.{liveness,readiness}.path` | `/healthz` / `/ready` | Probe paths (spec 07 code target). |
| `agentsSource.type` | `configmap` | `configmap` (inline) or `git` (initContainer clone). |
| `agents[]` | 5 agents | Inline `config` + `prompt` per agent. |
| `redis.host` | `""` | Managed ElastiCache endpoint. |
| `redis.inCluster.enabled` | `false` | DEV-only in-cluster Redis. |
| `dynamodb.sessionsTable` | `agent-sessions` | DynamoDB table name. |
| `ingress.enabled` | `false` | Routes only `expose: true` services. |
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
- KEDA `ScaledObject` (not raw HPA); Argo Rollouts optional for canary.
- NetworkPolicy isolates specialists; only supervisor + mcp-server are exposed.
