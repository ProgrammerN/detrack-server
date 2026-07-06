#!/bin/bash
set -euo pipefail

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
DOMAIN="${DOMAIN:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
REPO_URL="${REPO_URL:-https://github.com/ProgrammerN/detrack-server.git}"
INSTALL_DIR="/opt/detrack"
SRC_DIR="/opt/detrack-src"
LOG_FILE="/var/log/detrack-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Detrack install started at $(date -u) ==="

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "GITHUB_TOKEN is required to clone private repositories."
  exit 1
fi

if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git curl nginx certbot python3-certbot-nginx openjdk-21-jdk

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

rm -rf "$SRC_DIR"
git clone "https://${GITHUB_TOKEN}@github.com/ProgrammerN/detrack-server.git" "$SRC_DIR"
cd "$SRC_DIR"
git submodule update --init --recursive

./gradlew assemble -x checkstyleMain -x checkstyleTest --no-daemon

cd traccar-web
npm ci
npm run build

mkdir -p "$INSTALL_DIR"/{conf,data,logs,web,lib,schema,templates/translations}
cp "$SRC_DIR/target/tracker-server.jar" "$INSTALL_DIR/"
cp "$SRC_DIR/target/lib/"* "$INSTALL_DIR/lib/"
cp "$SRC_DIR/schema/"* "$INSTALL_DIR/schema/"
cp -r "$SRC_DIR/templates/"* "$INSTALL_DIR/templates/"
cp -r build/* "$INSTALL_DIR/web/"
cp -r src/resources/l10n/* "$INSTALL_DIR/templates/translations/"
cp "$SRC_DIR/setup/aws/detrack.xml" "$INSTALL_DIR/conf/traccar.xml"
cp "$SRC_DIR/setup/aws/detrack.service" /etc/systemd/system/detrack.service
cp "$SRC_DIR/setup/aws/nginx-detrack.conf" /etc/nginx/sites-available/detrack
ln -sf /etc/nginx/sites-available/detrack /etc/nginx/sites-enabled/detrack
rm -f /etc/nginx/sites-enabled/default

chown -R root:root "$INSTALL_DIR"
chmod -R go+rX "$INSTALL_DIR"

systemctl daemon-reload
systemctl enable detrack
systemctl restart detrack
nginx -t
systemctl restart nginx

if [[ -n "$DOMAIN" && -n "$ADMIN_EMAIL" && "$DOMAIN" != "_" ]]; then
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect || true
fi

echo "=== Detrack install finished at $(date -u) ==="
