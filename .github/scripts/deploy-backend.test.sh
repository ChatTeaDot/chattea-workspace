#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
deploy_script="$script_dir/deploy-backend.sh"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file=$1
  local expected=$2
  grep -F -- "$expected" "$file" >/dev/null || fail "missing: $expected"
}

assert_not_contains() {
  local file=$1
  local unexpected=$2
  if grep -F -- "$unexpected" "$file" >/dev/null; then fail "unexpected: $unexpected"; fi
}

reset_case() {
  case_dir="$test_root/$1"
  workspace_dir="$case_dir/workspace"
  fake_bin="$case_dir/bin"
  command_log="$case_dir/commands.log"
  mkdir -p "$workspace_dir/chattea-be" "$fake_bin"
  : >"$workspace_dir/chattea-be/.env"
  : >"$workspace_dir/chattea-be/docker-compose.production.yml"
  : >"$command_log"
  target_revision=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  previous_revision=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  candidate_digest=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  previous_digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  candidate_ref=ghcr.io/chatteadot/chattea-be@sha256:$candidate_digest
  previous_ref=ghcr.io/chatteadot/chattea-be@sha256:$previous_digest
  printf '%s\n' "$previous_revision" >"$case_dir/revision"
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
    'printf "git %s\n" "$*" >>"$FAKE_COMMAND_LOG"' \
    'if [[ "${1:-}" == "rev-parse" ]]; then cat "$FAKE_REVISION_FILE"; exit 0; fi' \
    'if [[ "${1:-}" == "checkout" ]]; then printf "%s\n" "${3:-}" >"$FAKE_REVISION_FILE"; fi' \
    'current_revision=$(cat "$FAKE_REVISION_FILE")' \
    'if [[ "${1:-}" == "diff" ]]; then' \
    '  if [[ "$current_revision" == "$RELEASE_WORKSPACE_SHA" && "${FAKE_CANDIDATE_DIRTY:-0}" == "1" ]]; then exit 1; fi' \
    '  if [[ "$current_revision" == "$FAKE_PREVIOUS_REVISION" && "${FAKE_ROLLBACK_DIRTY:-0}" == "1" ]]; then exit 1; fi' \
    'fi' \
    'if [[ "${1:-}" == "submodule" && "${2:-}" == "foreach" ]]; then' \
    '  if [[ "$current_revision" == "$RELEASE_WORKSPACE_SHA" && "${FAKE_CANDIDATE_SUBMODULE_DIRTY:-0}" == "1" ]]; then exit 1; fi' \
    '  if [[ "$current_revision" == "$FAKE_PREVIOUS_REVISION" && "${FAKE_ROLLBACK_SUBMODULE_DIRTY:-0}" == "1" ]]; then exit 1; fi' \
    'fi' \
    'exit 0' >"$fake_bin/git"
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
    'printf "docker digest=%s %s config=%s\n" "${CHATTEA_BACKEND_DIGEST:-unset}" "$*" "${DOCKER_CONFIG:-unset}" >>"$FAKE_COMMAND_LOG"' \
    'if [[ "${1:-}" == "login" ]]; then read -r _token; exit 0; fi' \
    'if [[ "${1:-}" == "ps" && -n "${FAKE_EXISTING_CONTAINER:-}" ]]; then printf "%s\n" chattea-be; fi' \
    'if [[ " $* " == *" run "* && "${FAKE_MIGRATION_FAIL:-0}" == "1" ]]; then exit 41; fi' \
    'if [[ " $* " == *" up "* && "${CHATTEA_BACKEND_DIGEST:-}" == "${RELEASE_IMAGE_DIGEST:-}" ]]; then' \
    '  if [[ -n "${FAKE_SIGNAL_ON_UP:-}" ]]; then kill -s "$FAKE_SIGNAL_ON_UP" "$PPID"; sleep 1; fi' \
    '  if [[ "${FAKE_ROLLOUT_FAIL:-0}" == "1" ]]; then exit 42; fi' \
    'fi' \
    'if [[ "${1:-}" == "pull" && "${2:-}" == "${FAKE_PREVIOUS_REF:-}" && "${FAKE_ROLLBACK_PULL_FAIL:-0}" == "1" ]]; then exit 43; fi' \
    'exit 0' >"$fake_bin/docker"
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
    'printf "curl %s\n" "$*" >>"$FAKE_COMMAND_LOG"' \
    'if [[ -n "${FAKE_HEALTH_FAILURE_FILE:-}" && -f "$FAKE_HEALTH_FAILURE_FILE" ]]; then rm -f "$FAKE_HEALTH_FAILURE_FILE"; exit 44; fi' \
    'exit 0' >"$fake_bin/curl"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fake_bin/flock"
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
    'if [[ "${FAKE_SIGNAL_BEFORE_STATE_MV:-0}" == "1" ]]; then kill -TERM "$PPID"; exit 45; fi' \
    '/bin/mv "$@"' \
    'if [[ "${FAKE_SIGNAL_AFTER_STATE_MV:-0}" == "1" ]]; then kill -TERM "$PPID"; sleep 1; fi' >"$fake_bin/mv"
  chmod +x "$fake_bin/git" "$fake_bin/docker" "$fake_bin/curl" "$fake_bin/flock" "$fake_bin/mv"
  export FAKE_COMMAND_LOG="$command_log"
  export FAKE_REVISION_FILE="$case_dir/revision"
  export RELEASE_WORKSPACE_DIR="$workspace_dir"
  export RELEASE_WORKSPACE_SHA="$target_revision"
  export RELEASE_IMAGE_DIGEST="$candidate_digest"
  export RELEASE_GHCR_USERNAME=chattea-reader
  export RELEASE_GHCR_TOKEN=read-token
  export FAKE_PREVIOUS_REF="$previous_ref"
  export FAKE_PREVIOUS_REVISION="$previous_revision"
  unset FAKE_EXISTING_CONTAINER FAKE_MIGRATION_FAIL FAKE_ROLLOUT_FAIL FAKE_ROLLBACK_PULL_FAIL
  unset FAKE_HEALTH_FAILURE_FILE FAKE_SIGNAL_ON_UP FAKE_SIGNAL_BEFORE_STATE_MV FAKE_SIGNAL_AFTER_STATE_MV
  unset FAKE_CANDIDATE_DIRTY FAKE_CANDIDATE_SUBMODULE_DIRTY FAKE_ROLLBACK_DIRTY FAKE_ROLLBACK_SUBMODULE_DIRTY
}

