#!/usr/bin/env bash
set -euo pipefail

APPLY=false
FORCE=false

if [[ "${1:-}" == "--apply" ]]; then
  APPLY=true
fi

if [[ "${2:-}" == "--force" ]]; then
  FORCE=true
fi

MAIN_SETTINGS="/Users/liyang/etc/agents/dot-claude/settings.json"

SEARCH_ROOTS=(
  "$HOME"
  "/Users/liyang/etc/agents"
)

EXCLUDE_KEYS='
[
  "apiKey",
  "api_key",
  "authToken",
  "accessToken",
  "refreshToken",
  "token",
  "baseUrl",
  "baseURL",
  "endpoint",
  "provider",
  "account",
  "email",
  "organizationId",
  "orgId"
]
'

log() {
  echo "$@"
}

run() {
  if [[ "$APPLY" == true ]]; then
    "$@"
  else
    printf '[dry-run] '
    printf '%q ' "$@"
    echo
  fi
}

[[ -f "$MAIN_SETTINGS" ]] || {
  echo "ERROR: main settings not found"
  exit 1
}

echo "==> Main settings: $MAIN_SETTINGS"
echo "Mode: $([[ "$APPLY" == true ]] && echo apply || echo dry-run)"
echo "Force overwrite: $FORCE"
echo

mapfile -t files < <(
  for root in "${SEARCH_ROOTS[@]}"; do
    [[ -d "$root" ]] || continue
    find "$root" \
      -path '*/node_modules/*' -prune -o \
      -path '*/plugins/cache/*' -prune -o \
      -name 'settings.json' -path '*claude*' -type f -print
  done | sort -u
)

for f in "${files[@]}"; do
  [[ "$f" == "$MAIN_SETTINGS" ]] && continue

  echo "==> Sync to: $f"

  tmp1="$(mktemp)"
  tmp2="$(mktemp)"

  # 过滤掉账号字段
  jq --argjson exclude "$EXCLUDE_KEYS" '
    with_entries(select(.key as $k | ($exclude | index($k) | not)))
  ' "$MAIN_SETTINGS" > "$tmp1"

  if [[ "$FORCE" == true ]]; then
    # 主配置覆盖 profile
    jq -s '.[1] * .[0]' "$f" "$tmp1" > "$tmp2"
  else
    # 只补缺失字段（推荐）
    jq -s '.[0] * .[1]' "$f" "$tmp1" > "$tmp2"
  fi

  run cp "$tmp2" "$f"

done

echo
echo "==> Done"
