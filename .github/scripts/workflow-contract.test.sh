#!/usr/bin/env bash
set -euo pipefail

workspace_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ci_file="$workspace_dir/.github/workflows/ci.yml"
release_file="$workspace_dir/.github/workflows/release.yml"
actionlint_image=docker.io/rhysd/actionlint@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

require_pattern() {
  local pattern=$1
  local file=$2
  rg -F -- "$pattern" "$file" >/dev/null || fail "missing workflow contract: $pattern"
}

reject_pattern() {
  local pattern=$1
  local file=$2
  if rg -F -- "$pattern" "$file" >/dev/null; then fail "forbidden workflow contract: $pattern"; fi
}

require_count() {
  local expected=$1
  local pattern=$2
  shift 2
  local actual
  actual=$(rg -F --count-matches -- "$pattern" "$@" | awk -F: '{ total += $NF } END { print total + 0 }')
  [[ "$actual" == "$expected" ]] || fail "workflow contract count mismatch for $pattern: expected $expected, got $actual"
}

require_job_pattern() {
  local job=$1
  local pattern=$2
  awk -v job="$job" '
    $0 == "  " job ":" { active = 1 }
    active && $0 ~ /^  [a-zA-Z0-9_-]+:$/ && $0 != "  " job ":" { exit }
    active { print }
  ' "$release_file" | rg -F -- "$pattern" >/dev/null || fail "missing $job workflow contract: $pattern"
}

docker run --rm -v "$workspace_dir:/workspace" -w /workspace "$actionlint_image"

while IFS= read -r action; do
  if [[ ! "$action" =~ ^[^@]+@[0-9a-f]{40}$ ]]; then fail "workflow action is not SHA pinned: $action"; fi
done < <(sed -nE 's/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*([^#[:space:]]+).*/\1/p' "$ci_file" "$release_file")

require_pattern 'packages: write' "$release_file"
require_pattern 'id-token: write' "$release_file"
require_pattern 'attestations: write' "$release_file"
require_pattern 'platforms: linux/amd64,linux/arm64' "$release_file"
require_pattern 'type=provenance,mode=max' "$release_file"
require_pattern 'type=sbom,generator=' "$release_file"
require_pattern 'TRIVY_PLATFORM: linux/amd64' "$release_file"
require_pattern 'TRIVY_PLATFORM: linux/arm64' "$release_file"
require_pattern 'cosign sign --yes' "$release_file"
require_pattern 'cosign verify' "$release_file"
require_pattern 'script_path: .github/scripts/deploy-backend.sh' "$release_file"
require_pattern 'RELEASE_IMAGE_DIGEST:' "$release_file"
require_pattern 'BUILD_DIGEST#sha256:' "$release_file"
require_pattern 'steps.build.outputs.digest' "$release_file"
require_pattern 'target:' "$release_file"
require_pattern '          - all' "$release_file"
require_pattern '          - backend' "$release_file"
require_pattern '          - mobile-build' "$release_file"
reject_pattern '          - mobile-update' "$release_file"
reject_pattern '          - mobile-submit' "$release_file"
require_pattern "if: github.ref == 'refs/heads/main' && (inputs.target == 'all' || inputs.target == 'backend')" "$release_file"
require_pattern '  mobile-build:' "$release_file"
reject_pattern '  mobile-update:' "$release_file"
reject_pattern '  mobile-submit:' "$release_file"
require_job_pattern mobile-build "if: github.ref == 'refs/heads/main' && (inputs.target == 'all' || inputs.target == 'mobile-build')"
require_job_pattern mobile-build 'environment: production'
require_job_pattern mobile-build 'timeout-minutes: 120'
require_job_pattern mobile-build 'eas build --platform all --profile production --non-interactive'
reject_pattern 'eas update ' "$release_file"
reject_pattern 'eas submit ' "$release_file"
if rg -F -- '--no-wait' "$release_file" >/dev/null; then
  fail "mobile production build does not wait for the EAS result"
fi
require_count 1 'uses: expo/expo-github-action@' "$release_file"
require_count 1 'eas-version: ' "$release_file"
require_count 1 'uses: expo/expo-github-action@eab7a230208c952974db8c3245cfd78402c7b385' "$release_file"
require_count 1 'eas-version: 22.4.0' "$release_file"
if rg -F -- 'eas-version: latest' "$release_file" >/dev/null; then
  fail "mobile release workflow uses an unpinned EAS CLI version"
fi
require_count 5 'token: ${{ secrets.CHATTEA_SUBMODULE_TOKEN }}' "$ci_file" "$release_file"
require_count 5 'persist-credentials: false' "$ci_file" "$release_file"
require_count 5 'submodules: recursive' "$ci_file" "$release_file"
require_count 2 'package_json_file: chattea-be/package.json' "$ci_file" "$release_file"
require_count 2 'package_json_file: chattea-fe/package.json' "$ci_file" "$release_file"
if rg -F -- 'RELEASE_IMAGE_REF:' "$release_file" >/dev/null; then
  fail "release workflow still passes a caller-controlled image reference"
fi
if rg -F -- 'docker build -t chattea-be:release-candidate' "$release_file" >/dev/null; then
  fail "release workflow still performs a second backend build"
fi
require_pattern 'expo config --type prebuild --json' "$ci_file"
require_pattern 'expo prebuild --clean --no-install --platform all' "$ci_file"
require_pattern 'deploy-backend.test.sh' "$ci_file"
require_pattern 'production-compose.test.sh' "$ci_file"
require_pattern 'container-contract.test.sh chattea-be:ci' "$ci_file"

printf '%s\n' "workflow-contract tests passed"
