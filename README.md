# ChatTea workspace

ChatTea is split into two Git submodules:

- `chattea-fe`: Expo React Native client
- `chattea-be`: NestJS and PostgreSQL backend

## Clone

```bash
git clone --recurse-submodules https://github.com/ChatTeaDot/chattea-workspace.git
```

## Local backend

```bash
cd chattea-be
pnpm install --frozen-lockfile
pnpm docker:up
curl http://127.0.0.1:4000/healthz
```

`pnpm docker:up` applies the tracked development Compose override. The base Compose file is production-only, binds the API to loopback for the reverse proxy, and fails closed without secure production settings.

See `chattea-be/README.md` for migrations, verification commands, and production configuration.

## Local mobile app

```bash
cd chattea-fe
pnpm install --frozen-lockfile
pnpm dev
```

See `chattea-fe/README.md` for native build requirements, environment variables, and release checks.

## Automation

- `.github/workflows/ci.yml` runs backend, PostgreSQL, container, deployment-contract, Expo config/prebuild, and production mobile bundle gates.
- `.github/workflows/release.yml` provides a manual EAS build target and builds, verifies, and deploys one immutable backend digest from `main` for the `all` and `backend` targets. Every production target is restricted to `main` and the protected `production` environment; EAS Build waits for its remote result before the job can pass.

OTA updates remain disabled because the mobile app has no `expo-updates` runtime contract. Store submission is an explicit external/manual prerequisite until an approved workflow can bind submission to the exact build ID produced from the selected main commit.

## Backend release runbook

`HOSTINGER_APP_DIR` must point to a clone of this workspace repository, not a standalone backend clone. The host must be able to update both public submodules and must keep the production environment in `chattea-be/.env` outside Git. It also needs Bash, Git, curl, `flock`, Docker, and a Docker Compose version that supports `up --wait`.

The protected GitHub `production` environment requires `HOSTINGER_HOST`, `HOSTINGER_HOST_FINGERPRINT`, `HOSTINGER_USER`, `HOSTINGER_SSH_KEY`, `HOSTINGER_APP_DIR`, `GHCR_READ_USERNAME`, and `GHCR_READ_TOKEN`. The GHCR token must be a classic personal access token limited to `read:packages`. Store the server host key's SHA256 fingerprint in `HOSTINGER_HOST_FINGERPRINT`; deployment refuses a host whose key does not match.

Repository Actions also require `CHATTEA_SUBMODULE_TOKEN` to read the private backend and frontend submodules. The mobile build target additionally requires `EXPO_TOKEN`.

A manual run from `main` checks out the exact workspace commit and submodules, builds one `linux/amd64` and `linux/arm64` image, attaches provenance and an SBOM, scans both platforms, signs and verifies the digest with GitHub OIDC, and smoke-tests that same digest. Only the validated 64-hex digest component crosses the smoke and SSH boundaries; the GHCR registry, repository, and `@sha256:` prefix are fixed in code and production Compose. The VPS pulls the digest, runs migrations once, and starts the API and maintenance services with `--no-build`. `.deploy/current` records the last healthy workspace revision and image digest atomically. A failed, interrupted, or timed-out rollout restores that revision and digest without rebuilding source.

Database migrations are forward-only. Take a provider snapshot or verify point-in-time recovery before a migration release; application rollback does not reverse an applied schema migration.
