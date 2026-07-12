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
REMOTE_JSON="/opt/detrack/conf/firebase-service-account.json"

if [[ -z "$FIREBASE_SERVICE_ACCOUNT_JSON" || ! -f "$FIREBASE_SERVICE_ACCOUNT_JSON" ]]; then
  echo "Set FIREBASE_SERVICE_ACCOUNT_JSON to a Firebase Admin SDK JSON file path."
  echo "Generate in Firebase Console → Project settings → Service accounts → Generate new private key"
  exit 1
fi

if ! python3 -c "import json; json.load(open('${FIREBASE_SERVICE_ACCOUNT_JSON}'))" 2>/dev/null; then
  echo "Invalid JSON file: $FIREBASE_SERVICE_ACCOUNT_JSON"
  exit 1
fi

scp -o StrictHostKeyChecking=no -i "$SSH_KEY" "$FIREBASE_SERVICE_ACCOUNT_JSON" "ubuntu@${SERVER_IP}:/tmp/firebase-service-account.json"

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "ubuntu@${SERVER_IP}" bash -s <<EOF
set -euo pipefail
ENV_FILE='/opt/detrack/conf/detrack.env'
CONF_FILE='/opt/detrack/conf/traccar.xml'
sudo mkdir -p /opt/detrack/conf

sudo mv /tmp/firebase-service-account.json "$REMOTE_JSON"
sudo chmod 600 "$REMOTE_JSON"

if [[ -f "\$ENV_FILE" ]]; then
  sudo grep -v '^NOTIFICATOR_FIREBASE_SERVICE_ACCOUNT=' "\$ENV_FILE" | sudo tee "\$ENV_FILE.tmp" >/dev/null || true
  sudo mv "\$ENV_FILE.tmp" "\$ENV_FILE"
fi

if ! grep -q "<entry key='notificator.types'>" "\$CONF_FILE"; then
  sudo sed -i "/notificator.firebase.mode/i\\    <entry key='notificator.types'>web,mail,command,firebase</entry>" "\$CONF_FILE"
else
  sudo sed -i "s|<entry key='notificator.types'>.*</entry>|<entry key='notificator.types'>web,mail,command,firebase</entry>|" "\$CONF_FILE"
fi

if ! grep -q "<entry key='notificator.firebase.serviceAccountFile'>" "\$CONF_FILE"; then
  sudo sed -i "/notificator.firebase.mode/a\\    <entry key='notificator.firebase.serviceAccountFile'>$REMOTE_JSON</entry>" "\$CONF_FILE"
else
  sudo sed -i "s|<entry key='notificator.firebase.serviceAccountFile'>.*</entry>|<entry key='notificator.firebase.serviceAccountFile'>$REMOTE_JSON</entry>|" "\$CONF_FILE"
fi

sudo systemctl restart detrack
EOF

echo "Firebase push configured. detrack service restarted."
