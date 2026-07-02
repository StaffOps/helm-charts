# Changelog — aigent-squad chart

All notable changes to the `aigent-squad` Helm chart are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versions follow
[SemVer](https://semver.org/).

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
