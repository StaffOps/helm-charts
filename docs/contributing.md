# Contributing

Thank you for contributing to the StaffOps Helm Charts repository. This guide covers everything you need to develop, test, and submit changes.

---

## Prerequisites

Install the following tools before you begin:

| Tool | Minimum version | Install |
|---|---|---|
| [Helm](https://helm.sh/docs/intro/install/) | 3.10 | `brew install helm` |
| [chart-testing (ct)](https://github.com/helm/chart-testing) | 3.10 | `brew install chart-testing` |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/) | 0.20 | `brew install kind` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.27 | `brew install kubectl` |
| [yamllint](https://yamllint.readthedocs.io/) | 1.32 | `brew install yamllint` |

!!! tip "macOS one-liner"
    ```bash
    brew install helm chart-testing kind kubectl yamllint
    ```

---

## Repository structure

```
helm-charts/
├── charts/
│   ├── aigent-squad/           # Chart source
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── values-distributed.yaml
│   │   ├── ci/
│   │   │   └── ct-values.yaml  # Values used during `ct install`
│   │   └── templates/
│   └── staffops-anomaly-detection/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── ci/
│       │   └── ct-values.yaml
│       └── templates/
├── docs/                       # MkDocs source
├── .github/
│   └── workflows/
│       ├── lint-test.yaml      # PR: lint + install
│       ├── release.yaml        # merge to main: chart-releaser
│       └── docs.yml            # merge to main: MkDocs deploy
├── mkdocs.yml
└── README.md
```

---

## Lint locally

`ct lint` validates chart structure, `Chart.yaml` fields, and runs `helm lint` against every values file under `ci/`.

```bash
# From the repository root
ct lint --target-branch main
```

`ct` detects which charts changed relative to `main` and lints only those. If you want to lint all charts regardless of changes:

```bash
ct lint --target-branch main --all
```

Common lint failures and fixes:

| Error | Fix |
|---|---|
| `icon is recommended` | Add `icon:` URL to `Chart.yaml` |
| `version not incremented` | Bump `version` in `Chart.yaml` — required for every chart change |
| `yaml: line N: ...` | Fix YAML syntax — run `yamllint charts/<name>/` for details |
| Missing required value | Add the required value to `ci/ct-values.yaml` |

---

## Test locally with kind

`ct install` spins up a `kind` cluster, installs the chart with each values file under `ci/`, runs Helm tests (`helm test`), and tears down.

=== "Automatic kind cluster"

    ```bash
    ct install --target-branch main
    ```

    `ct` creates and manages the kind cluster automatically.

=== "Bring your own cluster"

    ```bash
    # Create a kind cluster
    kind create cluster --name helm-test

    # Install against the existing cluster
    ct install --target-branch main --helm-extra-set-args "--timeout=120s"

    # Clean up
    kind delete cluster --name helm-test
    ```

!!! note
    `ct install` installs the chart with each file found under `charts/<name>/ci/`. Keep `ct-values.yaml` minimal — only the values required for the chart to render and pass `helm test` on a plain Kubernetes cluster (no cloud dependencies, no CRD-dependent features).

---

## Versioning conventions

This repository follows [Semantic Versioning](https://semver.org/) with two independent version fields in `Chart.yaml`:

```yaml
version: 0.6.0      # Helm chart package version — bump on every chart change
appVersion: "0.1.0" # Application (container image) version — bump when the image changes
```

**Rules:**

- **`version`** — increment on **every** PR that touches chart templates, values, or `Chart.yaml`. Use PATCH for backwards-compatible fixes, MINOR for new opt-in features, MAJOR for breaking changes to values or behavior.
- **`appVersion`** — update only when the container image tag changes. Wrap in quotes (it is treated as a string by Helm).
- Never set `version` and `appVersion` to the same value unless they happen to coincide — they track different things.
- Do **not** use pre-release suffixes (`-alpha`, `-beta`) for chart `version`; the chart-releaser action publishes every version it finds.

---

## Opening a pull request

1. **Fork** the repository and create a feature branch from `main`:
   ```bash
   git checkout -b feat/my-chart-improvement
   ```

2. Make your changes. Bump `version` in `Chart.yaml` for every chart you touch.

3. Run lint and test locally before pushing:
   ```bash
   ct lint --target-branch main
   ct install --target-branch main
   ```

4. Push your branch and open a PR against `main`:
   ```bash
   git push origin feat/my-chart-improvement
   gh pr create --fill
   ```

5. The **lint-test** CI workflow runs automatically. All checks must pass before the PR can be merged.

6. A maintainer will review and merge. The **release** workflow publishes the new chart version automatically on merge to `main`.

---

## Adding a new chart

### Minimum required structure

```
charts/<chart-name>/
├── Chart.yaml          # apiVersion, name, version, appVersion, description, type
├── values.yaml         # All configurable values with inline comments
├── .helmignore         # Standard Helm ignore file
├── ci/
│   └── ct-values.yaml  # Minimal values for ct install (no cloud dependencies)
└── templates/
    ├── _helpers.tpl    # Named templates: fullname, labels, selectorLabels
    ├── deployment.yaml
    ├── service.yaml
    ├── serviceaccount.yaml
    ├── NOTES.txt
    └── tests/
        └── test-connection.yaml
```

### Chart.yaml example

```yaml
apiVersion: v2
name: my-chart
description: One-line description of what this chart does
type: application
version: 0.1.0
appVersion: "1.0.0"
keywords:
  - staffops
  - kubernetes
home: https://github.com/StaffOps/helm-charts
sources:
  - https://github.com/StaffOps/helm-charts
maintainers:
  - name: StaffOps Contributors
    url: https://github.com/StaffOps
icon: https://staffops.github.io/helm-charts/assets/logo.png
```

### ci/ct-values.yaml rules

- Must contain only values that make the chart install successfully on a **bare kind cluster**.
- Do **not** set image tags to `latest` — pin to a real tag.
- Do **not** enable CRD-dependent features (`serviceMonitor`, `vmRule`, `externalSecrets`, KEDA, etc.).
- Do **not** include cloud-specific endpoints — use `localhost` or stub values where required.

### NOTES.txt

Always include a useful `NOTES.txt` that prints the release name, namespace, and next steps. This is shown to users after `helm install`.

### Helm test

Include at least one test pod under `templates/tests/` that verifies the service is reachable:

```yaml
# templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "my-chart.fullname" . }}-test-connection"
  labels:
    {{- include "my-chart.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
spec:
  restartPolicy: Never
  containers:
    - name: wget
      image: busybox
      command: ["wget"]
      args: ["--spider", "--timeout=5", "http://{{ include "my-chart.fullname" . }}:{{ .Values.service.port }}/healthz"]
```

### Add docs

Create a documentation page at `docs/charts/<chart-name>.md` following the structure of existing chart docs: TL;DR, prerequisites, values reference table, production example, and troubleshooting.

Update `mkdocs.yml` to add the page to the `nav`:

```yaml
nav:
  - Charts:
      - My Chart: charts/my-chart.md
```

---

## CI/CD pipeline

```
PR opened / updated
       │
       ▼
lint-test.yaml
  ├─ ct lint --target-branch main    (checks changed charts only)
  └─ ct install --target-branch main (kind cluster, helm test)
       │
       ▼ (PR merged to main)
release.yaml  (chart-releaser-action)
  ├─ Packages changed charts → .tgz
  ├─ Creates a GitHub Release + tag (e.g. aigent-squad-0.6.0)
  ├─ Uploads .tgz to the release assets
  └─ Updates gh-pages/index.yaml    ← Helm repository index
       │
       ▼ (if docs/** or mkdocs.yml changed)
docs.yml  (MkDocs + peaceiris/actions-gh-pages)
  ├─ mkdocs build --site-dir site
  └─ peaceiris/actions-gh-pages (keep_files: true)
       └─ Deploys HTML to gh-pages alongside index.yaml
```

!!! warning "Never manually push to `gh-pages`"
    The `gh-pages` branch is managed by two automated workflows. Manual pushes may corrupt the Helm `index.yaml` or the MkDocs site. If something goes wrong, re-run the relevant workflow from the GitHub Actions UI.
