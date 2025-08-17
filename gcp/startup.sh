#!/usr/bin/env bash
set -euo pipefail

# Read instance metadata attributes
meta() { curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1" || true; }

REPO_URL="$(meta repo_url)"
MCP_INSTANCE_URL="$(meta mcp_instance_url)"
APP_PORT="$(meta app_port)"
DOMAIN="$(meta domain)"

APP_PORT="${APP_PORT:-3080}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
curl -fsSL https://get.docker.com | sh
usermod -aG docker ${SUDO_USER:-ubuntu} 2>/dev/null || true
apt-get install -y docker-compose-plugin caddy git python3

mkdir -p /opt/librechat/{images,uploads,logs,data-node,meili_data_v1.12}
cd /opt/librechat

if [ -n "$REPO_URL" ]; then
  if [ -d .git ]; then
    git pull --ff-only || true
  else
    git clone "$REPO_URL" . || true
  fi
fi

# Ensure .env exists with minimal defaults; admins will fill secrets later
if [ ! -f .env ]; then
  cat > .env <<EOF
PORT=${APP_PORT}
# Fill these before production use
CREDS_KEY=
CREDS_IV=
JWT_SECRET=
JWT_REFRESH_SECRET=
MEILI_MASTER_KEY=
OPENAI_API_KEY=
MCP_INSTANCE_URL=${MCP_INSTANCE_URL}
EOF
fi

# Ensure librechat.yaml points to MCP /sse
if [ -f librechat.yaml ]; then
  if [ -n "$MCP_INSTANCE_URL" ]; then
    sed -i "s|^\s*url: .*|    url: ${MCP_INSTANCE_URL%/}/sse|" librechat.yaml || true
  fi
fi

docker compose pull || true
docker compose up -d

# Configure Caddy if a domain is provided
if [ -n "$DOMAIN" ]; then
  cat > /etc/caddy/Caddyfile <<CADDY
${DOMAIN} {
  reverse_proxy 127.0.0.1:${APP_PORT}
}
CADDY
  systemctl restart caddy || true
fi

echo "Startup completed for domain='${DOMAIN}' port=${APP_PORT}" 

