# Automated Software Delivery Pipeline

GitHub Actions · Docker · Python (Flask) · Trivy · GHCR

```
 push / PR
    │
    ▼
┌────────┐   ┌───────────────────────────────────┐   ┌─────────────────────────────────────┐
│ TEST   │──▶│ BUILD → TRIVY SCAN → PUSH to GHCR │──▶│ DEPLOY (main only, approval-gated)  │
│ ruff   │   │ fail on fixable HIGH/CRITICAL;    │   │ 1 candidate pre-flight health check │
│ pytest │   │ push only if clean; SARIF report  │   │ 2 swap live, re-check               │
│ ≥90% % │   │ tags: sha-<7> and latest          │   │ 3 auto-rollback on failure          │
└────────┘   └───────────────────────────────────┘   │ 4 external smoke test → rollback    │
                                                      └─────────────────────────────────────┘
 Manual rollback: "Manual rollback" workflow (any tag) or scripts/rollback.sh
```

PRs run test + build + scan only (nothing published or deployed).

## Try it locally (no GitHub, no server)

```bash
pip install -r requirements-dev.txt && ruff check . && pytest
./scripts/demo-local.sh     # needs Docker + curl
```
The demo walks through: first deploy → healthy upgrade → bad release rejected in pre-flight
(live untouched) → bad release caught after swap (auto-rollback) → manual rollback.

## Set up on GitHub

1. Push this repo to GitHub (default branch `main`).
2. **Server**: any Linux host with Docker; create a deploy user in the `docker` group with an SSH key.
3. **Repo secrets**: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY` (private key),
   `DEPLOY_KNOWN_HOSTS` (output of `ssh-keyscan -t ed25519 <host>`).
4. **Repo variable**: `DEPLOY_URL` (e.g. `http://<host>:8080`). Open port 8080 on the server.
5. **Settings → Environments → production**: add required reviewers for a manual approval gate.
6. **Settings → Actions → General**: allow workflow read/write permissions (needed for GHCR push).
7. After the first push, set the GHCR package visibility/access if the server pull is denied
   (package → Package settings → give the repo access).

## Demonstrating rollback in GitHub

- **Auto-rollback**: Actions → CI/CD → *Run workflow* → `simulate_failure = candidate` (rejected, live untouched)
  or `live` (swapped, fails, previous tag restored; job turns red).
- **Manual rollback**: Actions → *Manual rollback* → blank tag = previous release, or enter e.g. `sha-1a2b3c4`.

## Design notes

- Images are tagged by commit SHA (immutable); `latest` is convenience only. Rollback always targets a SHA.
- The scan happens before the push, so a vulnerable image never reaches the registry.
  `ignore-unfixed` keeps the gate actionable (only CVEs with a fix available block the build).
- Container runs as non-root, multi-stage build, with a Docker `HEALTHCHECK`.
- `SIMULATE_UNHEALTHY` / `SIMULATE_FAILURE_STAGE` exist purely to demo rollback; remove them for real services.
- Third-party actions are pinned to major versions / a release; pin to commit SHAs for stricter supply-chain control.
- Scaling up: replace the SSH step with `kubectl set image` / `helm upgrade --atomic` / ECS; the pipeline shape stays the same.
