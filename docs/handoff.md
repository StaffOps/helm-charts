# Handoff

Last updated: 2026-11-23 · Backstage docs-standard rollout · branch `main`

## State

helm-charts publishes three public charts through chart-releaser to
`https://staffops.github.io/helm-charts/` (see the
[README](https://github.com/StaffOps/helm-charts/blob/main/README.md)). On `main` the charts are
`aigent-squad` 0.9.6 (app 0.5.0), `anomaly-detection` 0.4.1 (app 0.11.0) and `generic` 0.1.0. The
published index stops at `aigent-squad` 0.9.5: the release run for 0.9.6 on 2026-11-16 failed with a
GitHub API 500 while creating the release, so 0.9.6 has no release, tag or index entry. The latest
lint-test runs succeed. The last chart change was on 2026-11-16; later commits only touch the
Backstage catalog. No work is in progress.

## Done

- Backstage catalog, tags and TechDocs ([`2e7156f`](https://github.com/StaffOps/helm-charts/commit/2e7156f), [`1df1d15`](https://github.com/StaffOps/helm-charts/commit/1df1d15))
- aigent-squad 0.9.6: `existingSecrets`, `appVersion` 0.5.0, `ct install` fixes (#3, [`89332e6`](https://github.com/StaffOps/helm-charts/commit/89332e6))
- anomaly-detection 0.4.1: ct-compliant maintainer, empty-registry image refs (#2, [`4583f22`](https://github.com/StaffOps/helm-charts/commit/4583f22))
- generic 0.1.0 (#1, [`9794797`](https://github.com/StaffOps/helm-charts/commit/9794797))
- aigent-squad image moved from Docker Hub to GHCR ([`2b681c8`](https://github.com/StaffOps/helm-charts/commit/2b681c8))

## In progress

- No open pull requests or issues. Check with `gh pr list -R StaffOps/helm-charts`.

## Next steps

1. Publish aigent-squad 0.9.6: re-run the `Release Charts` workflow and confirm the
   `aigent-squad-0.9.6` release and index entry (suggested, inferred).
2. Update the README chart table: it shows aigent-squad 0.6.0 / app 0.1.0 and anomaly-detection
   0.1.0 / app 0.7.0, and only one chart in the `helm search` example (suggested, inferred).
3. Delete the merged branches `feat/aigent-squad-0.9.6-existing-secrets`, `feat/generic-chart` and
   `fix/chart-maintainers` (suggested, inferred).

## Decisions

No ADRs. Recorded in the repo:

- The chart `staffops-anomaly-detection` was renamed `anomaly-detection` (`fdff52e`); the old tag
  `staffops-anomaly-detection-0.1.0` remains.
- Chart changes ship with their README, enforced by `.githooks/pre-commit`.

## Risks and open questions

- Until 0.9.6 is published, `helm install staffops/aigent-squad` installs 0.9.5, whose default
  `appVersion` 0.4.0 does not exist on GHCR (per the 0.9.6 changelog entry).
- The README links `LICENSE`, but the repo has no LICENSE file.
- `anomaly-detection` is not covered by `ct install` in CI, only by `ct lint`.
- Pushing `docs/` or `mkdocs.yml` to `main` deploys the public docs site.

## How to verify

```bash
gh run list -R StaffOps/helm-charts -L 5
helm repo add staffops https://staffops.github.io/helm-charts/ && helm search repo staffops --versions | head
docker run --rm -v "$PWD:/data" -w /data quay.io/helmpack/chart-testing:latest \
  ct lint --chart-dirs charts --target-branch main --all
```
