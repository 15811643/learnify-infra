#!/usr/bin/env bash
set -euo pipefail
TS="$(date +%F-%H%M%S)"
BACKUP_ROOT="/root/backups"
DB_DIR="$BACKUP_ROOT/db"
FILES_DIR="$BACKUP_ROOT/files"
LOG="/var/log/backup-learnify.log"
WP_CONFIG_DEFAULT="/var/www/html/wp-config.php"
WP_CONFIG="${WP_CONFIG:-$WP_CONFIG_DEFAULT}"
KEEP_AGE_DAYS="${KEEP_AGE_DAYS:-14}"
NEEDED_MB="${NEEDED_MB:-2048}"
KEEP_REMOTE_DIRS="${KEEP_REMOTE_DIRS:-1}"
REMOTE="${REMOTE:-gdrive:learnify-backups}"
MOODLE_PATH="${MOODLE_PATH:-/var/www/moodle}"
MOODLEDATA="${MOODLEDATA:-/var/www/moodledata}"

mkdir -p "$DB_DIR" "$FILES_DIR"

free_mb() { df -Pm / | awk 'NR==2{print $4}'; }

prune_oldest_until_free() {
  local class_glob="$1" needed="$2"
  local count i
  mapfile -t newest < <(ls -1t $class_glob 2>/dev/null || true)
  count=${#newest[@]}
  [ "$count" -eq 0 ] && return 0
  while (( $(free_mb) < needed && count > 1 )); do
    victim="${newest[$((count-1))]}"
    echo "[${TS}] pruning local (low space): $victim"
    rm -f -- "$victim" || true
    count=$((count-1))
  done
}

upload_and_prune() {
  local REMOTE_ROOT="$REMOTE"
  local SUB="files"
  local TS_DIR="$(date +%F-%H%M%S)"
  local TARGET="${REMOTE_ROOT}/${SUB}/${TS_DIR}"

  echo "[${TS}] → Uploading to ${TARGET}"
  rclone mkdir "${TARGET}" || true

  [ -d "$DB_DIR" ]    && [ -n "$(ls -A "$DB_DIR" 2>/dev/null)" ]    && rclone copy "$DB_DIR"    "${TARGET}/db"    --transfers=4 --checkers=8
  [ -d "$FILES_DIR" ] && [ -n "$(ls -A "$FILES_DIR" 2>/dev/null)" ] && rclone copy "$FILES_DIR" "${TARGET}/files" --transfers=2 --checkers=8

  echo "[${TS}] → Pruning old remote snapshots (keep ${KEEP_REMOTE_DIRS})"
  mapfile -t snaps < <(rclone lsf "${REMOTE_ROOT}/files" --dirs-only --format p | sed 's#/$##' | sort)
  local count=${#snaps[@]}
  if (( count > KEEP_REMOTE_DIRS )); then
    for (( i=0; i<count-KEEP_REMOTE_DIRS; i++ )); do
      old="${snaps[$i]}"
      [ -n "$old" ] && echo "  - deleting ${old}" && rclone purge "${REMOTE_ROOT}/files/${old}"
    done
  fi
  rclone cleanup "${REMOTE_ROOT%:*}:" >/dev/null 2>&1 || true
}

echo "[${TS}] Starting backup…"

# Space guard
if (( $(free_mb) < NEEDED_MB )); then
  echo "[${TS}] low space: $(free_mb)MB < ${NEEDED_MB}MB, pruning older local archives…"
  prune_oldest_until_free "$FILES_DIR/wp-*.tgz" "$NEEDED_MB"
  prune_oldest_until_free "$FILES_DIR/moodle-*.tgz" "$NEEDED_MB"
  prune_oldest_until_free "$FILES_DIR/moodledata-*.tgz" "$NEEDED_MB"
fi

# DB creds from wp-config
if [ -f "$WP_CONFIG" ]; then
  DB_NAME=$(php -r "include '$WP_CONFIG'; echo DB_NAME;")
  DB_USER=$(php -r "include '$WP_CONFIG'; echo DB_USER;")
  DB_PASS=$(php -r "include '$WP_CONFIG'; echo DB_PASSWORD;")
  DB_HOST=$(php -r "include '$WP_CONFIG'; echo DB_HOST;")
  echo "[$(date +%F' '%T)] Using $WP_CONFIG ; DB=${DB_NAME}@${DB_HOST}"
  # Standardize to TCP for mysqldump
  HOST_FOR_TCP=$(php -r "include '$WP_CONFIG'; echo (strpos(DB_HOST,':')!==false)?explode(':',DB_HOST)[0]:'127.0.0.1';")
else
  echo "[$(date +%F' '%T)] ERROR: wp-config not found at $WP_CONFIG"
  exit 1
fi

# DB dump
echo "[$(date +%F' '%T)] → Dumping ${DB_NAME}@${HOST_FOR_TCP} as ${DB_USER}"
mysqldump -h "$HOST_FOR_TCP" -P 3306 -u "$DB_USER" -p"$DB_PASS" \
  --single-transaction --routines --quick "$DB_NAME" \
| gzip -c > "$DB_DIR/${DB_NAME}-${TS}.sql.gz"

# Files — WordPress
WP_PATH=$(dirname "$WP_CONFIG")
tar -C / \
  --exclude="var/www/html/wp-content/cache" \
  -czf "$FILES_DIR/wp-${TS}.tgz" "${WP_PATH#/}"

# Files — Moodle code (optional)
if [ -d "$MOODLE_PATH" ]; then
  tar -C / -czf "$FILES_DIR/moodle-${TS}.tgz" "${MOODLE_PATH#/}"
fi

# Files — Moodledata (optional)
if [ -d "$MOODLEDATA" ]; then
  tar -C / -czf "$FILES_DIR/moodledata-${TS}.tgz" "${MOODLEDATA#/}"
fi

# Local age retention
find "$DB_DIR" -type f -name '*.sql.gz' -mtime +"$KEEP_AGE_DAYS" -delete || true
find "$FILES_DIR" -type f -name '*.tgz'    -mtime +"$KEEP_AGE_DAYS" -delete || true

# Upload + remote retention
upload_and_prune

echo "✅ Backup complete: ${TS}"

# Retention (keep 14 local + remote)
/usr/local/sbin/backup-retention-14.sh
