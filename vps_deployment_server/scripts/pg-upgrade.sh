#!/bin/bash
set -e
set -o pipefail # Catch errors in pipe chains (crucial for backup integrity)

# ==============================================================================
# PostgreSQL Version-Agnostic Upgrade Script (v3 - Automated Edition)
# ==============================================================================

# --- Configuration & Argument Parsing ---
AUTO_CONFIRM=false
if [[ "$1" == "--yes" || "$1" == "-y" ]]; then
  AUTO_CONFIRM=true
  echo "Running in non-interactive mode. Auto-confirmation is ON."
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.production.yaml"

# Dynamically determine the project name from the directory to build the volume name
COMPOSE_PROJECT_NAME=$(basename "$COMPOSE_DIR")
VOLUME_NAME_IN_COMPOSE="vps_deployment_data" # The name from the volumes: section
VOLUME_NAME="${VOLUME_NAME:-${COMPOSE_PROJECT_NAME}_${VOLUME_NAME_IN_COMPOSE}}"

BACKUP_DIR="${BACKUP_DIR:-${COMPOSE_DIR}/backups}"
TEMP_CONTAINER_NAME="pg_upgrade_temp_runner"
PG_USER="${POSTGRES_USER:-postgres}"

# --- Safety Mechanism: Cleanup Trap ---
# Ensures that background containers are stopped and services are restarted on exit.
cleanup() {
  EXIT_CODE=$?
  echo "" # Newline for clarity
  if [ -n "$(docker ps -q -f name=$TEMP_CONTAINER_NAME)" ]; then
    echo "⚠ Stopping temporary container..."
    docker stop $TEMP_CONTAINER_NAME >/dev/null 2>&1 || true
    docker rm $TEMP_CONTAINER_NAME >/dev/null 2>&1 || true
  fi
  
  # Only restart services if the script didn't fail prematurely before shutdown
  if [ "$SERVICES_STOPPED" = "true" ]; then
    echo "▶ Restarting application services..."
    docker compose -f "$COMPOSE_FILE" up -d
  fi

  if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ Upgrade script failed. Please check the logs."
  fi
}
trap cleanup EXIT

echo "=== PostgreSQL Version-Agnostic Upgrade (Safe Mode) ==="
echo ""

# --- Helper Functions ---
detect_current_version() {
  docker run --rm -v "${VOLUME_NAME}:/data:ro" alpine:latest cat /data/PG_VERSION 2>/dev/null || echo ""
}

detect_target_version() {
  grep -E "image:\s*postgres:" "$COMPOSE_FILE" | head -1 | sed -E 's/.*postgres:([0-9]+).*/\1/'
}

wait_for_postgres() {
  echo "Waiting for PostgreSQL to accept connections..."
  for i in {1..60}; do
    if docker exec $TEMP_CONTAINER_NAME pg_isready -U "$PG_USER" -h localhost >/dev/null 2>&1; then
      echo "✓ PostgreSQL is ready."
      return 0
    fi
    sleep 1
  done
  echo "❌ Error: PostgreSQL failed to start within 60 seconds."
  docker logs $TEMP_CONTAINER_NAME
  exit 1
}

# --- Pre-Flight Checks ---
CURRENT_VERSION=$(detect_current_version)
TARGET_VERSION=$(detect_target_version)

echo "Compose Project:      ${COMPOSE_PROJECT_NAME}"
echo "Volume Name:          ${VOLUME_NAME}"
echo "Database User:        ${PG_USER}"
echo "Current Data Version: ${CURRENT_VERSION:-none (fresh install)}"
echo "Target Image Version: ${TARGET_VERSION}"
echo ""

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "❌ Error: docker-compose.production.yaml not found at ${COMPOSE_FILE}"
  exit 1
fi

if [ -z "$CURRENT_VERSION" ]; then
  echo "✓ No existing data directory found. Fresh install will occur automatically."
  exit 0
fi

if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
  echo "✓ Data is already at version ${TARGET_VERSION}. No upgrade needed."
  exit 0
fi

echo "⚠ UPGRADE REQUIRED: ${CURRENT_VERSION} → ${TARGET_VERSION}"

# Create backup directory
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SQL_BACKUP_FILE="${BACKUP_DIR}/pg${CURRENT_VERSION}_dump_${TIMESTAMP}.sql"
RAW_BACKUP_FILE="${BACKUP_DIR}/pg${CURRENT_VERSION}_raw_volume_${TIMESTAMP}.tar.gz"

