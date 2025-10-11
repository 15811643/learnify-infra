#!/usr/bin/env bash
set -euo pipefail
SITE="https://learnify.cloud"

echo "== Apache configtest (sudo) =="
if sudo apache2ctl configtest; then echo "OK"; else exit 1; fi
echo

echo "== TLS files (sudo stat) =="
sudo ls -l /etc/letsencrypt/live/learnify.cloud/ || true
sudo readlink -f /etc/letsencrypt/live/learnify.cloud/fullchain.pem /etc/letsencrypt/live/learnify.cloud/privkey.pem || true
echo

echo "== Headers =="
curl -skI "$SITE/" | egrep -i 'Referrer-Policy|Content-Security|X-Content-Type|Permissions-Policy|Strict-Transport' || true
echo

echo "== Robots.txt =="
curl -sk "$SITE/robots.txt" | sed -n '1,80p' || true
echo

echo "== PHP modules enabled =="
ls -1 /etc/apache2/mods-enabled/php*.load 2>/dev/null || echo "none"
echo

echo "== Recent apache warnings (5m) =="
journalctl -u apache2 --since "5 minutes ago" | egrep -i "already loaded|error|warn" || echo "✅ No recent warnings"
