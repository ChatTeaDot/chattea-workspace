#!/usr/bin/env bash
set -euo pipefail

workspace_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
image_name=${1:-chattea-be:track-c-contract}

if (($# == 0)); then docker build -t "$image_name" "$workspace_dir/chattea-be"; fi
config=$(docker image inspect "$image_name" --format '{{json .Config}}')

jq -e '.User == "node"' <<<"$config" >/dev/null
jq -e '.Cmd | join(" ") | contains("dist/src/main.js")' <<<"$config" >/dev/null
if jq -e '.Cmd | join(" ") | contains("dist/scripts/migrate.js")' <<<"$config" >/dev/null; then
  printf '%s\n' "production image still runs migrations during API startup" >&2
  exit 1
fi
if ! docker run --rm --entrypoint sh "$image_name" -c 'test -f dist/src/maintenance.js'; then
  printf '%s\n' "production image is missing the maintenance entrypoint" >&2
  exit 1
fi

printf '%s\n' "container-contract tests passed"
