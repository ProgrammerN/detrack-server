#!/bin/bash
# Configure Firebase Cloud Messaging push on the Detrack tracking server.
#
# Usage:
#   FIREBASE_SERVICE_ACCOUNT_JSON=/path/to/serviceAccount.json ./setup/aws/configure-firebase-push.sh
#
# Optional:
#   SERVER_IP=3.239.244.194
#   SSH_KEY=~/.ssh/lightsail.pem

set -euo pipefail

FIREBASE_SERVICE_ACCOUNT_JSON="${FIREBASE_SERVICE_ACCOUNT_JSON:-}"
SERVER_IP="${SERVER_IP:-3.239.244.194}"
SSH_KEY="${SSH_KEY:-$HOME/Downloads/LightsailDefaultKey-us-east-1.pem}"

if [[ -z "$FIREBASE_SERVICE_ACCOUNT_JSON" || ! -f "$FIREBASE_SERVICE_ACCOUNT_JSON" ]]; then
  echo "Set FIREBASE_SERVICE_ACCOUNT_JSON to a Firebase Admin SDK JSON file path."
  echo "Generate in Firebase Console → Project settings → Service accounts → Generate new private key"
  exit 1
fi

TMP_ENV="$(mktemp)"
python3 - "$FIREBASE_SERVICE_ACCOUNT_JSON" "$TMP_ENV" <<'PY'
import json
import sys

json_path, env_path = sys.argv[1:3]
payload = json.dumps(json.load(open(json_path)))
with open(env_path, "w", encoding="utf-8") as handle:
    handle.write(f"NOTIFICATOR_FIREBASE_SERVICE_ACCOUNT={payload}\n")
PY

trap 'rm -f "$TMP_ENV"' EXIT

scp -o StrictHostKeyChecking=no -i "$SSH_KEY" "$TMP_ENV" "ubuntu@${SERVER_IP}:/tmp/detrack-firebase.env"

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "ubuntu@${SERVER_IP}" bash -s <<'EOF'
set -euo pipefail
ENV_FILE='/opt/detrack/conf/detrack.env'
CONF_FILE='/opt/detrack/conf/traccar.xml'
sudo mkdir -p /opt/detrack/conf

if [[ ! -f "$ENV_FILE" ]]; then
  sudo touch "$ENV_FILE"
fi

if ! grep -q '^CONFIG_USE_ENVIRONMENT_VARIABLES=' "$ENV_FILE" 2>/dev/null; then
  echo 'CONFIG_USE_ENVIRONMENT_VARIABLES=true' | sudo tee -a "$ENV_FILE" >/dev/null
fi

sudo grep -v '^NOTIFICATOR_FIREBASE_SERVICE_ACCOUNT=' "$ENV_FILE" | sudo tee "$ENV_FILE.tmp" >/dev/null || true
sudo mv "$ENV_FILE.tmp" "$ENV_FILE"
sudo cat /tmp/detrack-firebase.env | sudo tee -a "$ENV_FILE" >/dev/null
sudo rm -f /tmp/detrack-firebase.env
sudo chmod 600 "$ENV_FILE"

if ! grep -q "<entry key='notificator.types'>" "$CONF_FILE"; then
  sudo sed -i "/notificator.firebase.mode/i\\    <entry key='notificator.types'>web,mail,command,firebase</entry>" "$CONF_FILE"
else
  sudo sed -i "s|<entry key='notificator.types'>.*</entry>|<entry key='notificator.types'>web,mail,command,firebase</entry>|" "$CONF_FILE"
fi

sudo systemctl restart detrack
EOF

echo "Firebase push configured. detrack service restarted."
