#!/bin/bash
# Enable Let's Encrypt HTTPS on an existing Detrack Lightsail instance.
#
# Prerequisites:
#   1. A domain name with an A record pointing to the server public IP
#   2. Lightsail firewall allows TCP 443 (and 80 for certificate validation)
#
# Usage:
#   DOMAIN=track.yourdomain.com ADMIN_EMAIL=you@example.com ./setup/aws/enable-https.sh
#
# Optional:
#   INSTANCE_NAME=detrack-server
#   REGION=us-east-1
#   SSH_KEY=~/.ssh/lightsail.pem
#   SERVER_IP=3.239.244.194

set -euo pipefail

DOMAIN="${DOMAIN:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
INSTANCE_NAME="${INSTANCE_NAME:-detrack-server}"
REGION="${REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
SSH_KEY="${SSH_KEY:-$HOME/Downloads/LightsailDefaultKey-us-east-1.pem}"
SERVER_IP="${SERVER_IP:-$(aws lightsail get-instance --region "$REGION" --instance-name "$INSTANCE_NAME" --query 'instance.publicIpAddress' --output text 2>/dev/null || true)}"

if [[ -z "$DOMAIN" || -z "$ADMIN_EMAIL" ]]; then
  echo "Set DOMAIN and ADMIN_EMAIL."
  echo "Example: DOMAIN=track.example.com ADMIN_EMAIL=admin@example.com $0"
  exit 1
fi

if [[ -z "$SERVER_IP" || "$SERVER_IP" == "None" ]]; then
  echo "Could not resolve SERVER_IP. Pass SERVER_IP explicitly."
  exit 1
fi

echo "Opening HTTPS port on Lightsail..."
aws lightsail open-instance-public-ports \
  --region "$REGION" \
  --instance-name "$INSTANCE_NAME" \
  --port-info fromPort=443,toPort=443,protocol=tcp 2>/dev/null || true

echo "Running certbot on $SERVER_IP for $DOMAIN..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "ubuntu@${SERVER_IP}" bash -s <<EOF
set -euo pipefail
DOMAIN='${DOMAIN}'
ADMIN_EMAIL='${ADMIN_EMAIL}'
INSTALL_DIR='/opt/detrack'

if ! command -v certbot >/dev/null 2>&1; then
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-nginx
fi

sudo certbot --nginx -d "\$DOMAIN" --non-interactive --agree-tos -m "\$ADMIN_EMAIL" --redirect

if ! grep -q "<entry key='web.url'>" "\$INSTALL_DIR/conf/traccar.xml"; then
  sudo sed -i "/<\\/properties>/i\\    <entry key='web.url'>https://\${DOMAIN}</entry>" "\$INSTALL_DIR/conf/traccar.xml"
else
  sudo sed -i "s|<entry key='web.url'>.*</entry>|<entry key='web.url'>https://\${DOMAIN}</entry>|" "\$INSTALL_DIR/conf/traccar.xml"
fi

sudo nginx -t
sudo systemctl reload nginx
sudo systemctl restart detrack
EOF

echo "HTTPS enabled: https://${DOMAIN}"
