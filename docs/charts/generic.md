# generic

**Chart:** `staffops/generic`  
**Version:** `0.1.0` · **App Version:** `1.27-alpine` (default image only)  
**Source:** [StaffOps/helm-charts](https://github.com/StaffOps/helm-charts/tree/main/charts/generic)

Generic application chart: **one workload** (Deployment, StatefulSet or DaemonSet) plus everything that usually goes around it. Cloud-agnostic — the same values shape works on EKS, GKE, AKS and on-premises (MetalLB, local-path/Longhorn/Ceph, Istio/Envoy/NGINX gateways, Vault).

Every resource is named after the **release** (`helm install orders-api` → Deployment, Service, ... `orders-api`).

## TL;DR

```bash
helm repo add staffops https://staffops.github.io/helm-charts/
helm install orders-api staffops/generic -n orders --create-namespace \
  --set image.repository=ghcr.io/acme/orders-api \
  --set image.tag=1.4.2 \
  --set ports[0].name=http,ports[0].containerPort=8080
```

## What it renders

| Resource | Toggle | Notes |
|---|---|---|
| Deployment / StatefulSet / DaemonSet | `workload.kind` | `strategy.rollingUpdate` dropped automatically for `Recreate`/`OnDelete` |
| Service | `service.enabled` + exposed `ports` | ClusterIP/NodePort/LoadBalancer; skipped when no port is exposed |
| Headless Service | automatic for StatefulSet, `headlessService.enabled` otherwise | |
| ConfigMap(s) | `configMaps.<name>` | as env (`envFrom`), directory or single file (`subPath`), optional `tpl` |
| Secret(s) | `secrets.<name>` | for dev/CI — prefer ExternalSecrets in production |
| ExternalSecret(s) | `externalSecrets.<name>` | any ESO provider (AWS SM, GCP SM, Azure KV, Vault, ...) |
| PersistentVolumeClaim | `persistence.enabled` | Deployment: one PVC · StatefulSet: volumeClaimTemplate |
| Ingress | `ingress.enabled` | any controller |
| HTTPRoute / GRPCRoute | `httpRoute.enabled` / `grpcRoute.enabled` | Gateway API v1, optional HTTP→HTTPS redirect route |
| HPA | `autoscaling.enabled` | autoscaling/v2 |
| KEDA ScaledObject + TriggerAuthentication | `keda.enabled` | mutually exclusive with HPA |
| VPA | `vpa.enabled` | |
| PodDisruptionBudget | `pdb.enabled` (default on) | not for DaemonSets |
| NetworkPolicy | `networkPolicy.enabled` | raw rules + optional DNS egress |
| ServiceAccount / Role / ClusterRole | `serviceAccount.create`, `rbac.create` | |
| ServiceMonitor / PrometheusRule | `serviceMonitor.enabled`, `prometheusRule.enabled` | Prometheus Operator (also honored by VictoriaMetrics operator) |
| Anything else | `extraObjects` | maps or strings, rendered through `tpl` |
| Helm test | `tests.enabled` | `wget` against the Service |

Out of the box: Pod Security **restricted** (non-root, read-only rootfs, seccomp, no capabilities), `/tmp` emptyDir, API token not mounted, soft pod anti-affinity, pods roll when chart-managed ConfigMaps/Secrets change.

Invalid combinations fail at render time (unknown `workload.kind`, HPA + KEDA, autoscaling a DaemonSet, PVC on a DaemonSet without `existingClaim`, Ingress/Route without a Service, a numeric `image.tag`, ...).

## Examples

### API (Deployment + HTTPRoute + HPA + ESO)

```yaml
image:
  registry: ghcr.io
  repository: acme/orders-api
  tag: "1.4.2"
ports:
  - name: http
    containerPort: 8080
    servicePort: 80
  - name: metrics
    containerPort: 9090
livenessProbe:
  httpGet: {path: /healthz, port: http}
readinessProbe:
  httpGet: {path: /ready, port: http}
resources:
  requests: {cpu: 250m, memory: 256Mi}
  limits: {memory: 256Mi}
env:
  LOG_LEVEL: info
  POD_IP:
    valueFrom:
      fieldRef: {fieldPath: status.podIP}
configMaps:
  config:
    mountPath: /etc/orders
    data:
      app.yaml: |
        listen: :8080
externalSecrets:
  db:
    envFrom: true
    secretStoreRef: {kind: ClusterSecretStore, name: vault}
    data:
      - secretKey: DATABASE_URL
        remoteRef: {key: orders/prod, property: database_url}
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
pdb:
  minAvailable: 2
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
httpRoute:
  enabled: true
  parentRefs:
    - {name: public, namespace: gateway, sectionName: https}
  hostnames: [orders.example.com]
  httpsRedirect:
    enabled: true
serviceMonitor:
  enabled: true
  port: metrics
```

### StatefulSet with storage

```yaml
workload:
  kind: StatefulSet
  podManagementPolicy: Parallel
  persistentVolumeClaimRetentionPolicy: {whenDeleted: Retain, whenScaled: Retain}
replicaCount: 3
persistence:
  enabled: true
  storageClass: gp3        # gp3 / premium-rwo / managed-csi / longhorn / local-path ...
  size: 20Gi
  mountPath: /data
```

Peers reach each other at `<release>-<ordinal>.<release>-headless.<namespace>.svc`.

### Node agent (DaemonSet)

```yaml
workload:
  kind: DaemonSet
ports:
  - name: metrics
    containerPort: 2020
tolerations:
  - operator: Exists
extraVolumes:
  - name: varlog
    hostPath: {path: /var/log, type: Directory}
extraVolumeMounts:
  - {name: varlog, mountPath: /host/var/log, readOnly: true}
```

hostPath volumes need a namespace with Pod Security `privileged` (or at least `baseline` without hostPath restrictions).

### Worker without a Service, scaled by KEDA

```yaml
ports: []
livenessProbe: {exec: {command: [/bin/healthcheck]}}
readinessProbe: {}
keda:
  enabled: true
  minReplicaCount: 0
  maxReplicaCount: 20
  triggers:
    - type: rabbitmq
      metadata: {queueName: orders, mode: QueueLength, value: "50"}
      authenticationRef: {name: "{{ .Release.Name }}-rabbit"}
  triggerAuthentications:
    "{{ .Release.Name }}-rabbit":
      secretTargetRef:
        - {parameter: host, name: rabbit-conn, key: url}
```

## Cloud / on-premises cheat sheet

| Concern | EKS | GKE | AKS | On-premises |
|---|---|---|---|---|
| Pod identity | `serviceAccount.annotations.eks.amazonaws.com/role-arn` | `iam.gke.io/gcp-service-account` | `azure.workload.identity/client-id` + `podLabels.azure.workload.identity/use: "true"` | Vault/ESO, SPIFFE |
| Internal LB | `service.beta.kubernetes.io/aws-load-balancer-scheme: internal` (+ `loadBalancerClass: service.k8s.aws/nlb`) | `networking.gke.io/load-balancer-type: Internal` | `service.beta.kubernetes.io/azure-load-balancer-internal: "true"` | MetalLB `metallb.universe.tf/address-pool` |
| Storage | `gp3` | `premium-rwo` | `managed-csi` | `longhorn`, `ceph-rbd`, `local-path` |
| RWX storage | EFS | Filestore | `azurefile-csi` | NFS, CephFS |
| Image mirror | ECR pull-through → `global.imageRegistry` | Artifact Registry remote repo | ACR cache | Harbor / Nexus proxy → `global.imageRegistry` |
| Secrets | ESO + AWS SM | ESO + GCP SM | ESO + Key Vault | ESO + Vault |

`global.imageRegistry` rewrites every image the chart renders (main container and test pod), which is what an air-gapped cluster needs. Images inside `initContainers`, `sidecars` and `extraObjects` are taken as written.

## Notable behaviors

- **Replicas and autoscaling**: `spec.replicas` is omitted when HPA or KEDA is enabled, so GitOps tools don't fight the autoscaler.
- **volumeClaimTemplates** carry only selector labels. That field is immutable, so a label that changes with each version would break `helm upgrade`.
- **tpl**: env values, hosts/hostnames, `extraObjects`, `extraVolumes`, `initContainers`/`sidecars`, NetworkPolicy rules and ESO refs go through `tpl`. ConfigMap/Secret data does too, but only with `tpl: true`. PrometheusRule groups are never templated, so `{{ $labels }}` keeps working.
- **ConfigMap/Secret with `subPath`** do not hot-reload. Pods still roll on chart-managed changes (`rollOnConfigChange`). ExternalSecret *content* changes are not visible to Helm, so use [Reloader](https://github.com/stakater/Reloader) via `podAnnotations` if you need that.
- **Deployment + RWO PVC + >1 replica** gets a warning in NOTES. Use RWX or a StatefulSet.
- **NetworkPolicy + Istio ambient**: in ambient mode traffic reaches the pod over HBONE on port 15008 and kubelet probes come from `169.254.7.127`. A policy that only allows the app port blocks everything. Set `networkPolicy.istioAmbient: true`: it adds 15008 to every ingress rule that lists ports (keeping its `from` peers) and allows the probe address.
- **ClusterRole/ClusterRoleBinding** are named `<namespace>-<release>` so the same release name in two namespaces doesn't collide.

## Values

See [`values.yaml`](https://github.com/StaffOps/helm-charts/blob/main/charts/generic/values.yaml). Every key is commented inline.
