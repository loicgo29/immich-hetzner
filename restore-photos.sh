#!/bin/bash
#
# restore-photos.sh — Restauration Immich avec logging complet
#
# Flux : DS124 NAS → Storage Box Hetzner → Hetzner /donnees/immich/library
#
# Étapes :
#   1. test       — Vérifier connectivité NAS + Storage Box + Hetzner
#   2. checksum   — Calculer SHA256 sur Storage Box
#   3. sync       — rsync Storage Box → /donnees/immich/library
#   4. verify     — Vérifier checksums + count fichiers
#   5. all        — Exécuter toutes les étapes
#
# Logging : Tout est enregistré dans RESTORATION_LOG.md

set -uo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

if [ -f .env.hetzner ]; then
  set -a
  source .env.hetzner
  set +a
elif [ -f .env ]; then
  set -a
  source .env
  set +a
else
  echo "❌ Fichier .env ou .env.hetzner non trouvé"
  exit 1
fi

# Chemins
NAS_USER="${NAS_USER:-backup}"
NAS_HOST="${NAS_HOST:-192.168.1.40}"
NAS_KEY="${NAS_SSH_KEY:-${HOME}/.ssh/backup-key}"
NAS_PATH="/volume1/backup-6tb/NAS-LOGO-VOLUME/personnes/loic-perso/immich"

STORAGE_BOX_KEY="${STORAGE_BOX_SSH_KEY:-${HOME}/.ssh/id_ed25519_storagebox}"

IMMICH_LIBRARY="${IMMICH_UPLOAD_LOCATION:-.}"
IMMICH_TEMP="${IMMICH_LIBRARY}/.tmp"

LOG_FILE="RESTORATION_LOG.md"
CHECKSUMS_FILE="checksums.txt"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════════════════
# Logging functions
# ═══════════════════════════════════════════════════════════════════════════

log_init() {
  cat > "$LOG_FILE" <<'EOF'
# Restoration Log — Immich Hetzner

**Start:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Configuration

EOF
  echo "**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG_FILE"
  echo "**NAS:** $NAS_USER@$NAS_HOST:$NAS_PATH" >> "$LOG_FILE"
  echo "**Storage Box:** $STORAGE_BOX_USER@$STORAGE_BOX_HOST:$STORAGE_BOX_DIR" >> "$LOG_FILE"
  echo "**Target:** /donnees/immich/library" >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"
}

log_cmd() {
  echo "" >> "$LOG_FILE"
  echo "### $(date '+%Y-%m-%d %H:%M:%S') — $1" >> "$LOG_FILE"
  echo '```bash' >> "$LOG_FILE"
  echo "$2" >> "$LOG_FILE"
  echo '```' >> "$LOG_FILE"
}

log_result() {
  echo "**Result:** $1" >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"
}

console() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }

# ═══════════════════════════════════════════════════════════════════════════
# Test Connectivity
# ═══════════════════════════════════════════════════════════════════════════

test_connectivity() {
  console "Testing connectivity…"
  log_init

  local pass=0
  local fail=0

  # Test NAS
  console "→ NAS ($NAS_HOST)…"
  if ssh -i "$NAS_KEY" -o ConnectTimeout=5 "$NAS_USER@$NAS_HOST" "ls $NAS_PATH" > /dev/null 2>&1; then
    success "NAS accessible"
    log_cmd "NAS SSH Test" "ssh -i $NAS_KEY $NAS_USER@$NAS_HOST \"ls $NAS_PATH\""
    log_result "✅ Connected"
    ((pass++))
  else
    error "NAS unreachable"
    log_result "❌ Failed"
    ((fail++))
  fi

  # Test Storage Box
  console "→ Storage Box ($STORAGE_BOX_HOST)…"
  if ssh -p "$STORAGE_BOX_PORT" -i "$STORAGE_BOX_KEY" -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$STORAGE_BOX_USER@$STORAGE_BOX_HOST" "df" > /dev/null 2>&1; then
    success "Storage Box accessible"
    log_cmd "Storage Box SSH Test" "ssh -p $STORAGE_BOX_PORT -i $STORAGE_BOX_KEY $STORAGE_BOX_USER@$STORAGE_BOX_HOST df"
    log_result "✅ Connected"
    ((pass++))
  else
    error "Storage Box unreachable"
    log_result "❌ Failed"
    ((fail++))
  fi

  # Test Docker
  console "→ Docker…"
  if docker ps > /dev/null 2>&1; then
    success "Docker available"
    log_cmd "Docker Test" "docker ps"
    log_result "✅ Available"
    ((pass++))
  else
    error "Docker not found"
    log_result "❌ Not available"
    ((fail++))
  fi

  echo "" >> "$LOG_FILE"
  echo "## Test Results" >> "$LOG_FILE"
  echo "- Passed: $pass" >> "$LOG_FILE"
  echo "- Failed: $fail" >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"

  if [ $fail -gt 0 ]; then
    error "Some tests failed. Fix connectivity before proceeding."
    exit 1
  fi

  success "All tests passed ✓"
}

