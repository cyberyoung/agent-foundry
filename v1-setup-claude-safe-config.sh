#!/usr/bin/env bash
set -euo pipefail

CLAUDE_LINK="$HOME/.claude"

# Resolve ~/.claude real directory.
if [ -L "$CLAUDE_LINK" ]; then
  CLAUDE_REAL="$(cd "$(dirname "$CLAUDE_LINK")" && cd "$(dirname "$(readlink "$CLAUDE_LINK")")" && pwd)/$(basename "$(readlink "$CLAUDE_LINK")")"
else
  CLAUDE_REAL="$CLAUDE_LINK"
fi

BASE_DIR="$(dirname "$CLAUDE_REAL")"
SHARED_REAL="$BASE_DIR/dot-claude-shared"
BACKUP_DIR="$BASE_DIR/dot-claude-backup-$(date +%Y%m%d-%H%M%S)"

echo "Claude link:   $CLAUDE_LINK"
echo "Claude real:   $CLAUDE_REAL"
echo "Shared real:   $SHARED_REAL"
echo "Backup dir:    $BACKUP_DIR"

#echo "==> Create Claude real directory"
#mkdir -p "$CLAUDE_REAL"
echo "==> Verify Claude real directory exists"

if [ ! -d "$CLAUDE_REAL" ]; then
  echo "ERROR: Claude real directory does not exist: $CLAUDE_REAL"
  exit 1
fi
if [ ! -L "$HOME/.claude" ]; then
  echo "ERROR: ~/.claude is not a symlink"
  exit 1
fi

echo "==> Backup current Claude real directory"
mkdir -p "$BACKUP_DIR"

rsync -a \
  --exclude='plugins/cache/' \
  --exclude='**/node_modules/' \
  "$CLAUDE_REAL/" "$BACKUP_DIR/"
#cp -a "$CLAUDE_REAL" "$BACKUP_DIR"

echo "==> Create shared directories"
mkdir -p "$SHARED_REAL"/{plugins,hooks,commands,agents,skills}

echo "==> Migrate directories from Claude real dir to shared dir"
for dir in plugins hooks commands agents skills; do
  src="$CLAUDE_REAL/$dir"
  dst="$SHARED_REAL/$dir"

  mkdir -p "$dst"

  if [ -d "$src" ] && [ ! -L "$src" ]; then
    #cp -a "$src/." "$dst/" 2>/dev/null || true
    rsync -a \
    --exclude='cache/' \
    --exclude='**/node_modules/' \
    "$src/" "$dst/" 2>/dev/null || true
    rm -rf "$src"
  elif [ -L "$src" ]; then
    rm -f "$src"
  fi

  ln -sfn "$dst" "$src"
done

echo "==> Ensure settings.json exists in Claude real dir"
if [ ! -f "$CLAUDE_REAL/settings.json" ]; then
  cat > "$CLAUDE_REAL/settings.json" <<'JSON'
{
  "hooks": {}
}
JSON
fi

echo "==> Ensure ~/.claude points to Claude real dir"
if [ -e "$CLAUDE_LINK" ] || [ -L "$CLAUDE_LINK" ]; then
  if [ ! -L "$CLAUDE_LINK" ]; then
    echo "ERROR: $CLAUDE_LINK exists but is not a symlink."
    echo "Refuse to overwrite it."
    exit 1
  fi
else
  ln -s "$CLAUDE_REAL" "$CLAUDE_LINK"
fi

echo "==> Done"
echo
echo "Verify:"
echo "  ls -l $CLAUDE_LINK"
echo "  ls -l $CLAUDE_REAL"
echo "  readlink $CLAUDE_LINK"
echo "  readlink $CLAUDE_REAL/plugins"
