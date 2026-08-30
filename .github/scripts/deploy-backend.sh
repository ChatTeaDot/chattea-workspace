#!/usr/bin/env bash
set -Eeuo pipefail

: "${RELEASE_WORKSPACE_DIR:?RELEASE_WORKSPACE_DIR is required}"
: "${RELEASE_WORKSPACE_SHA:?RELEASE_WORKSPACE_SHA is required}"
: "${RELEASE_IMAGE_DIGEST:?RELEASE_IMAGE_DIGEST is required}"
: "${RELEASE_GHCR_USERNAME:?RELEASE_GHCR_USERNAME is required}"
: "${RELEASE_GHCR_TOKEN:?RELEASE_GHCR_TOKEN is required}"

if [[ ! "$RELEASE_WORKSPACE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  printf '%s\n' "RELEASE_WORKSPACE_SHA must be a full commit SHA" >&2
  exit 2
fi
if [[ ! "$RELEASE_IMAGE_DIGEST" =~ ^[0-9a-f]{64}$ ]]; then
  printf '%s\n' "RELEASE_IMAGE_DIGEST must be 64 lowercase hex characters" >&2
  exit 2
fi
release_image_ref="ghcr.io/chatteadot/chattea-be@sha256:$RELEASE_IMAGE_DIGEST"

cd "$RELEASE_WORKSPACE_DIR"
workspace_dir=$(pwd -P)
state_dir="$workspace_dir/.deploy"
state_file="$state_dir/current"
umask 077
mkdir -p "$state_dir"
exec 9>"$state_dir/release.lock"
if ! flock -n 9; then
  printf '%s\n' "Another deployment owns the release lock" >&2
  exit 3
fi

shopt -s nullglob
for stale_docker_config in "$state_dir"/docker-config.*; do
  if [[ -d "$stale_docker_config" && ! -L "$stale_docker_config" ]]; then
    rm -rf -- "$stale_docker_config"
  fi
done
shopt -u nullglob

previous_revision=
previous_image=
if [[ -f "$state_file" ]]; then
  state_line_count=$(wc -l <"$state_file")
  if ((state_line_count != 2)); then
    printf '%s\n' "Deployment state is malformed" >&2
    exit 4
  fi
  previous_revision=$(sed -n '1s/^revision=//p' "$state_file")
  previous_image=$(sed -n '2s/^image=//p' "$state_file")
  if [[ ! "$previous_revision" =~ ^[0-9a-f]{40}$ ]] ||
    [[ ! "$previous_image" =~ ^ghcr\.io/chatteadot/chattea-be@sha256:[0-9a-f]{64}$ ]]; then
    printf '%s\n' "Deployment state is malformed" >&2
    exit 4
  fi
elif [[ -n "$(docker ps --filter name='^/chattea-be$' --format '{{.Names}}')" ]]; then
  printf '%s\n' "Existing production container has no recorded digest" >&2
  exit 4
fi

compose_file="$workspace_dir/chattea-be/docker-compose.production.yml"
environment_file="$workspace_dir/chattea-be/.env"
rollout_started=0
docker_config_dir=

cleanup_docker_config() {
  if [[ -z "$docker_config_dir" ]]; then return; fi
  if [[ "$docker_config_dir" != "$state_dir"/docker-config.* ]]; then
    printf '%s\n' "Refusing to remove unexpected Docker config path" >&2
    return 1
  fi
  rm -rf -- "$docker_config_dir"
  docker_config_dir=
  unset DOCKER_CONFIG
}

candidate_state_committed() {
  local expected_state
  if [[ ! -f "$state_file" ]]; then return 1; fi
  expected_state=$(printf 'revision=%s\nimage=%s' "$RELEASE_WORKSPACE_SHA" "$release_image_ref")
  [[ "$(cat "$state_file")" == "$expected_state" ]]
}

assert_clean_checkout() {
  if ! git diff --quiet --ignore-submodules=none || ! git diff --cached --quiet --ignore-submodules=none; then
    printf '%s\n' "Deployment checkout has tracked changes" >&2
    return 1
  fi
  if git submodule status --recursive | grep -Eq '^[+-U]'; then
    printf '%s\n' "Deployment checkout has tracked changes" >&2
    return 1
  fi
  if ! git submodule foreach --quiet --recursive \
    'git diff --quiet --ignore-submodules=none && git diff --cached --quiet --ignore-submodules=none'; then
    printf '%s\n' "Deployment checkout has tracked changes" >&2
    return 1
  fi
}

ensure_candidate_revision() (
  set -e
  cd "$workspace_dir"
  if [[ "$(git rev-parse HEAD)" != "$RELEASE_WORKSPACE_SHA" ]]; then
    git checkout --detach "$RELEASE_WORKSPACE_SHA"
    git submodule sync --recursive
    git submodule update --init --recursive
  fi
  assert_clean_checkout
)

restore_revision() (
  set -e
  if [[ -z "$previous_revision" ]]; then return 0; fi
  cd "$workspace_dir"
  git checkout --detach "$previous_revision"
  git submodule sync --recursive
  git submodule update --init --recursive
  assert_clean_checkout
)

rollback_application() (
  set -e
  if [[ -z "$previous_image" ]]; then
    export CHATTEA_BACKEND_DIGEST="$RELEASE_IMAGE_DIGEST"
    docker compose --project-directory "$workspace_dir/chattea-be" --env-file "$environment_file" \
      -f "$compose_file" -p chattea stop chattea-be chattea-maintenance
    return
  fi
  restore_revision
  compose_file="$workspace_dir/chattea-be/docker-compose.production.yml"
  export CHATTEA_BACKEND_DIGEST="${previous_image#ghcr.io/chatteadot/chattea-be@sha256:}"
  docker pull "$previous_image"
  docker compose --project-directory "$workspace_dir/chattea-be" --env-file "$environment_file" \
    -f "$compose_file" -p chattea config --quiet
  docker compose --project-directory "$workspace_dir/chattea-be" --env-file "$environment_file" \
    -f "$compose_file" -p chattea up -d --no-build --wait --wait-timeout 120 chattea-be chattea-maintenance
  curl -fsS http://127.0.0.1:4000/healthz
)

handle_exit() {
  local exit_code=$?
  local rollback_status=0
  trap - EXIT HUP INT TERM
  if ((exit_code == 0)); then
    cleanup_docker_config
    return
  fi
  set +e
  if candidate_state_committed; then
    ensure_candidate_revision
    rollback_status=$?
  elif ((rollout_started == 1)); then
    rollback_application
    rollback_status=$?
  else
    restore_revision
    rollback_status=$?
  fi
  if ((rollback_status != 0)); then
    printf '%s\n' "Automatic application rollback failed; manual recovery is required." >&2
  fi
  cleanup_docker_config
  exit "$exit_code"
}

trap handle_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

docker_config_dir=$(mktemp -d "$state_dir/docker-config.XXXXXX")
chmod 700 "$docker_config_dir"
export DOCKER_CONFIG="$docker_config_dir"

git fetch --prune origin
git cat-file -e "${RELEASE_WORKSPACE_SHA}^{commit}"
git checkout --detach "$RELEASE_WORKSPACE_SHA"
git submodule sync --recursive
git submodule update --init --recursive
assert_clean_checkout

if [[ ! -f "$compose_file" ]] || [[ ! -f "$environment_file" ]]; then
  printf '%s\n' "Production Compose or environment file is missing" >&2
  exit 5
fi

printf '%s\n' "$RELEASE_GHCR_TOKEN" | docker login ghcr.io --username "$RELEASE_GHCR_USERNAME" --password-stdin
unset RELEASE_GHCR_TOKEN
export CHATTEA_BACKEND_DIGEST="$RELEASE_IMAGE_DIGEST"
docker pull "$release_image_ref"
docker compose --project-directory "$workspace_dir/chattea-be" --env-file "$environment_file" \
  -f "$compose_file" -p chattea config --quiet
docker compose --project-directory "$workspace_dir/chattea-be" --env-file "$environment_file" \
  -f "$compose_file" -p chattea pull chattea-migrate chattea-be chattea-maintenance
docker compose --project-directory "$workspace_dir/chattea-be" --env-file "$environment_file" \
  -f "$compose_file" -p chattea run --rm chattea-migrate

rollout_started=1
docker compose --project-directory "$workspace_dir/chattea-be" --env-file "$environment_file" \
  -f "$compose_file" -p chattea up -d --no-build --wait --wait-timeout 120 chattea-be chattea-maintenance
curl -fsS http://127.0.0.1:4000/healthz

state_temporary=$(mktemp "$state_dir/current.XXXXXX")
printf 'revision=%s\nimage=%s\n' "$RELEASE_WORKSPACE_SHA" "$release_image_ref" >"$state_temporary"
chmod 600 "$state_temporary"
mv "$state_temporary" "$state_file"
rollout_started=0
cleanup_docker_config
trap - EXIT HUP INT TERM
