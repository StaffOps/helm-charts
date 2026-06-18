# Helm Charts

Kubernetes-ready Helm charts for the StaffOps suite.

---

## Repository

```bash
helm repo add staffops https://staffops.github.io/helm-charts/
helm repo update
```

---

## Available charts

| Chart | Version | Description |
|---|---|---|
| [`aigent-squad`](charts/aigent-squad.md) | 0.6.0 | Multi-agent platform — supervisor + 5 specialists |
| [`anomaly-detection`](charts/anomaly-detection.md) | 0.1.0 | Distributed anomaly detection — Go controller + ML |

---

## Requirements

- Kubernetes 1.24+
- Helm 3.10+

---

## License

Apache 2.0 — Copyright (c) StaffOps Contributors
