# aigent-squad

**Chart:** `staffops/aigent-squad`  
**Version:** `0.6.0` · **App Version:** `0.1.0`  
**Source:** [StaffOps/helm-charts](https://github.com/StaffOps/helm-charts/tree/main/charts/aigent-squad)

Config-driven multi-agent platform for AWS and Kubernetes operations. One chart, two topologies: a single in-process supervisor (default) or a fully distributed mesh of specialized microservices.

---

## TL;DR

```bash
helm repo add staffops https://staffops.github.io/helm-charts/
helm repo update
helm install aigent-squad staffops/aigent-squad \
  --namespace aigent-squad --create-namespace \
  --set redis.host=my-elasticache.cache.amazonaws.com
```

The install above uses the `inProcess` topology with an external ElastiCache endpoint. No Bedrock, KEDA, or ExternalSecret CRDs are required.

---

## Prerequisites

- Kubernetes **1.24+**
- Helm **3.10+**
- An external Redis endpoint (ElastiCache or equivalent)
- AWS credentials accessible to the pod — the recommended approach is **IRSA** (annotate the ServiceAccount with a role ARN)

Optional, but required for specific features:

| Feature | Required operator / CRD |
|---|---|
| KEDA autoscaling | [KEDA](https://keda.sh/) ≥ 2.12 |
| External secrets | [External Secrets Operator](https://external-secrets.io/) ≥ 0.9 |
| Network isolation | Kubernetes NetworkPolicy support (Cilium, Calico, etc.) |
| Gateway API routing | [Gateway API](https://gateway-api.sigs.k8s.io/) ≥ 1.0 |

---

## Topologies

### `inProcess` (default)

A single `supervisor` Deployment runs all agents in-process. The agent definitions are loaded from a ConfigMap (or a git repository) and projected into the pod as a volume. This topology requires only one Deployment and one Service, making it the right choice for development, staging, or clusters with limited resources.

```
┌─────────────────────────────────────────┐
│  supervisor pod                         │
│  ┌────────┐ ┌────┐ ┌──────┐ ┌───────┐  │
│  │  aws   │ │ k8s│ │finops│ │devops │  │
│  └────────┘ └────┘ └──────┘ └───────┘  │
│        all agents in one process        │
└─────────────────────────────────────────┘
```

### `distributed`

Each agent runs in its own Deployment with its own ServiceAccount, IRSA role, and KEDA ScaledObject. The supervisor routes requests to specialists over HTTP. The `mcp-server` is a separate facade used by CLI tooling (e.g. Kiro). NetworkPolicy restricts inter-pod traffic: specialists only accept ingress from the supervisor pod.

```
┌──────────────┐     HTTP      ┌───────────────┐
│  supervisor  │──────────────▶│  aws-agent    │
│  (exposed)   │               ├───────────────┤
│              │──────────────▶│  k8s-agent    │
└──────────────┘               ├───────────────┤
                               │  finops-agent │
┌──────────────┐               ├───────────────┤
│  mcp-server  │               │  devops-agent │
│  (exposed)   │               ├───────────────┤
└──────────────┘               │ obs-agent     │
                               └───────────────┘
```

To render the distributed topology:

```bash
helm template aigent-squad staffops/aigent-squad \
  -f https://raw.githubusercontent.com/StaffOps/helm-charts/main/charts/aigent-squad/values-distributed.yaml
```

---

## Values reference

### Core

| Key | Type | Default | Description |
|---|---|---|---|
| `topology` | string | `inProcess` | Topology mode: `inProcess` or `distributed` |
| `nameOverride` | string | `""` | Override the chart name component of resource names |
| `fullnameOverride` | string | `""` | Override the fully-qualified resource name |

### Global settings

| Key | Type | Default | Description |
|---|---|---|---|
| `global.image.registry` | string | `""` | Container registry prefix (empty = use repository as-is) |
| `global.image.pullPolicy` | string | `IfNotPresent` | Image pull policy for all services |
| `global.env.AWS_REGION` | string | `us-east-1` | AWS region for Bedrock and other SDK calls |
| `global.env.BEDROCK_MODEL_ID` | string | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | Default Bedrock model ID |
| `global.env.LOG_LEVEL` | string | `info` | Log verbosity (`debug`, `info`, `warn`, `error`) |
| `global.otel.enabled` | bool | `true` | Enable OpenTelemetry export |
| `global.otel.endpoint` | string | `http://otel-collector.monitoring:4317` | OTLP gRPC endpoint |
| `global.terminationGracePeriodSeconds` | int | `30` | Pod graceful shutdown window |

### Backing services

| Key | Type | Default | Description |
|---|---|---|---|
| `redis.host` | string | `""` | **Required.** External Redis/ElastiCache endpoint |
| `redis.port` | int | `6379` | Redis port |
| `redis.ssl` | bool | `true` | Enable TLS for Redis connection |
| `redis.inCluster.enabled` | bool | `false` | Deploy a single-pod Redis for DEV (no HA) |
| `dynamodb.sessionsTable` | string | `agent-sessions` | DynamoDB table for conversation state |
| `dynamodb.endpoint` | string | `""` | Override for DynamoDB Local in DEV |

### Services map

Each entry under `services` renders a complete workload (Deployment or StatefulSet), a ClusterIP Service, and a ServiceAccount. Only the `supervisor` entry is active in `inProcess` mode.

| Key | Type | Default | Description |
|---|---|---|---|
| `services.<name>.enabled` | bool | `true` | Toggle this service entirely |
| `services.<name>.image.repository` | string | — | Container image repository |
| `services.<name>.image.tag` | string | — | Container image tag |
| `services.<name>.port` | int | — | Container port (also Service targetPort) |
| `services.<name>.expose` | bool | `false` | Include this service in routing (Ingress / HTTPRoute) |
| `services.<name>.mountAgents` | bool | `false` | Mount the agents ConfigMap volume into this pod |
| `services.<name>.serviceAccount.create` | bool | `true` | Create a dedicated ServiceAccount |
| `services.<name>.serviceAccount.annotations` | map | `{}` | SA annotations — use for IRSA `eks.amazonaws.com/role-arn` |
| `services.<name>.scaling.replicas` | int | `1` | Static replica count (ignored when autoscaling is enabled) |
| `services.<name>.scaling.autoscaling.kind` | string | `none` | Autoscaler: `none`, `hpa`, or `keda` |
| `services.<name>.scaling.autoscaling.minReplicas` | int | `1` | Min replicas for HPA / KEDA |
| `services.<name>.scaling.autoscaling.maxReplicas` | int | `10` | Max replicas for HPA / KEDA |
| `services.<name>.networkPolicy.enabled` | bool | `false` | Create a NetworkPolicy for this service |
| `services.<name>.workload.kind` | string | `Deployment` | `Deployment` or `StatefulSet` |

### Routing

| Key | Type | Default | Description |
|---|---|---|---|
| `routing.type` | string | `none` | External routing: `none`, `ingress`, or `gatewayapi` |
| `routing.host` | string | `""` | Hostname for Ingress / HTTPRoute |
| `routing.tls.enabled` | bool | `false` | Enable TLS on the Ingress resource |
| `routing.tls.secretName` | string | `""` | Kubernetes TLS Secret name (Ingress only) |
| `routing.ingress.className` | string | `""` | Ingress class (`nginx`, `alb`, `traefik`, …) |
| `routing.gatewayapi.parentRef.name` | string | `""` | Gateway name for HTTPRoute parentRef |
| `routing.gatewayapi.parentRef.namespace` | string | `""` | Gateway namespace for HTTPRoute parentRef |

### External secrets

| Key | Type | Default | Description |
|---|---|---|---|
| `externalSecrets.enabled` | bool | `false` | Create ExternalSecret resources (requires ESO) |
| `externalSecrets.secretStore.name` | string | `aws-secrets-manager` | SecretStore or ClusterSecretStore name |
| `externalSecrets.secretStore.kind` | string | `ClusterSecretStore` | `SecretStore` or `ClusterSecretStore` |
| `externalSecrets.refreshInterval` | string | `1h` | How often ESO syncs from the remote store |
| `externalSecrets.secrets` | list | `[]` | List of ExternalSecret definitions (see values.yaml) |

---

## Production values example

The snippet below is a production-ready starting point for an EKS cluster using IRSA, KEDA, and ExternalSecret for secret management.

```yaml
# values-prod.yaml
topology: inProcess

global:
  image:
    registry: ""
    pullPolicy: IfNotPresent
  env:
    AWS_REGION: "us-east-1"
    BEDROCK_MODEL_ID: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
    ENVIRONMENT: "PRD"
    LOG_LEVEL: "info"
  otel:
    enabled: true
    endpoint: "http://otel-collector.monitoring:4317"

redis:
  host: "aigent-squad.xxxx.ng.0001.use1.cache.amazonaws.com"
  port: 6379
  ssl: true

dynamodb:
  sessionsTable: "aigent-squad-sessions-prod"

services:
  supervisor:
    enabled: true
    image:
      repository: karlipegomes/aigent-squad
      tag: "0.1.0"
    port: 8000
    mountAgents: true
    expose: true
    serviceAccount:
      create: true
      annotations:
        eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/aigent-squad-supervisor-prod"
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        memory: 2Gi
    scaling:
      autoscaling:
        kind: keda
        minReplicas: 2
        maxReplicas: 10
        pollingInterval: 30
        triggers:
          - type: cpu
            metricType: Utilization
            metadata:
              value: "70"
    networkPolicy:
      enabled: true

routing:
  type: ingress
  host: "aigent-squad.example.com"
  tls:
    enabled: true
    secretName: "aigent-squad-tls"
  ingress:
    className: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/proxy-read-timeout: "300"

externalSecrets:
  enabled: true
  secretStore:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  refreshInterval: 1h
  secrets:
    - name: aigent-squad-secrets
      data:
        - secretKey: REDIS_PASSWORD
          remoteRef:
            key: aigent-squad/redis-password
        - secretKey: INTERNAL_API_TOKEN
          remoteRef:
            key: aigent-squad/internal-api-token
        - secretKey: GITLAB_TOKEN
          remoteRef:
            key: aigent-squad/gitlab-token
```

Apply with:

```bash
helm upgrade --install aigent-squad staffops/aigent-squad \
  --namespace aigent-squad --create-namespace \
  -f values-prod.yaml
```

---

## Adding a new agent

In `inProcess` mode, adding a new agent requires only a new entry in the `agents` list — no new Deployment is created.

```yaml
agents:
  - name: security
    config: |
      name: security
      description: Cloud security posture specialist
      datasources: [aws_securityhub, guardduty]
    prompt: |
      You are a cloud security specialist agent.
      You assess security findings, prioritize CVEs, and recommend remediations.
      Always follow least-privilege principles.
```

The supervisor mounts all agent configs via a projected ConfigMap volume and loads them at startup. No chart upgrade is required — a `helm upgrade` that bumps the ConfigMap will trigger a rolling restart of the supervisor pod.

In `distributed` mode, add a new entry to the `services` map as well:

```yaml
services:
  security:
    enabled: true
    image:
      repository: aigent-squad/security-agent
      tag: "0.1.0"
    port: 8007
    mountAgents: true
    expose: false
    serviceAccount:
      create: true
      annotations:
        eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/aigent-squad-security"
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        memory: 512Mi
    scaling:
      autoscaling:
        kind: keda
        minReplicas: 1
        maxReplicas: 5
    networkPolicy:
      enabled: true
```

---

## Uninstall

```bash
helm uninstall aigent-squad --namespace aigent-squad
kubectl delete namespace aigent-squad
```

!!! warning
    If you enabled `externalSecrets`, the synced Kubernetes Secrets are deleted by Helm but the remote secrets in AWS Secrets Manager are **not** touched.
