# Changelog — aigent-squad chart

All notable changes to the `aigent-squad` Helm chart are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versions follow
[SemVer](https://semver.org/).

## [0.9.6] - 2026-11-15

### Added
- `existingSecrets: []` — list of pre-existing K8s Secret names injected via
  `envFrom` into every workload (no External Secrets Operator required).
  Combines with `externalSecrets` when both are set (ESO secrets first).
- `values.yaml` documents the app's spec-28 LLM provider settings
  (`LLM_PROVIDER=openai`, `OPENAI_BASE_URL`, `LLM_MODEL_ID`, optional
  `LLM_PRICE_*` in `global.env`; `OPENAI_API_KEY` in a Secret) and that the
  Bedrock Guardrail (L1) is off by design when the provider is not Bedrock.

### Changed
- `appVersion` `0.4.0` → `0.5.0`. Since the image moved to GHCR
  (`ghcr.io/staffops/aigent-squad`), the default install resolved to
  `:0.4.0`, a tag that only ever existed on Docker Hub — GHCR's first release
  tag is `0.5.0`. The default `values.yaml` now pulls an image that exists.

### Fixed
- `ci/ct-values.yaml` pointed at a dead private registry
  (`harbor.bdc.app.br/aigent-squad/supervisor:0.1.0`) — now the public GHCR
  image at `Chart.appVersion`, with readiness on `/healthz` (the kind CI
  cluster has no DynamoDB, so the supervisor's `/ready` can never pass there).
- Gateway `SUPERVISOR_URL` (and the distributed agents' gateway URL) used
  `{{ .Release.Name }}-supervisor`, but the Service is named via
  `aigent-squad.fullname` (`<release>-aigent-squad-supervisor` unless the
  release name contains the chart name) — any other release name left the
  gateway unable to reach the supervisor. Now rendered with the
  `aigent-squad.serviceFullname` helper. Found by the first `ct install`.
- `ci/ct-values.yaml`: in-cluster Redis enabled (the app requires
  `REDIS_HOST` at startup) and the supervisor uses the image's baked-in
  agents (the inline test agent had drifted from the app's `AgentConfig`
  schema).
- Stale links: `home`/`sources` → `StaffOps/aigent-squad`, NOTES docs link,
  README image (Docker Hub → public GHCR).
- `Chart.yaml` maintainer `StaffOps Contributors` → `StaffOps` — `ct lint`
  validates maintainer names against the GitHub users API and the old value
  404'd (first PR-based CI run of the repo exposed it).

## [0.9.5] - 2026-07-16

### Changed
- `appVersion` `0.3.0` → `0.4.0`, restoring coherence with the app tag
  actually published (spec-34's `RELEASE.md` cut `v0.4.0` on 2026-07-15;
  this chart bump follows to close BACKLOG B-25's chart-side gap — see
  `RELEASE.md` Phase 3). No template/values changes; `global.image.registry`
  default (`""`) + `repository: karlipegomes/aigent-squad` already resolve
  to the public Docker Hub tag, `karlipegomes/aigent-squad:0.4.0`.

## [0.9.4] - 2026-07-15

### Fixed
- `servicemonitor.yaml`'s scrape `path` now targets `/metrics/` (trailing
  slash) instead of `/metrics`. A bare `/metrics` 307-redirects (Starlette
  `Mount`'s own routing behavior for the mounted metrics sub-app, verified
  live) — most scrapers follow it fine, but the trailing slash skips the
  extra hop on every scrape. No `ServiceMonitor`-users were left broken by
  this (0.9.3's `ServiceMonitor` still worked, just with one redirect per
  scrape) — this is a follow-up optimization, not a functional fix.

### Added
- **Optional LibreChat + in-cluster MongoDB sub-chart** (`librechat.enabled`,
  default `false`) — a minimal, non-production chat UI for the squad's
  OpenAI-compatible bridge (spec 29), for quick homologation/demo use.
  `templates/librechat.yaml`: single-pod MongoDB `StatefulSet` (no HA, no
  auth — same posture as `redis.inCluster`) + a LibreChat `Deployment`
  pre-wired with a `custom` endpoint pointing at the release's own gateway
  Service (auto-computed unless `librechat.baseURL` is set). JWT/CREDS
  secrets auto-generate per install if not supplied (`librechat.jwtSecret`
  etc. to pin them across upgrades). The API key LibreChat needs to
  authenticate against the gateway resolves in priority order:
  `librechat.apiKey` → `librechat.apiKeySecretName` → automatic reuse of the
  existing `externalSecrets.secrets[]`-provisioned Secret when
  `externalSecrets.enabled=true`. Not a hardened multi-user LibreChat
  deployment — for anything beyond quick homologation, run LibreChat
  separately with production-grade Mongo and secret management.

## [0.9.3] - 2026-07-15

### Added
- **Prometheus `/metrics` direct-scrape support**, pairing with the app's
  bump to `otel-helper` v0.2.0+ (which can run the OTLP push exporter and a
  Prometheus exporter on the same MeterProvider). New
  `global.otel.metricsPrometheusScrape` (default `true`) sets
  `OTEL_METRICS_EXPORTER=otlp,prometheus` + `OTEL_HELPER_METRICS_PORT=0` so
  each service mounts `/metrics` on its own app port instead of otel-helper's
  standalone listener (which can't bind under multi-worker servers).
- New `serviceMonitor.*` values block (default `enabled: false` — the
  Prometheus Operator CRD isn't guaranteed to exist on every cluster) and
  `templates/servicemonitor.yaml`: one `ServiceMonitor` per enabled service,
  targeting the existing `http` port + `/metrics` path. No new Service or
  port — reuses what's already there.

## [0.9.2] - 2026-07-02

### Changed
- In-cluster Redis is now a **StatefulSet with a PVC** (was a Deployment +
  emptyDir). Cache and rate/budget counters survive pod restarts — important on
  spot instances, which reschedule frequently. Persistence (AOF `everysec`) is
  re-enabled because `/data` is now a writable PVC (the read-only-rootfs reason
  for disabling it no longer applies). New `redis.inCluster.persistence`
  (`size`, `storageClass`). Caveat: EBS PVC is AZ-locked — cross-AZ reschedule
  waits for the volume's AZ; use managed ElastiCache for cross-AZ HA.

## [0.9.1] - 2026-07-02

### Changed
- `appVersion` `0.3.0-dev` → `0.3.0` (stable release cut; image published by the
  project pipeline).
- `global.labels` is now an empty, optional map — the chart ships **no**
  org-specific labels (removed the cost-allocation tag defaults). Add whatever
  your platform requires per deployment.

## [0.9.0] - 2026-07-01

First cluster-validated release (devops-core, in-process topology). All fixes
below were found and validated deploying the chart against a real EKS cluster
with a restricted pod securityContext (`readOnlyRootFilesystem`) and External
Secrets Operator.

### Fixed
- **ExternalSecret apiVersion** `external-secrets.io/v1beta1` → `v1`. ESO ≥ 0.10
  no longer serves `v1beta1`; the old value made `helm install` fail with
  "no matches for kind ExternalSecret".
- **In-cluster Redis readiness under read-only rootfs.** Redis tried to write an
  RDB snapshot to `/data` and, unable to (read-only fs), tripped
  `stop-writes-on-bgsave-error` → readiness never passed. Disabled persistence
  (`--save "" --appendonly no`) and mounted an `emptyDir` at `/data`. This Redis
  is an ephemeral dev cache; production uses managed ElastiCache (`redis.host`).
- **git agentsSource clone under read-only rootfs.** The git-sync initContainer
  cloned into `/tmp/repo`, which is read-only → "Read-only file system". Now
  clones into `/agents/.repo` (the writable emptyDir), copies, and cleans up.
- **Built-in `agents[]` config schema** updated to the current `AgentConfig`
  (spec 22): `domain`, `capabilities`, and `datasources[]` as objects with a
  `type`. The previous string-list datasources crashed the supervisor with a
  Pydantic ValidationError.

### Changed
- `appVersion` `0.2.0` → `0.3.0-dev`. The `0.2.0` image predates the edge
  gateway (spec 31); `0.3.0-dev` is the first image containing both tiers.
- `global.labels` is now an empty, optional map. The chart no longer ships any
  org-specific labels (removed the cost-allocation tags) — add whatever your
  platform requires per deployment.

### Notes
- `topology: distributed` renders specialist Deployments but is **not
  functional** yet — the supervisor only routes in-process (see the app
  ROADMAP backlog "Distributed topology (code)"). Use `inProcess` (default).