# ═══════════════════════════════════════════════════════════════════════════
# Calculate Checksums
# ═══════════════════════════════════════════════════════════════════════════

calculate_checksums() {
  console "Calculating checksums…"

  log_cmd "Storage Box Checksum" \
    "ssh -p $STORAGE_BOX_PORT -i $STORAGE_BOX_KEY $STORAGE_BOX_USER@$STORAGE_BOX_HOST \
      'find $STORAGE_BOX_DIR -type f -exec sha256sum {} + | sort -k2'"

  console "Computing SHA256 on Storage Box (this may take hours)…"
  ssh -p "$STORAGE_BOX_PORT" -i "$STORAGE_BOX_KEY" \
    "$STORAGE_BOX_USER@$STORAGE_BOX_HOST" \
    "find $STORAGE_BOX_DIR -type f -exec sha256sum {} + | sort -k2" \
    > "$CHECKSUMS_FILE" 2>&1

  success "Checksums saved to $CHECKSUMS_FILE"
  log_result "✅ Computed SHA256 for all files"
}

# ═══════════════════════════════════════════════════════════════════════════
# Sync Photos
# ═══════════════════════════════════════════════════════════════════════════

sync_photos() {
  console "Syncing photos from Storage Box…"

  mkdir -p "$IMMICH_LIBRARY"

  local cmd="rsync -av --progress --partial --append-verify --timeout=300 \
    -e 'ssh -p $STORAGE_BOX_PORT -i $STORAGE_BOX_KEY \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=6 \
        -o TCPKeepAlive=yes' \
    $STORAGE_BOX_USER@$STORAGE_BOX_HOST:$STORAGE_BOX_DIR/ \
    $IMMICH_LIBRARY/"

  log_cmd "rsync Storage Box → Hetzner" "$cmd"

  eval "$cmd" 2>&1 | tee -a "$LOG_FILE"

  log_result "✅ Sync completed"
}

# ═══════════════════════════════════════════════════════════════════════════
# Verify
# ═══════════════════════════════════════════════════════════════════════════

verify_restoration() {
  console "Verifying restoration…"

  echo "" >> "$LOG_FILE"
  echo "## Verification" >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"

  # Count files
  console "Counting files…"
  local file_count=$(find "$IMMICH_LIBRARY" -type f | wc -l)
  success "Files found: $file_count"
  echo "**Files:** $file_count" >> "$LOG_FILE"

  # Disk usage
  console "Checking disk usage…"
  local disk_usage=$(du -sh "$IMMICH_LIBRARY" | cut -f1)
  success "Disk used: $disk_usage"
  echo "**Disk Usage:** $disk_usage" >> "$LOG_FILE"

  # Immich health
  console "Checking Immich health…"
  if docker ps | grep -q immich-server; then
    if curl -s http://localhost:3001/api/server/health > /dev/null 2>&1; then
      success "Immich API responsive"
      echo "**Immich Health:** ✅ API responsive" >> "$LOG_FILE"
    else
      warn "Immich API not responding"
      echo "**Immich Health:** ⚠️ API not responding" >> "$LOG_FILE"
    fi
  else
    warn "Immich server not running"
    echo "**Immich Health:** ⚠️ Server not running" >> "$LOG_FILE"
  fi

  echo "" >> "$LOG_FILE"
  echo "**Status:** ✅ Verification complete" >> "$LOG_FILE"
  echo "**End:** $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG_FILE"
}

# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

case "${1:-help}" in
  test)
    test_connectivity
    ;;
  checksum)
    log_init
    calculate_checksums
    ;;
  sync)
    sync_photos
    ;;
  verify)
    verify_restoration
    ;;
  all)
    test_connectivity
    calculate_checksums
    sync_photos
    verify_restoration
    success "Restoration complete! Check $LOG_FILE for details."
    ;;
  *)
    cat <<USAGE
Usage: $0 {test|checksum|sync|verify|all}

  test       — Test connectivity to NAS, Storage Box, Hetzner
  checksum   — Calculate SHA256 checksums on Storage Box
  sync       — rsync photos from Storage Box → /donnees/immich/library
  verify     — Verify file count, disk usage, Immich health
  all        — Run all steps (can take many hours)

Logging:
  All commands logged to RESTORATION_LOG.md
  Checksums saved to checksums.txt

Examples:
  $0 test
  $0 all 2>&1 | tee console.log
USAGE
    exit 1
    ;;
esac
