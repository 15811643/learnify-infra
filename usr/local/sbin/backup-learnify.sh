#!/usr/bin/env bash
set -euo pipefail

SITE_USER="www-data"
WP_PATH="/var/www/wp_stage"
MOODLE_PATH="/var/www/moodle"
BACKUP_ROOT="/root/backups"
TS="$(date +%F-%H%M%S)"
KEEP_DAYS=14

mkdir -p "$BACKUP_ROOT/db" "$BACKUP_ROOT/files" "$BACKUP_ROOT/configs" "$BACKUP_ROOT/logs"

# Ensure tools exist
command -v mysqldump >/dev/null || { echo "mysqldump not found; installing client"; apt-get update && apt-get install -y mariadb-client >/dev/null; }

# Discover DB creds via wp-cli
DB_NAME=$(sudo -u "$SITE_USER" wp config get DB_NAME --path="$WP_PATH" --allow-root)
DB_USER=$(sudo -u "$SITE_USER" wp config get DB_USER --path="$WP_PATH" --allow-root)
DB_PASS=$(sudo -u "$SITE_USER" wp config get DB_PASSWORD --path="$WP_PATH" --allow-root)
DB_HOST=$(sudo -u "$SITE_USER" wp config get DB_HOST --path="$WP_PATH" --allow-root)

# DB dump
mysqldump -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" --single-transaction --routines --quick "$DB_NAME" \
  | gzip -c > "$BACKUP_ROOT/db/${DB_NAME}-${TS}.sql.gz"

# Files: WordPress + (optional) Moodle
tar -C "$(dirname "$WP_PATH")" -czf "$BACKUP_ROOT/files/wp_stage-${TS}.tgz" "$(basename "$WP_PATH")"
[ -d "$MOODLE_PATH" ] && tar -C "$(dirname "$MOODLE_PATH")" -czf "$BACKUP_ROOT/files/moodle-${TS}.tgz" "$(basename "$MOODLE_PATH")" || true

# Config snapshots (Apache, infra state)
tar -C / -czf "$BACKUP_ROOT/configs/apache-${TS}.tgz" etc/apache2
[ -d /srv/learnify-infra ] && /srv/learnify-infra/sync-infra.sh >/dev/null 2>&1 || true

# Checksums
( cd "$BACKUP_ROOT" && find db files configs -type f -newermt "$(date -d '-1 hour' +%F-%T 2>/dev/null || date -v-1H +%F-%T)" -print0 | xargs -0 sha256sum ) \
  > "$BACKUP_ROOT/logs/sha256-${TS}.txt" || true

# Retention
find "$BACKUP_ROOT/db"      -type f -mtime +$KEEP_DAYS -delete
find "$BACKUP_ROOT/files"   -type f -mtime +$KEEP_DAYS -delete
find "$BACKUP_ROOT/configs" -type f -mtime +$KEEP_DAYS -delete
find "$BACKUP_ROOT/logs"    -type f -mtime +$KEEP_DAYS -delete

echo "Backup complete: ${TS}"
