#!/usr/bin/env bash
set -euo pipefail

APPLY=false
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=true
fi

MAIN_SETTINGS="/Users/liyang/etc/agents/dot-claude/settings.json"
BACKUP="${MAIN_SETTINGS}.backup-$(date +%Y%m%d-%H%M%S)"

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

fail() {
  echo "ERROR: $*" >&2
  exit 1
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

[[ -f "$MAIN_SETTINGS" ]] || fail "main settings not found: $MAIN_SETTINGS"

echo "==> Main settings: $MAIN_SETTINGS"
echo "Mode: $([[ "$APPLY" == true ]] && echo apply || echo dry-run)"
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

[[ "${#files[@]}" -gt 0 ]] || fail "no claude settings.json found"

echo "==> Found settings files:"
printf '  %s\n' "${files[@]}"
echo

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

merged="$tmp_dir/merged.json"
cp "$MAIN_SETTINGS" "$merged"

for f in "${files[@]}"; do
  [[ "$f" == "$MAIN_SETTINGS" ]] && continue

  echo "==> Merge from: $f"

  sanitized="$tmp_dir/sanitized-$(basename "$(dirname "$f")")-$(date +%s%N).json"
  output="$tmp_dir/output-$(date +%s%N).json"

  jq --argjson exclude "$EXCLUDE_KEYS" '
    with_entries(select(.key as $k | ($exclude | index($k) | not)))
  ' "$f" > "$sanitized"

  jq -s '.[0] * .[1]' "$merged" "$sanitized" > "$output"
  mv "$output" "$merged"
done

echo
echo "==> Preview diff:"
if command -v diff >/dev/null 2>&1; then
  diff -u "$MAIN_SETTINGS" "$merged" || true
else
  echo "diff command not found, skip diff preview"
fi

echo
if [[ "$APPLY" == true ]]; then
  echo "==> Backup current main settings"
  cp "$MAIN_SETTINGS" "$BACKUP"

  echo "==> Write merged settings"
  cp "$merged" "$MAIN_SETTINGS"

  echo "Done."
  echo "Backup: $BACKUP"
else
  echo "Dry-run only. Nothing changed."
  echo "Run with --apply to write changes:"
  echo "  $0 --apply"
fi
