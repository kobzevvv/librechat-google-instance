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
  log {
    output file /var/log/caddy/access.log
    format json
  }
}
CADDY
  systemctl restart caddy || true

  # Install and configure Google Cloud Ops Agent to ship logs to Cloud Logging
  if ! dpkg -s google-cloud-ops-agent >/dev/null 2>&1; then
    curl -sS https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh | bash || true
    apt-get install -y google-cloud-ops-agent || true
  fi

  mkdir -p /opt/librechat/logs || true
  cat > /etc/google-cloud-ops-agent/config.yaml <<'OPS'
logging:
  receivers:
    docker:
      type: filelog
      include_paths:
        - /var/lib/docker/containers/*/*.log
      record_log_file_path: true
    librechat_files:
      type: filelog
      include_paths:
        - /opt/librechat/logs/**/*.log
      record_log_file_path: true
    caddy_access:
      type: filelog
      include_paths:
        - /var/log/caddy/*.log
      record_log_file_path: true
  service:
    pipelines:
      default_pipeline:
        receivers: [docker, librechat_files, caddy_access]
OPS
  systemctl restart google-cloud-ops-agent || true
fi

echo "Startup completed for domain='${DOMAIN}' port=${APP_PORT}" 

