# Chattea Infra Plan

## Summary
- Hostinger 기반 hosting, domain, secrets, observability 연동, 배포 기반.
- 담당:
  - hosting resources
  - secrets wiring
  - network/security boundaries
  - runtime env config

## Environments
- `dev`
- `prod`

## Core Hostinger
- Hostinger Node.js app or VPS for BE.
- Hostinger domain/DNS.
- PostgreSQL managed by Hostinger if available for selected plan; otherwise VPS PostgreSQL.
- Redis on VPS if realtime fanout/rate limit needs it.
- Object/file uploads via Hostinger storage or external object storage if presigned upload is required.
- hPanel/env config for runtime secrets.

## Backend Deploy
- deploy from Git or VPS release script.
- service env vars from Hostinger panel or VPS `.env`.
- health check endpoint.
- scale up Hostinger plan/VPS before adding multi-node deployment.

## Realtime
- WebSocket-compatible Node.js hosting or VPS reverse proxy.
- sticky session avoided; Redis pub/sub handles fanout.

## Phone Verification Infra
- SMS provider: TBD after Korean SMS sender requirements.
- env/secret:
  - `SMS_SENDER_ID`
  - `PHONE_CODE_PEPPER`
- `PHONE_CODE_PEPPER`는 secret output 금지.
- app/Sentry/Datadog 로그에서 `phone`, `code`, `signupToken`, `session` redaction 전제.
- 한국 SMS 발신번호/템플릿 제약은 prod 전 확인 필요.

## Security
- DB public access 금지.
- Redis public access 금지.
- upload storage private.
- presigned upload only.
- SSH key auth only if VPS.
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
- public exposure review for DB, Redis, uploads, admin panels.
- secret leakage review.
