#!/bin/bash
# Deploy Detrack to AWS Lightsail (~$7/month).
#
# Usage:
#   ./setup/aws/deploy-lightsail.sh
#   DOMAIN=track.example.com ADMIN_EMAIL=you@example.com ./setup/aws/deploy-lightsail.sh
#
# Optional env vars:
#   INSTANCE_NAME   (default: detrack-server)
#   BUNDLE_ID       (default: micro_3_0 = 1GB RAM, $7/mo)
#   REGION          (default: aws configure region or us-east-1)
#   AZ              (default: ${REGION}a)
#   DOMAIN          (optional, for HTTPS via Let's Encrypt)
#   ADMIN_EMAIL     (required if DOMAIN is set)

set -euo pipefail

INSTANCE_NAME="${INSTANCE_NAME:-detrack-server}"
BUNDLE_ID="${BUNDLE_ID:-micro_3_0}"
REGION="${REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
AZ="${AZ:-${REGION}a}"
DOMAIN="${DOMAIN:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"

if [[ -n "$DOMAIN" && -z "$ADMIN_EMAIL" ]]; then
  echo "Set ADMIN_EMAIL when DOMAIN is provided (required for Let's Encrypt)."
  exit 1
fi

GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "GITHUB_TOKEN is required (private repos). Run: gh auth login"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT_B64="$(base64 < "$SCRIPT_DIR/install.sh" | tr -d '\n')"

USER_DATA=$(cat <<EOF
#!/bin/bash
export GITHUB_TOKEN='${GITHUB_TOKEN}'
export DOMAIN='${DOMAIN}'
export ADMIN_EMAIL='${ADMIN_EMAIL}'
echo '${INSTALL_SCRIPT_B64}' | base64 -d > /tmp/detrack-install.sh
chmod +x /tmp/detrack-install.sh
/tmp/detrack-install.sh
EOF
)

echo "Creating Lightsail instance '${INSTANCE_NAME}' in ${AZ} (${BUNDLE_ID}, ~\$7/month)..."
aws lightsail create-instances \
  --region "$REGION" \
  --instance-names "$INSTANCE_NAME" \
  --availability-zone "$AZ" \
  --blueprint-id ubuntu_22_04 \
  --bundle-id "$BUNDLE_ID" \
  --user-data "$USER_DATA" \
  --tags key=project,value=detrack

echo "Waiting for instance to become running..."
for i in $(seq 1 60); do
  STATE=$(aws lightsail get-instance --region "$REGION" --instance-name "$INSTANCE_NAME" --query 'instance.state.name' --output text)
  if [[ "$STATE" == "running" ]]; then
    break
  fi
  sleep 10
done

PUBLIC_IP=$(aws lightsail get-instance --region "$REGION" --instance-name "$INSTANCE_NAME" --query 'instance.publicIpAddress' --output text)
echo "Instance IP: $PUBLIC_IP"

open_port() {
  local from=$1
  local to=${2:-$1}
  local protocol=${3:-tcp}
  aws lightsail open-instance-public-ports \
    --region "$REGION" \
    --instance-name "$INSTANCE_NAME" \
    --port-info "fromPort=${from},toPort=${to},protocol=${protocol}" 2>/dev/null || true
}

echo "Opening firewall ports (web + common GPS device ports)..."
open_port 80
open_port 443
open_port 8082
open_port 5001 5100

echo ""
echo "=============================================="
echo " Detrack Lightsail deployment started"
echo "=============================================="
echo "Instance:  $INSTANCE_NAME"
echo "Region:    $REGION"
echo "Public IP: $PUBLIC_IP"
echo "Cost:      ~\$7/month (micro_3_0 bundle)"
echo ""
echo "Install runs in background (~15-25 min on first boot)."
echo "Monitor progress:"
echo "  ssh ubuntu@${PUBLIC_IP} 'sudo tail -f /var/log/detrack-install.log'"
echo ""
if [[ -n "$DOMAIN" ]]; then
  echo "After install, web UI: https://${DOMAIN}"
  echo "Point DNS A record for ${DOMAIN} -> ${PUBLIC_IP}"
else
  echo "After install, web UI: http://${PUBLIC_IP}"
  echo "Default login: admin / admin (change immediately)"
fi
echo ""
echo "Add more device ports in Lightsail Networking if needed."
echo "=============================================="
