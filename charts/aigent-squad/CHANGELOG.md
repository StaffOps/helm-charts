# Changelog — aigent-squad chart

All notable changes to the `aigent-squad` Helm chart are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versions follow
[SemVer](https://semver.org/).

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
- `global.labels.CostCenter` default is now the neutral placeholder `CHANGE-ME`.
  CostCenter is org-specific and subject to an AWS tag policy — it MUST be set
  to a policy-approved value in an environment overlay, never hardcoded here.

### Notes
- `topology: distributed` renders specialist Deployments but is **not
  functional** yet — the supervisor only routes in-process (see the app
  ROADMAP backlog "Distributed topology (code)"). Use `inProcess` (default).
