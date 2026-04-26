#!/bin/bash
# Weekly task to process paper note image directories

VAULT_PATH="${OBSIDIAN_VAULT:-$HOME/Documents/Obsidian Vault}"
SCRIPT_PATH="$HOME/.config/opencode/skills/ob-images-to-note/scripts/images_to_note.py"

LOG_FILE="$VAULT_PATH/stock/Inbox/纸质笔记/.weekly_process.log"

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE"
}

log "=== Starting weekly paper notes processing ==="

# Process 观点 directory
if [ -d "$VAULT_PATH/stock/Inbox/纸质笔记/观点/" ]; then
	log "Processing: stock/Inbox/纸质笔记/观点/"
	python3 "$SCRIPT_PATH" "$VAULT_PATH/stock/Inbox/纸质笔记/观点/" >>"$LOG_FILE" 2>&1
else
	log "Directory not found: stock/Inbox/纸质笔记/观点/"
fi

# Process 研报 directory
if [ -d "$VAULT_PATH/stock/Inbox/纸质笔记/研报/" ]; then
	log "Processing: stock/Inbox/纸质笔记/研报/"
	python3 "$SCRIPT_PATH" "$VAULT_PATH/stock/Inbox/纸质笔记/研报/" >>"$LOG_FILE" 2>&1
else
	log "Directory not found: stock/Inbox/纸质笔记/研报/"
fi

log "=== Weekly processing completed ==="
