#!/usr/bin/env bash
set -euo pipefail

workspace_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
compose_file="$workspace_dir/chattea-be/docker-compose.production.yml"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
environment_file="$test_dir/production.env"
candidate_digest=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
candidate_ref=ghcr.io/chatteadot/chattea-be@sha256:$candidate_digest
export CANDIDATE_REF="$candidate_ref"

printf '%s\n' \
  'POSTGRES_HOST=postgres' \
  'POSTGRES_PORT=5432' \
  'POSTGRES_USERNAME=chattea' \
  'POSTGRES_PASSWORD=production-postgres-secret' \
  'POSTGRES_DATABASE=chattea' \
  'POSTGRES_SSL=false' \
  'JWT_ACCESS_TOKEN_SECRET=production-access-secret' \
  'JWT_REFRESH_TOKEN_SECRET=production-refresh-secret' \
  'JWT_ACCESS_TOKEN_EXP=15m' \
  'JWT_REFRESH_TOKEN_EXP=30d' \
  'SIGNUP_TOKEN_SECRET=production-signup-secret' \
  'KAKAO_SIGNUP_TOKEN_SECRET=production-kakao-signup-secret' \
  'KAKAO_CLIENT_ID=production-kakao-client' \
  'KAKAO_CALLBACK_URL=https://api.example.com/api/auth/kakao/callback' \
  'PHONE_CODE_PEPPER=production-phone-pepper' \
  'SMS_PROVIDER_URL=https://sms.example.com/send' \
  'SMS_PROVIDER_AUTHORIZATION=production-sms-authorization' \
  'SMS_SENDER_ID=production-sender' \
  'R2_ACCOUNT_ID=production-r2-account' \
  'R2_ACCESS_KEY_ID=production-r2-access-key' \
  'R2_SECRET_ACCESS_KEY=production-r2-secret' \
  'R2_BUCKET=chattea-production' \
  'R2_PUBLIC_BASE_URL=https://images.example.com' \
  'REVENUECAT_WEBHOOK_SECRET=production-revenuecat-secret' \
  'REVENUECAT_IOS_APP_ID=production-revenuecat-ios' \
  'REVENUECAT_ANDROID_APP_ID=production-revenuecat-android' \
  'CLIENT_URL=https://app.example.com' \
  'TRUST_PROXY=loopback' >"$environment_file"

if env -u CHATTEA_BACKEND_DIGEST docker compose --env-file "$environment_file" -f "$compose_file" config --format json \
  >"$test_dir/missing-image.json" 2>"$test_dir/missing-image.err"; then
  printf '%s\n' "production compose accepted a missing image digest" >&2
  exit 1
fi

if env -u CHATTEA_BACKEND_DIGEST CHATTEA_BACKEND_IMAGE=ghcr.io/chatteadot/chattea-be:latest \
  docker compose --env-file "$environment_file" -f "$compose_file" config --format json \
  >"$test_dir/mutable-tag.json" 2>"$test_dir/mutable-tag.err"; then
  printf '%s\n' "production compose accepted a mutable image override" >&2
  exit 1
fi

CHATTEA_BACKEND_DIGEST="$candidate_digest" docker compose --env-file "$environment_file" -f "$compose_file" \
  config --format json >"$test_dir/config.json"

jq -e '
  .services as $services |
  ["chattea-be", "chattea-maintenance", "chattea-migrate"] |
  all(.[]; $services[.].image == env.CANDIDATE_REF)
' "$test_dir/config.json" >/dev/null
jq -e 'all(.services[]; has("build") | not)' "$test_dir/config.json" >/dev/null
jq -e '.services["chattea-migrate"].command | join(" ") | contains("dist/scripts/migrate.js")' \
  "$test_dir/config.json" >/dev/null
jq -e '.services["chattea-maintenance"].command | join(" ") | contains("dist/src/maintenance.js")' \
  "$test_dir/config.json" >/dev/null
jq -e '.services["chattea-be"].healthcheck.test | join(" ") | contains("/healthz")' \
  "$test_dir/config.json" >/dev/null
jq -e '.services["chattea-maintenance"].healthcheck.test | join(" ") | contains("maintenance-heartbeat")' \
  "$test_dir/config.json" >/dev/null

printf '%s\n' "production-compose tests passed"
