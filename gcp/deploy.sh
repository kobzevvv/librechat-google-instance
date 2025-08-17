#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   PROJECT_ID=... REGION=europe-west1 ZONE=europe-west1-b \
#   PROD_DOMAIN=chat.recruiter-assistant.com DEV_DOMAIN=test-chat.recruiter-assistant.com \
#   REPO_URL=https://github.com/your-org/starjourney-assistant.git \
#   MCP_INSTANCE_URL=https://hiring-router-mcp-680223933889.europe-west1.run.app/mcp \
#   ./gcp/deploy.sh

PROJECT_ID=${PROJECT_ID:?set PROJECT_ID}
REGION=${REGION:-europe-west1}
ZONE=${ZONE:-${REGION}-b}
PROD_DOMAIN=${PROD_DOMAIN:?set PROD_DOMAIN}
DEV_DOMAIN=${DEV_DOMAIN:?set DEV_DOMAIN}
REPO_URL=${REPO_URL:?set REPO_URL}
MCP_INSTANCE_URL=${MCP_INSTANCE_URL:?set MCP_INSTANCE_URL}

gcloud config set project "$PROJECT_ID" >/dev/null

create_ip() {
  local name=$1
  if ! gcloud compute addresses describe "$name" --region="$REGION" >/dev/null 2>&1; then
    gcloud compute addresses create "$name" --region="$REGION"
  fi
  gcloud compute addresses describe "$name" --region="$REGION" --format='get(address)'
}

PROD_IP=$(create_ip librechat-prod-ip)
DEV_IP=$(create_ip librechat-dev-ip)

echo "Prod IP: $PROD_IP"
echo "Dev  IP: $DEV_IP"
echo "Update DNS A records before continuing:"
echo "  ${PROD_DOMAIN} -> ${PROD_IP}"
echo "  ${DEV_DOMAIN}  -> ${DEV_IP}"

create_vm() {
  local name=$1 ip=$2 port=$3 domain=$4
  if ! gcloud compute instances describe "$name" --zone="$ZONE" >/dev/null 2>&1; then
    gcloud compute instances create "$name" \
      --zone="$ZONE" \
      --machine-type=e2-standard-2 \
      --address="$ip" \
      --tags=http-server,https-server \
      --boot-disk-size=50GB \
      --image-family=debian-12 --image-project=debian-cloud \
      --metadata-from-file startup-script=gcp/startup.sh \
      --metadata repo_url="$REPO_URL",mcp_instance_url="$MCP_INSTANCE_URL",app_port="$port",domain="$domain"
  else
    echo "$name already exists; updating metadata and restarting startup"
    gcloud compute instances add-metadata "$name" --zone="$ZONE" \
      --metadata repo_url="$REPO_URL",mcp_instance_url="$MCP_INSTANCE_URL",app_port="$port",domain="$domain"
    gcloud compute instances reset "$name" --zone="$ZONE"
  fi
}

create_vm librechat-prod "$PROD_IP" 3080 "$PROD_DOMAIN"
create_vm librechat-dev  "$DEV_IP"  3081 "$DEV_DOMAIN"

echo "Deployment kicked off. It may take ~2-3 minutes."
echo "Then visit: https://${PROD_DOMAIN} and https://${DEV_DOMAIN}"

