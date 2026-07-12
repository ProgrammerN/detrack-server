#!/bin/bash
# Configure Google reverse geocoding on a running Detrack server.
#
# Usage:
#   GEOCODER_KEY=AIza... ./setup/aws/configure-geocoder.sh
#
# Optional:
#   SERVER_IP=3.239.244.194
#   SSH_KEY=~/.ssh/lightsail.pem

set -euo pipefail

GEOCODER_KEY="${GEOCODER_KEY:-}"
SERVER_IP="${SERVER_IP:-3.239.244.194}"
SSH_KEY="${SSH_KEY:-$HOME/Downloads/LightsailDefaultKey-us-east-1.pem}"

if [[ -z "$GEOCODER_KEY" ]]; then
  echo "Set GEOCODER_KEY to your Google Geocoding API key."
  exit 1
fi

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "ubuntu@${SERVER_IP}" bash -s <<EOF
set -euo pipefail
ENV_FILE='/opt/detrack/conf/detrack.env'
sudo mkdir -p /opt/detrack/conf
if [[ ! -f "\$ENV_FILE" ]]; then
  sudo cp /opt/detrack-src/setup/aws/detrack.env.example "\$ENV_FILE" 2>/dev/null || sudo touch "\$ENV_FILE"
fi
if grep -q '^GEOCODER_KEY=' "\$ENV_FILE"; then
  sudo sed -i "s|^GEOCODER_KEY=.*|GEOCODER_KEY=${GEOCODER_KEY}|" "\$ENV_FILE"
else
  echo "GEOCODER_KEY=${GEOCODER_KEY}" | sudo tee -a "\$ENV_FILE" >/dev/null
fi
if ! grep -q '^CONFIG_USE_ENVIRONMENT_VARIABLES=' "\$ENV_FILE"; then
  echo 'CONFIG_USE_ENVIRONMENT_VARIABLES=true' | sudo tee -a "\$ENV_FILE" >/dev/null
fi
sudo chmod 600 "\$ENV_FILE"
sudo systemctl restart detrack
EOF

echo "Geocoder configured. Restart complete."