run_deploy() {
  PATH="$fake_bin:$PATH" "$deploy_script"
}

write_previous_state() {
  mkdir -p "$workspace_dir/.deploy"
  printf 'revision=%s\nimage=%s\n' "$previous_revision" "$previous_ref" >"$workspace_dir/.deploy/current"
}

reset_case invalid-digest
RELEASE_IMAGE_DIGEST=latest
if run_deploy >"$case_dir/stdout" 2>"$case_dir/stderr"; then fail "invalid digest was accepted"; fi
[[ ! -s "$command_log" ]] || fail "invalid digest executed external commands"

reset_case successful-rollout
run_deploy
assert_contains "$command_log" "docker digest=unset login ghcr.io --username chattea-reader --password-stdin"
assert_contains "$command_log" "docker digest=$candidate_digest compose"
assert_contains "$command_log" "run --rm chattea-migrate"
assert_contains "$command_log" "up -d --no-build --wait --wait-timeout 120 chattea-be chattea-maintenance"
assert_not_contains "$command_log" " build "
migration_line=$(grep -nF "run --rm chattea-migrate" "$command_log" | head -n 1 | cut -d: -f1)
rollout_line=$(grep -nF "up -d --no-build" "$command_log" | head -n 1 | cut -d: -f1)
((migration_line < rollout_line)) || fail "application switched before migration"
expected_state=$(printf 'revision=%s\nimage=%s' "$target_revision" "$candidate_ref")
[[ "$(cat "$workspace_dir/.deploy/current")" == "$expected_state" ]] || fail "successful state was not recorded"
docker_config_path=$(sed -n 's/.*login ghcr.io.* config=//p' "$command_log")
workspace_real=$(cd "$workspace_dir" && pwd -P)
[[ "$docker_config_path" == "$workspace_real/.deploy"/docker-config.* ]] || fail "docker login did not use an isolated config"
[[ ! -e "$docker_config_path" ]] || fail "temporary Docker credentials were not removed"

reset_case migration-failure
write_previous_state
FAKE_MIGRATION_FAIL=1
export FAKE_MIGRATION_FAIL
if run_deploy; then fail "migration failure was ignored"; fi
[[ "$(cat "$workspace_dir/.deploy/current")" == "$(printf 'revision=%s\nimage=%s' "$previous_revision" "$previous_ref")" ]] || fail "migration failure changed state"
assert_not_contains "$command_log" "up -d --no-build"
[[ "$(cat "$case_dir/revision")" == "$previous_revision" ]] || fail "migration failure did not restore revision"

