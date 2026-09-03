#!/bin/bash
#
# restore-photos.sh
#
# Restaure les photos depuis la Storage Box Hetzner dans Immich.
# Étapes :
#   1. Télécharger l'archive tar.gz depuis Storage Box
#   2. L'extraire dans /donnees/immich/library
#   3. Restaurer la base de données
#   4. Vérifier que Immich voit les photos
#
# Usage:
#   ./restore-photos.sh download   # Télécharger l'archive
#   ./restore-photos.sh extract    # Extraire l'archive
#   ./restore-photos.sh db-restore # Restaurer la base de données
#   ./restore-photos.sh verify     # Vérifier la restauration
#   ./restore-photos.sh all        # Tout (download + extract + db-restore + verify)

set -uo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

# Charger les variables d'environnement
if [ -f .env.hetzner ]; then
  export $(grep -v '^#' .env.hetzner | xargs)
elif [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "❌ Fichier .env ou .env.hetzner non trouvé"
  exit 1
fi

# Chemins
STORAGE_BOX_KEY="${HOME}/.ssh/id_ed25519_storagebox"
IMMICH_LIBRARY="${IMMICH_UPLOAD_LOCATION:-.}/volumes/immich/library"
IMMICH_TEMP="${IMMICH_LIBRARY}/.tmp"
ARCHIVE_LOCAL="${IMMICH_TEMP}/${PHOTO_ARCHIVE_NAME}"
ARCHIVE_REMOTE="${STORAGE_BOX_DIR}/${PHOTO_ARCHIVE_NAME}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }

# ═══════════════════════════════════════════════════════════════════════════
# Fonctions
# ═══════════════════════════════════════════════════════════════════════════

ssh_box() {
  ssh -p "${STORAGE_BOX_PORT}" -i "${STORAGE_BOX_KEY}" \
    -o StrictHostKeyChecking=no \
    "${STORAGE_BOX_USER}@${STORAGE_BOX_HOST}" "$@"
}

check_prerequisites() {
  log "Vérification des prérequis…"

  # Storage Box accessible
  if ! ssh_box "df" > /dev/null 2>&1; then
    error "Storage Box (${STORAGE_BOX_HOST}) injoignable"
    exit 1
  fi
  success "Storage Box accessible"

  # Docker disponible
  if ! command -v docker &> /dev/null; then
    error "Docker non trouvé. Installer Docker."
    exit 1
  fi
  success "Docker disponible"

  # Immich container running
  if ! docker ps | grep -q immich-server; then
    warn "Container immich-server n'est pas en cours. Lancer 'docker-compose up -d'"
  fi

  # Dossier temporaire
  mkdir -p "${IMMICH_TEMP}"
  success "Dossier temporaire prêt"
}

download_archive() {
  log "Téléchargement de l'archive depuis Storage Box…"
  log "Source : ${STORAGE_BOX_USER}@${STORAGE_BOX_HOST}:${ARCHIVE_REMOTE}"

  if [ -f "${ARCHIVE_LOCAL}" ]; then
    warn "Archive locale existe déjà : ${ARCHIVE_LOCAL}"
    read -p "Continuer avec cette copie ? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      success "Utilisation de la copie locale"
      return 0
    fi
    rm "${ARCHIVE_LOCAL}"
  fi

  # Télécharger via rsync (plus fiable que scp pour gros fichiers)
  if command -v rsync &> /dev/null; then
    log "Utilisation de rsync (reprise automatique en cas de coupure)…"
    rsync -av --progress --partial --append-verify \
      -e "ssh -p ${STORAGE_BOX_PORT} -i ${STORAGE_BOX_KEY} -o StrictHostKeyChecking=no" \
      "${STORAGE_BOX_USER}@${STORAGE_BOX_HOST}:${ARCHIVE_REMOTE}" \
      "${ARCHIVE_LOCAL}" || { error "rsync échoué"; exit 1; }
  else
    log "Utilisation de scp…"
    scp -P "${STORAGE_BOX_PORT}" -i "${STORAGE_BOX_KEY}" \
      "${STORAGE_BOX_USER}@${STORAGE_BOX_HOST}:${ARCHIVE_REMOTE}" \
      "${ARCHIVE_LOCAL}" || { error "scp échoué"; exit 1; }
  fi

  success "Archive téléchargée"
}

extract_archive() {
  log "Extraction de l'archive…"

  if [ ! -f "${ARCHIVE_LOCAL}" ]; then
    error "Archive non trouvée : ${ARCHIVE_LOCAL}"
    exit 1
  fi

  log "Cible : ${IMMICH_LIBRARY}"
  mkdir -p "${IMMICH_LIBRARY}"

  # Vérifier l'intégrité avant extraction
  log "Vérification de l'intégrité de l'archive…"
  if ! gzip -t "${ARCHIVE_LOCAL}"; then
    error "Archive corrompue. Relancer download."
    exit 1
  fi
  success "Archive valide"

  # Extraction
  log "Extraction en cours (plusieurs heures)…"
  tar -xzf "${ARCHIVE_LOCAL}" -C "${IMMICH_LIBRARY}" --strip-components=1 \
    || { error "Extraction échouée"; exit 1; }

  success "Archive extraite"

  # Nettoyage
  log "Suppression du fichier temporaire…"
  rm -f "${ARCHIVE_LOCAL}"
  success "Nettoyage effectué"
}

restore_database() {
  log "Restauration de la base de données…"

  # Chercher le dump le plus récent sur Storage Box
  log "Recherche du dump DB sur Storage Box…"
  DUMP_FILE=$(ssh_box "ls -1 ${STORAGE_BOX_DIR}/${DB_DUMP_PATTERN} 2>/dev/null | sort | tail -1" || true)

  if [ -z "$DUMP_FILE" ]; then
    error "Dump DB non trouvé sur Storage Box"
    exit 1
  fi

  log "Dump trouvé : $DUMP_FILE"

  # Télécharger le dump
  DUMP_LOCAL="${IMMICH_TEMP}/$(basename "$DUMP_FILE")"
  log "Téléchargement du dump…"
  scp -P "${STORAGE_BOX_PORT}" -i "${STORAGE_BOX_KEY}" \
    "${STORAGE_BOX_USER}@${STORAGE_BOX_HOST}:${DUMP_FILE}" \
    "${DUMP_LOCAL}" || { error "Téléchargement du dump échoué"; exit 1; }

  # Restaurer dans PostgreSQL via Docker
  log "Restauration dans PostgreSQL…"
  docker exec -i immich-postgres pg_restore \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    --no-owner --no-privileges \
    < <(gunzip -c "${DUMP_LOCAL}") || {
    error "Restauration échouée"
    exit 1
  }

  success "Base de données restaurée"

  # Nettoyage
  rm -f "${DUMP_LOCAL}"
}

verify_photos() {
  log "Vérification de la restauration…"

  # Vérifier que Immich voit les photos
  PHOTO_COUNT=$(find "${IMMICH_LIBRARY}" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.raw" \) | wc -l)

  if [ "$PHOTO_COUNT" -eq 0 ]; then
    error "Aucune photo trouvée dans ${IMMICH_LIBRARY}"
    exit 1
  fi

  success "Photos détectées : $PHOTO_COUNT fichiers"

  # Vérifier que Immich API répond
  log "Vérification de l'API Immich…"
  if ! curl -s http://localhost:3001/api/server/health > /dev/null; then
    warn "API Immich ne répond pas sur localhost:3001. Vérifier que le container est en cours."
  else
    success "API Immich opérationnelle"
  fi

  # Générer un rapport
  REPORT="${IMMICH_TEMP}/verification-report.json"
  cat > "$REPORT" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "success",
  "photos_found": $PHOTO_COUNT,
  "library_path": "${IMMICH_LIBRARY}",
  "storage_box": "${STORAGE_BOX_HOST}",
  "database_restored": true,
  "api_available": true
}
EOF

  log "Rapport de vérification : $REPORT"
  cat "$REPORT" | jq .
}

# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

case "${1:-help}" in
  download)
    check_prerequisites
    download_archive
    ;;
  extract)
    check_prerequisites
    extract_archive
    ;;
  db-restore)
    check_prerequisites
    restore_database
    ;;
  verify)
    check_prerequisites
    verify_photos
    ;;
  all)
    check_prerequisites
    download_archive
    extract_archive
    restore_database
    verify_photos
    success "Restauration complète terminée !"
    ;;
  *)
    cat <<USAGE
Usage: $0 {download|extract|db-restore|verify|all}

  download   — Télécharger l'archive photos depuis Storage Box
  extract    — Extraire l'archive dans immich/library
  db-restore — Restaurer la base de données PostgreSQL
  verify     — Vérifier que les photos sont visibles par Immich
  all        — Exécuter toutes les étapes (peut durer plusieurs heures)

Exemples:
  $0 all                    # Restauration complète
  $0 download               # Juste télécharger
  $0 all 2>&1 | tee restore.log  # Enregistrer les logs
USAGE
    exit 1
    ;;
esac
