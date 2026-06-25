# chattea-workspace

ChatTea workspace repository.

## Repos
- `chattea-fe`
- `chattea-be`

## Local stack

```sh
cp .env.example .env
BUILDX_CONFIG=/tmp/chattea-buildx docker compose up -d postgres chattea-be
curl http://127.0.0.1:4000/healthz
cd chattea-be
pnpm run smoke:auth
```

`pnpm run smoke:auth` prerequisites:
- PostgreSQL is reachable at `127.0.0.1` on port `5433` (`POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` can override).
- `psql` is installed in PATH.
- `PHONE_CODE_PEPPER` is set consistently with backend behavior when not using default.

Containers:
- `chattea-be`
- `chattea-postgres`

Local compose runs only the backend and PostgreSQL. No Redis container is used.

Production mode is fail-closed: with `SERVICE_ENV=production`, backend startup requires `DATABASE_URL`, a non-default `PHONE_CODE_PEPPER`, Munjanara SMS env, and Cloudflare R2 env.

## Release

- `.github/workflows/ci.yml`: BE/FE checks on PR and `main`/`develop`, including live PostgreSQL integration tests.
- `.github/workflows/release.yml`: manual Hostinger BE deploy plus EAS Build/Update/Submit.

## Clone
```sh
git clone --recurse-submodules https://github.com/ChatTeaDot/chattea-workspace.git
```
