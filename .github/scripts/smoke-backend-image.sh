#!/usr/bin/env bash
set -Eeuo pipefail

image_digest=${1:-}
if [[ ! "$image_digest" =~ ^[0-9a-f]{64}$ ]]; then
  printf '%s\n' "smoke image digest must be 64 lowercase hex characters" >&2
  exit 2
fi
image_ref="ghcr.io/chatteadot/chattea-be@sha256:$image_digest"

temporary_root=${RUNNER_TEMP:-/tmp}
environment_file=$(mktemp "$temporary_root/chattea-smoke.XXXXXX")
api_container="chattea-smoke-api-$$"
maintenance_container="chattea-smoke-maintenance-$$"

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  set +e
  docker rm -f "$api_container" "$maintenance_container" >/dev/null 2>&1
  rm -f "$environment_file"
  exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
chmod 600 "$environment_file"
printf '%s\n' \
  'NODE_ENV=production' \
  'PORT=4000' \
  'DD_SERVICE=chattea-smoke' \
  'DD_ENV=ci' \
  'DD_VERSION=ci' \
  'TRUST_PROXY=loopback' \
  'POSTGRES_HOST=127.0.0.1' \
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
  'KAKAO_CALLBACK_URL=https://api.example.test/api/auth/kakao/callback' \
  'PHONE_CODE_PEPPER=production-phone-pepper' \
  'SMS_PROVIDER_URL=https://sms.example.test/send' \
  'SMS_PROVIDER_AUTHORIZATION=production-sms-authorization' \
  'SMS_SENDER_ID=production-sender' \
  'R2_ACCOUNT_ID=production-r2-account' \
  'R2_ACCESS_KEY_ID=production-r2-access-key' \
  'R2_SECRET_ACCESS_KEY=production-r2-secret' \
  'R2_BUCKET=chattea-production' \
  'R2_PUBLIC_BASE_URL=https://images.example.test' \
  'EXPO_PUSH_ENABLED=false' \
  'REVENUECAT_WEBHOOK_SECRET=production-revenuecat-secret' \
  'REVENUECAT_IOS_APP_ID=production-revenuecat-ios' \
  'REVENUECAT_ANDROID_APP_ID=production-revenuecat-android' \
  'CLIENT_URL=https://app.example.test' >"$environment_file"

docker pull "$image_ref"
if [[ "$(docker image inspect "$image_ref" --format '{{.Config.User}}')" != "node" ]]; then
  printf '%s\n' "backend image must run as node" >&2
  exit 3
fi

docker run -d --name "$api_container" --network host --env-file "$environment_file" "$image_ref" >/dev/null
docker run -d --name "$maintenance_container" --network host --env-file "$environment_file" "$image_ref" \
  sh -c 'node --env-file-if-exists=.env dist/scripts/preflight.js && exec node --env-file-if-exists=.env dist/src/maintenance.js' >/dev/null

api_ready=0
for _attempt in {1..30}; do
  if curl -fsS http://127.0.0.1:4000/healthz >/dev/null; then
    api_ready=1
    break
  fi
  sleep 1
done
if ((api_ready != 1)); then
  printf '%s\n' "backend image health check failed" >&2
  exit 4
fi

maintenance_ready=0
for _attempt in {1..30}; do
  if docker exec "$maintenance_container" node -e \
    "require('fs').stat('/tmp/chattea-maintenance-heartbeat',(e,s)=>process.exit(!e&&Date.now()-s.mtimeMs<150000?0:1))"; then
    maintenance_ready=1
    break
  fi
  sleep 1
done
if ((maintenance_ready != 1)); then
  printf '%s\n' "maintenance image heartbeat failed" >&2
  exit 5
fi

for container in "$api_container" "$maintenance_container"; do
  docker exec "$container" node -e \
    "const c=require('fs').readFileSync('/proc/1/cmdline','utf8');process.exit(c.startsWith('node')?0:1)"
  docker kill --signal TERM "$container" >/dev/null
  stopped=0
  for _attempt in {1..10}; do
    if [[ "$(docker inspect "$container" --format '{{.State.Running}}')" == "false" ]]; then
      stopped=1
      break
    fi
    sleep 1
  done
  if ((stopped != 1)); then
    printf '%s\n' "$container did not stop after SIGTERM" >&2
    exit 6
  fi
done
