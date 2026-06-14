# Helm Charts

Helm charts for the [StaffOps](https://github.com/karlipegomes) suite of open-source Kubernetes operational tooling.

## Charts

| Chart | Version | App Version | Description |
|-------|---------|-------------|-------------|
| [staffops-anomaly-detection](./charts/staffops-anomaly-detection) | ![chart-version](https://img.shields.io/badge/chart-0.1.0-blue) | ![app-version](https://img.shields.io/badge/app-0.7.0-green) | Distributed anomaly detection for Kubernetes (Go controller + workers + Python ML) |

## Usage

### 1. Add the Helm repository

```bash
helm repo add staffops https://karlipegomes.github.io/helm-charts/
helm repo update
```

### 2. Search available charts

```bash
helm search repo staffops
```

```
NAME                                    CHART VERSION   APP VERSION     DESCRIPTION
staffops/staffops-anomaly-detection     0.1.0           0.7.0           Distributed anomaly detection for Kubernetes
```

### 3. Install a chart

```bash
helm install my-anomaly-detection staffops/staffops-anomaly-detection \
  --namespace monitoring \
  --create-namespace \
  --set datasources.victoriametrics.url=https://vm.example.com \
  --set datasources.loki.url=https://loki.example.com \
  --set datasources.alertmanager.url=https://alertmanager.example.com
```

For full configuration, see each chart's README:

- [staffops-anomaly-detection README](./charts/staffops-anomaly-detection/README.md)

## Repository Layout

```
helm-charts/
├── charts/
│   └── staffops-anomaly-detection/    # Anomaly detection stack
├── .github/
│   └── workflows/
│       ├── lint-test.yaml             # Validates PRs (helm lint, ct lint, ct install)
│       └── release.yaml               # Publishes charts to GitHub Pages on push to main
└── README.md                          # This file
```

The released charts are served from the [`gh-pages` branch](https://github.com/karlipegomes/helm-charts/tree/gh-pages), built automatically by [chart-releaser-action](https://github.com/helm/chart-releaser-action).

## Contributing

### Local validation

```bash
# Lint a chart
helm lint charts/staffops-anomaly-detection

# Render templates with default values
helm template my-release charts/staffops-anomaly-detection

# Run chart-testing locally (matches CI)
docker run --rm -v $(pwd):/data quay.io/helmpack/chart-testing:latest \
  ct lint --chart-dirs charts --target-branch main
```

### Releasing a new version

1. Bump `version` in `charts/<chart>/Chart.yaml` (SemVer)
2. Update `appVersion` if the upstream application version changed
3. Update the chart's `CHANGELOG.md` (when present)
4. Open a PR — `lint-test` workflow validates the change
5. Merge to `main` — `release` workflow packages the chart, publishes to GitHub Pages, and creates a GitHub Release with the `.tgz` asset

## License

Apache 2.0 — see [LICENSE](./LICENSE).
