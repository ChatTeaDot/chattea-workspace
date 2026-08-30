#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
smoke_script="$script_dir/smoke-backend-image.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
fake_bin="$test_dir/bin"
command_log="$test_dir/commands.log"
mkdir -p "$fake_bin"
: >"$command_log"

printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'printf "docker %s\n" "$*" >>"$FAKE_COMMAND_LOG"' \
  'if [[ "${1:-}" == "image" && "${2:-}" == "inspect" ]]; then printf "%s\n" node; exit 0; fi' \
  'if [[ "${1:-}" == "run" ]]; then printf "%s\n" container-id; exit 0; fi' \
  'if [[ "${1:-}" == "inspect" ]]; then' \
  '  name=${2:-}' \
  '  if [[ -f "$FAKE_STATE_DIR/$name.stopped" ]]; then printf "%s\n" false; else printf "%s\n" true; fi' \
  '  exit 0' \
  'fi' \
  'if [[ "${1:-}" == "kill" ]]; then for name in "$@"; do :; done; touch "$FAKE_STATE_DIR/$name.stopped"; exit 0; fi' \
  'exit 0' >"$fake_bin/docker"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  'printf "curl %s\n" "$*" >>"$FAKE_COMMAND_LOG"' \
  'exit 0' >"$fake_bin/curl"
chmod +x "$fake_bin/docker" "$fake_bin/curl"
export FAKE_COMMAND_LOG="$command_log"
export FAKE_STATE_DIR="$test_dir"
export RUNNER_TEMP="$test_dir"
image_digest=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
image_ref=ghcr.io/chatteadot/chattea-be@sha256:$image_digest

if PATH="$fake_bin:$PATH" "$smoke_script" latest; then
  printf '%s\n' "smoke accepted a non-digest component" >&2
  exit 1
fi
[[ ! -s "$command_log" ]] || { printf '%s\n' "invalid smoke input invoked Docker" >&2; exit 1; }

PATH="$fake_bin:$PATH" "$smoke_script" "$image_digest"
grep -F "docker pull $image_ref" "$command_log" >/dev/null
grep -F "docker image inspect" "$command_log" >/dev/null
grep -F "docker run -d --name" "$command_log" >/dev/null
grep -F "docker exec" "$command_log" >/dev/null
grep -F "docker kill --signal TERM" "$command_log" >/dev/null

printf '%s\n' "smoke-backend-image tests passed"
