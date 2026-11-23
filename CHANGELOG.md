# Changelog

All notable changes to this repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
charts follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

Each chart is versioned on its own. chart-releaser publishes a GitHub Release and tag
`<chart>-<version>` for every new chart version merged to `main`. Chart-level detail lives in the
chart changelog when there is one ([aigent-squad](charts/aigent-squad/CHANGELOG.md)); this file lists
the recent releases.

## [Unreleased]

### Changed

- aigent-squad 0.9.6 (merged 2026-11-16, not published: the release job failed with a GitHub API
  500 while creating the release): `existingSecrets` injected through `envFrom`, `appVersion` 0.5.0 so
  the default image exists on GHCR, and `ct install` fixes (supervisor Service name, CI values).
  Details in the [chart changelog](charts/aigent-squad/CHANGELOG.md).
- Backstage `catalog-info.yaml`, technology tags and TechDocs.

## [anomaly-detection-0.4.1] - 2026-11-16

### Fixed

- Chart maintainer accepted by `ct lint`, and image references render correctly with an empty
  registry.

## [generic-0.1.0] - 2026-11-15

### Added

- Generic application chart: a Deployment, StatefulSet or DaemonSet plus Service, Ingress,
  HTTPRoute/GRPCRoute, ConfigMaps, Secrets, ExternalSecrets, PVC, HPA/KEDA/VPA, PDB, NetworkPolicy,
  RBAC, ServiceMonitor/PrometheusRule and `extraObjects`.

## [anomaly-detection-0.4.0] - 2026-07-19

### Changed

- `appVersion` 0.11.0.

### Fixed

- Default detection rules include `cluster` in every `by()` / `group_by`.

## [anomaly-detection-0.3.2] - 2026-07-16

### Fixed

- `honorLabels` on the ServiceMonitor, so the workload namespace label is kept.

## [aigent-squad-0.9.5] - 2026-07-16

### Changed

- `appVersion` 0.3.0 to 0.4.0, matching the published app tag. No template or values changes.

[Unreleased]: https://github.com/StaffOps/helm-charts/compare/anomaly-detection-0.4.1...HEAD
[anomaly-detection-0.4.1]: https://github.com/StaffOps/helm-charts/compare/anomaly-detection-0.4.0...anomaly-detection-0.4.1
[generic-0.1.0]: https://github.com/StaffOps/helm-charts/releases/tag/generic-0.1.0
[anomaly-detection-0.4.0]: https://github.com/StaffOps/helm-charts/compare/anomaly-detection-0.3.2...anomaly-detection-0.4.0
[anomaly-detection-0.3.2]: https://github.com/StaffOps/helm-charts/compare/anomaly-detection-0.3.1...anomaly-detection-0.3.2
[aigent-squad-0.9.5]: https://github.com/StaffOps/helm-charts/compare/aigent-squad-0.9.4...aigent-squad-0.9.5
