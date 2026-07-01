# Chattea Infra Plan

## Summary
- Hostinger VPS 기반 hosting, domain, secrets, observability 연동, 배포 기반.
- 담당:
  - hosting resources
  - secrets wiring
  - network/security boundaries
  - runtime env config

## Environments
- `dev`
- `prod`

## Core Hostinger
- Hostinger VPS for BE.
- Hostinger domain/DNS.
- PostgreSQL on VPS unless Hostinger managed PostgreSQL is selected.
- PostgreSQL on VPS for persisted app state.
- Object/file uploads via Cloudflare R2.
- VPS `.env` or secret manager for runtime secrets.

## Backend Deploy
- GitHub Actions deploy to Hostinger VPS.
- deploy via SSH or Docker Compose; choose one during BE scaffold.
- service env vars from VPS `.env` or secret manager.
- health check endpoint.
- scale up VPS before adding multi-node deployment.

## Realtime
- WebSocket-compatible Node.js runtime on VPS.
- v1 runs as one BE instance; add PostgreSQL-backed fanout only if multi-instance deployment becomes required.

## Phone Verification Infra
- SMS provider: 문자나라.
- env/secret:
  - `SMS_SENDER_ID`
  - `PHONE_CODE_PEPPER`
- `PHONE_CODE_PEPPER`는 secret output 금지.
- app/Sentry/Datadog 로그에서 `phone`, `code`, `signupToken`, `session` redaction 전제.
- 문자나라 발신번호 등록, API credential, API 발송 IP 제한은 prod 전 확인 필요.

## Security
- DB public access 금지.
- upload storage private.
- presigned upload only.
- Cloudflare R2 bucket private; BE issues short-lived presigned URLs.
- SSH key auth only.
- admin panel credentials and env secrets must not be committed.

## Observability
- Datadog agent/log forwarding if VPS; app-level SDK otherwise.
- Sentry DSN as secret.
- app env tags:
  - `service`
  - `env`
  - `version`

## Tests
- deployment dry run.
- health check.
- DNS/SSL check.
- public exposure review for DB, uploads, admin panels.
- secret leakage review.