# --- User Confirmation ---
if [ "$AUTO_CONFIRM" = false ]; then
  echo ""
  echo "!!! RISK WARNING !!!"
  echo "This script will STOP your application, wipe the database volume, and restore."
  echo "Safety measures included:"
  echo "  1. APPLICATION SHUTDOWN: To ensure data consistency."
  echo "  2. LOGICAL BACKUP: pg_dumpall to ${SQL_BACKUP_FILE}"
  echo "  3. PHYSICAL BACKUP: Raw volume tarball to ${RAW_BACKUP_FILE} (The Safety Net)"
  echo ""
  read -p "Are you sure you want to proceed? [y/N]: " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 1
  fi
else
  echo "✓ Auto-confirming upgrade process."
fi

# --- Step 0: Stop Running Services ---
echo ""
echo "▶ Step 0: Stopping application to ensure data consistency..."
docker compose -f "$COMPOSE_FILE" stop serverpod traefik
SERVICES_STOPPED="true"
echo "✓ Services stopped."

# --- Step 1: Start Old Version ---
echo ""
echo "▶ Step 1: Starting temp container (v${CURRENT_VERSION})..."
docker run -d --name $TEMP_CONTAINER_NAME \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -e POSTGRES_USER="$PG_USER" \
  -v "${VOLUME_NAME}:/var/lib/postgresql/data" \
  "postgres:${CURRENT_VERSION}"

wait_for_postgres

# --- Step 2: Logical Backup (pg_dumpall) ---
echo ""
echo "▶ Step 2: Creating logical backup (pg_dumpall)..."
docker exec $TEMP_CONTAINER_NAME pg_dumpall -U "$PG_USER" --clean --if-exists --load-via-partition-root > "$SQL_BACKUP_FILE"

if [ ! -s "$SQL_BACKUP_FILE" ]; then
  echo "❌ CRITICAL ERROR: Dump file is empty or missing!"
  exit 1
fi
echo "✓ Logical backup successful: $(du -h "$SQL_BACKUP_FILE" | cut -f1)"

docker stop $TEMP_CONTAINER_NAME >/dev/null
docker rm $TEMP_CONTAINER_NAME >/dev/null

# --- Step 3: Physical Safety Net (Tarball) ---
echo ""
echo "▶ Step 3: Creating physical safety net (Raw Volume Backup)..."
docker run --rm \
  -v "${VOLUME_NAME}:/data:ro" \
  -v "${BACKUP_DIR}:/backup" \
  alpine:latest \
  tar -czf "/backup/$(basename "$RAW_BACKUP_FILE")" -C /data .

if [ ! -f "$RAW_BACKUP_FILE" ]; then
  echo "❌ CRITICAL ERROR: Failed to create raw backup."
  exit 1
fi
echo "✓ Physical safety net created: $(du -h "$RAW_BACKUP_FILE" | cut -f1)"

# --- Step 4: Wipe Volume ---
echo ""
echo "▶ Step 4: Wiping old data directory..."
docker run --rm \
  -v "${VOLUME_NAME}:/data" \
  alpine:latest \
  sh -c "rm -rf /data/* /data/..?* /data/.[!.]*" # Thoroughly clean hidden files
echo "✓ Volume wiped."

# --- Step 5: Start New Version ---
echo ""
echo "▶ Step 5: Initializing new version (v${TARGET_VERSION})..."
# When initializing, postgres user is required, but data will be owned by PG_USER
docker run -d --name $TEMP_CONTAINER_NAME \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -e POSTGRES_USER="$PG_USER" \
  -e POSTGRES_DB="$PG_USER" \
  -v "${VOLUME_NAME}:/var/lib/postgresql/data" \
  "postgres:${TARGET_VERSION}"

wait_for_postgres

# --- Step 6: Restore Data ---
echo ""
echo "▶ Step 6: Restoring data..."
# Use -v (ON_ERROR_STOP) to ensure we know if the SQL fails
cat "$SQL_BACKUP_FILE" | docker exec -i $TEMP_CONTAINER_NAME psql -U "$PG_USER" -v ON_ERROR_STOP=1 >/dev/null
echo "✓ Data restore completed."

# --- Step 7: Final Cleanup ---
# The trap will handle stopping the temp container and restarting services.
echo ""
echo "▶ Step 7: Final Cleanup..."

# Explicitly setting exit code to 0 to signal success to the trap
EXIT_CODE=0
trap - EXIT # Disable the trap to prevent it from running again on explicit exit
cleanup # Manually call cleanup for a clean exit

echo ""
echo "=========================================="
echo "✓ UPGRADE SUCCESSFUL: ${CURRENT_VERSION} → ${TARGET_VERSION}"
echo "=========================================="
echo "Backups stored in: $BACKUP_DIR"
echo "1. $SQL_BACKUP_FILE (Used for restore)"
echo "2. $RAW_BACKUP_FILE (Keep safe!)"
echo ""
echo "Application services have been restarted."