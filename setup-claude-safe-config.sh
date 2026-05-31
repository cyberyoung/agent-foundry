#!/usr/bin/env bash
set -euo pipefail

APPLY=false

if [[ "${1:-}" == "--apply" ]]; then
  APPLY=true
fi

CLAUDE_LINK="$HOME/.claude"

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

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

resolve_symlink() {
  local link="$1"
  local target

  target="$(readlink "$link")"

  if [[ "$target" = /* ]]; then
    echo "$target"
  else
    echo "$(cd "$(dirname "$link")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
  fi
}

log "==> Verify ~/.claude"

[[ -L "$CLAUDE_LINK" ]] || fail "$CLAUDE_LINK is not a symlink"

CLAUDE_REAL="$(resolve_symlink "$CLAUDE_LINK")"

[[ -d "$CLAUDE_REAL" ]] || fail "Claude real directory does not exist: $CLAUDE_REAL"

BASE_DIR="$(dirname "$CLAUDE_REAL")"
SHARED_REAL="$BASE_DIR/dot-claude-shared"
BACKUP_DIR="$BASE_DIR/dot-claude-backup-$(date +%Y%m%d-%H%M%S)"

log "Claude link:  $CLAUDE_LINK"
log "Claude real:  $CLAUDE_REAL"
log "Shared real:  $SHARED_REAL"
log "Backup dir:   $BACKUP_DIR"
log "Mode:         $([[ "$APPLY" == true ]] && echo apply || echo dry-run)"
echo

log "==> Backup Claude real directory"
run mkdir -p "$BACKUP_DIR"

run rsync -a \
  --exclude='plugins/cache/' \
  --exclude='**/node_modules/' \
  "$CLAUDE_REAL/" "$BACKUP_DIR/"

log "==> Create shared directories"
for dir in plugins hooks commands agents skills; do
  run mkdir -p "$SHARED_REAL/$dir"
done

log "==> Move real directories to shared and replace with symlinks"
for dir in plugins hooks commands agents skills; do
  src="$CLAUDE_REAL/$dir"
  dst="$SHARED_REAL/$dir"

  log "--- $dir"

  # run mkdir -p "$dst"

  # Case 1: src is already a symlink
  if [[ -L "$src" ]]; then
    current_target="$(readlink "$src")"

    if [[ "$current_target" == "$dst" ]]; then
      log "OK: $src already points to $dst"
      continue
    fi

    fail "$src is a symlink but points to wrong target:
  current:  $current_target
  expected: $dst

Refuse to overwrite automatically."

  fi

  # Case 2: src is a real directory
  if [[ -d "$src" ]]; then
    log "Sync directory to shared: $src -> $dst"

    run rsync -a \
      --exclude='cache/' \
      --exclude='**/node_modules/' \
      "$src/" "$dst/"

    run rm -rf "$src"
    run ln -s "$dst" "$src"

    continue
  fi

  # Case 3: src exists but is neither directory nor symlink
  if [[ -e "$src" ]]; then
    fail "$src exists but is not a directory or symlink"
  fi

  # Case 4: src does not exist
  log "Create symlink: $src -> $dst"
  run ln -s "$dst" "$src"
done

log "==> Ensure settings.json exists"
if [[ ! -f "$CLAUDE_REAL/settings.json" ]]; then
  run tee "$CLAUDE_REAL/settings.json" >/dev/null <<'JSON'
{
  "hooks": {}
}
JSON
else
  log "settings.json already exists, skip"
fi

echo
log "==> Done"
log "Verify:"
log "  ls -l ~/.claude"
log "  ls -l \"$CLAUDE_REAL\""
log "  readlink ~/.claude"
log "  readlink \"$CLAUDE_REAL/plugins\""
