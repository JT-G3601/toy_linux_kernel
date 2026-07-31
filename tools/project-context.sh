#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

section() {
    printf '\n===== %s =====\n' "$1"
}

show_file() {
    local title=$1
    local path=$2
    section "$title"
    if [[ -f "$path" ]]; then
        sed -n '1,240p' "$path"
    else
        printf 'MISSING: %s\n' "$path"
    fi
}

section "PROJECT"
printf 'root: %s\n' "$PROJECT_ROOT"
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'git_head: %s\n' "$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unborn')"
    git -C "$PROJECT_ROOT" status --short --branch
else
    printf 'git: unversioned\n'
fi

show_file "CURRENT STATUS" "$PROJECT_ROOT/PROJECT_STATUS.md"
show_file "TASKS" "$PROJECT_ROOT/TASKS.md"
show_file "DECISIONS" "$PROJECT_ROOT/DECISIONS.md"

section "ACTIVE WRITE CLAIMS"
mapfile -t ACTIVE_CLAIMS < <(
    find "$PROJECT_ROOT/docs/claims/active" -maxdepth 1 -type f \
        ! -name '.gitkeep' -name '*.md' -print 2>/dev/null | sort
)
if ((${#ACTIVE_CLAIMS[@]} == 0)); then
    printf 'none\n'
else
    for claim in "${ACTIVE_CLAIMS[@]}"; do
        printf '\n--- %s ---\n' "$(basename "$claim")"
        sed -n '1,80p' "$claim"
    done
fi

section "RECENT SESSION LOGS"
mapfile -t SESSION_LOGS < <(
    find "$PROJECT_ROOT/docs/sessions" -maxdepth 1 -type f -name '*.md' \
        ! -name 'README.md' ! -name 'TEMPLATE.md' -printf '%f\n' 2>/dev/null |
        sort -r | sed -n '1,3p'
)
if ((${#SESSION_LOGS[@]} == 0)); then
    printf 'none\n'
else
    for log_name in "${SESSION_LOGS[@]}"; do
        printf '\n--- %s ---\n' "$log_name"
        sed -n '1,180p' "$PROJECT_ROOT/docs/sessions/$log_name"
    done
fi

section "NEXT ACTION"
printf 'Read relevant plan.md milestone, then run ./tools/check-project-state.sh.\n'
