#!/usr/bin/env bash
set -euo pipefail

SRC=/opt/learnify/infra/apache/sites-available
DST=/etc/apache2/sites-available

install -m 0644 -o root -g root "$SRC/app.learnify.cloud.conf"        "$DST/app.learnify.cloud.conf"
install -m 0644 -o root -g root "$SRC/app.learnify.cloud-le-ssl.conf" "$DST/app.learnify.cloud-le-ssl.conf"

# Enable the intended sites (symlinks only)
a2ensite -q app.learnify.cloud.conf app.learnify.cloud-le-ssl.conf >/dev/null || true

# Guards BEFORE reload
/usr/local/sbin/apache-vhost-sanity.sh
/usr/local/sbin/apache-sites-enabled-guard.sh

apachectl -t
systemctl reload apache2
