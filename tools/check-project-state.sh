#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ERRORS=0

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    ERRORS=$((ERRORS + 1))
}

required_files=(
    AGENTS.md
    plan.md
    PROJECT_STATUS.md
    TASKS.md
    DECISIONS.md
    docs/claims/README.md
    docs/claims/TEMPLATE.md
    docs/sessions/README.md
    docs/sessions/TEMPLATE.md
)

for relative_path in "${required_files[@]}"; do
    [[ -f "$PROJECT_ROOT/$relative_path" ]] || fail "missing required file: $relative_path"
done

declare -a CLAIM_FILES=()
declare -a CLAIM_NAMES=()
declare -a SCOPE_CLAIMS=()
declare -a SCOPES=()

mapfile -t CLAIM_FILES < <(
    find "$PROJECT_ROOT/docs/claims/active" -maxdepth 1 -type f \
        ! -name '.gitkeep' -name '*.md' -print 2>/dev/null | sort
)

for claim_file in "${CLAIM_FILES[@]}"; do
    claim_name=$(basename "$claim_file" .md)
    session_id=$(sed -n 's/^session_id:[[:space:]]*//p' "$claim_file" | head -1)
    status=$(sed -n 's/^status:[[:space:]]*//p' "$claim_file" | head -1)

    [[ -n "$session_id" ]] || fail "$claim_name: missing session_id"
    [[ "$session_id" == "$claim_name" ]] ||
        fail "$claim_name: filename and session_id differ"
    [[ "$status" == "active" ]] || fail "$claim_name: active claim status must be active"
    [[ -f "$PROJECT_ROOT/docs/sessions/$claim_name.md" ]] ||
        fail "$claim_name: missing matching session log"

    for previous_name in "${CLAIM_NAMES[@]}"; do
        [[ "$previous_name" != "$session_id" ]] ||
            fail "$claim_name: duplicate session_id"
    done
    CLAIM_NAMES+=("$session_id")

    mapfile -t claim_scopes < <(
        awk '
            /^scope:[[:space:]]*$/ { in_scope=1; next }
            in_scope && /^  - / {
                sub(/^  - /, "")
                print
                next
            }
            in_scope { exit }
        ' "$claim_file"
    )
    ((${#claim_scopes[@]} > 0)) || fail "$claim_name: scope is empty"

    for scope in "${claim_scopes[@]}"; do
        normalized=${scope#./}
        normalized=${normalized%/}
        [[ -n "$normalized" ]] || normalized="."
        SCOPE_CLAIMS+=("$claim_name")
        SCOPES+=("$normalized")
    done
done

for ((i = 0; i < ${#SCOPES[@]}; i++)); do
    for ((j = i + 1; j < ${#SCOPES[@]}; j++)); do
        [[ "${SCOPE_CLAIMS[$i]}" != "${SCOPE_CLAIMS[$j]}" ]] || continue
        left=${SCOPES[$i]}
        right=${SCOPES[$j]}
        if [[ "$left" == "." || "$right" == "." ||
              "$left" == "$right" ||
              "$left" == "$right/"* ||
              "$right" == "$left/"* ]]; then
            fail "scope conflict: ${SCOPE_CLAIMS[$i]}:$left <-> ${SCOPE_CLAIMS[$j]}:$right"
        fi
    done
done

if ((ERRORS > 0)); then
    printf 'Project state check: FAIL (%d error(s))\n' "$ERRORS" >&2
    exit 1
fi

printf 'Project state check: PASS (%d active claim(s))\n' "${#CLAIM_FILES[@]}"