reset_case candidate-dirty
write_previous_state
FAKE_CANDIDATE_DIRTY=1
export FAKE_CANDIDATE_DIRTY
if run_deploy >"$case_dir/stdout" 2>"$case_dir/stderr"; then fail "dirty candidate checkout was accepted"; fi
assert_contains "$case_dir/stderr" "Deployment checkout has tracked changes"
assert_not_contains "$command_log" "docker digest=$candidate_digest compose"

reset_case rollout-failure
write_previous_state
FAKE_HEALTH_FAILURE_FILE="$case_dir/fail-health-once"
export FAKE_HEALTH_FAILURE_FILE
: >"$FAKE_HEALTH_FAILURE_FILE"
if run_deploy; then fail "failed health check was ignored"; fi
assert_contains "$command_log" "pull $previous_ref"
assert_contains "$command_log" "docker digest=$previous_digest compose"
[[ "$(cat "$case_dir/revision")" == "$previous_revision" ]] || fail "rollback did not restore revision"
[[ "$(cat "$workspace_dir/.deploy/current")" == "$(printf 'revision=%s\nimage=%s' "$previous_revision" "$previous_ref")" ]] || fail "rollback changed successful state"

reset_case rollback-failure
write_previous_state
FAKE_ROLLOUT_FAIL=1
FAKE_ROLLBACK_PULL_FAIL=1
export FAKE_ROLLOUT_FAIL FAKE_ROLLBACK_PULL_FAIL
if run_deploy >"$case_dir/stdout" 2>"$case_dir/stderr"; then fail "rollback failure returned success"; fi
assert_contains "$case_dir/stderr" "Automatic application rollback failed"

reset_case rollback-submodule-dirty
write_previous_state
FAKE_HEALTH_FAILURE_FILE="$case_dir/fail-health-once"
FAKE_ROLLBACK_SUBMODULE_DIRTY=1
export FAKE_HEALTH_FAILURE_FILE FAKE_ROLLBACK_SUBMODULE_DIRTY
: >"$FAKE_HEALTH_FAILURE_FILE"
if run_deploy >"$case_dir/stdout" 2>"$case_dir/stderr"; then fail "dirty rollback checkout returned success"; fi
assert_contains "$case_dir/stderr" "Deployment checkout has tracked changes"
assert_contains "$case_dir/stderr" "Automatic application rollback failed"
assert_not_contains "$command_log" "docker digest=$previous_digest compose"

reset_case signal-rollback
write_previous_state
FAKE_SIGNAL_ON_UP=TERM
export FAKE_SIGNAL_ON_UP
if run_deploy; then fail "termination returned success"; fi
assert_contains "$command_log" "pull $previous_ref"
docker_config_path=$(sed -n 's/.*login ghcr.io.* config=//p' "$command_log")
[[ ! -e "$docker_config_path" ]] || fail "signal path retained temporary Docker credentials"

reset_case stale-docker-config
mkdir -p "$workspace_dir/.deploy/docker-config.abandoned"
: >"$workspace_dir/.deploy/docker-config.abandoned/config.json"
run_deploy
[[ ! -e "$workspace_dir/.deploy/docker-config.abandoned" ]] || fail "stale Docker credentials were not scrubbed"

reset_case signal-before-state-commit
write_previous_state
FAKE_SIGNAL_BEFORE_STATE_MV=1
export FAKE_SIGNAL_BEFORE_STATE_MV
if run_deploy; then fail "pre-commit termination returned success"; fi
[[ "$(cat "$workspace_dir/.deploy/current")" == "$(printf 'revision=%s\nimage=%s' "$previous_revision" "$previous_ref")" ]] || fail "pre-commit signal changed state"
[[ "$(cat "$case_dir/revision")" == "$previous_revision" ]] || fail "pre-commit signal did not restore revision"

reset_case signal-after-state-commit
write_previous_state
FAKE_SIGNAL_AFTER_STATE_MV=1
export FAKE_SIGNAL_AFTER_STATE_MV
if run_deploy; then fail "post-commit termination returned success"; fi
[[ "$(cat "$workspace_dir/.deploy/current")" == "$(printf 'revision=%s\nimage=%s' "$target_revision" "$candidate_ref")" ]] || fail "post-commit signal reverted candidate state"
[[ "$(cat "$case_dir/revision")" == "$target_revision" ]] || fail "post-commit signal reverted candidate revision"
assert_not_contains "$command_log" "pull $previous_ref"

printf '%s\n' "deploy-backend tests passed"
