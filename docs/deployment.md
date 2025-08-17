## Deployment Guide

This guide covers deploying LibreChat to Google Cloud (recommended) and local troubleshooting.

### Environments
- Production: `chat.recruiter-assistant.com` → VM `librechat-prod` → Caddy → `127.0.0.1:3080`
- Development: `test-chat.recruiter-assistant.com` → VM `librechat-dev` → Caddy → `127.0.0.1:3081`
- Local: `http://localhost:3080` (no domain, for troubleshooting only)

### Prerequisites
- `gcloud` CLI authenticated to your project
- DNS control for your domains
- Ability to run shell on macOS/Linux or WSL

### 1) Reserve IPs and create VMs
Run the deploy script with environment variables set:
```bash
export PROJECT_ID=<your-project>
export REGION=europe-west1
export ZONE=europe-west1-b
export PROD_DOMAIN=chat.recruiter-assistant.com
export DEV_DOMAIN=test-chat.recruiter-assistant.com
export REPO_URL=https://github.com/vova-ru/librechat-google-instance.git
export MCP_INSTANCE_URL=https://hiring-router-mcp-680223933889.europe-west1.run.app/mcp
./gcp/deploy.sh
```
The script prints two static IPs. Create A records:
- `chat.recruiter-assistant.com` → Prod IP
- `test-chat.recruiter-assistant.com` → Dev IP

### 2) Secrets on the VM
SSH to the VM and set `.env` in `/opt/librechat`:
```bash
gcloud compute ssh librechat-prod --zone $ZONE
sudo -s
cd /opt/librechat
sed -n '1,200p' .env
# If empty, set values:
printf "PORT=3080\n" > .env
printf "JWT_SECRET=$(openssl rand -hex 32)\n" >> .env
printf "JWT_REFRESH_SECRET=$(openssl rand -hex 32)\n" >> .env
printf "CREDS_KEY=$(openssl rand -hex 32)\n" >> .env
printf "CREDS_IV=$(openssl rand -hex 16)\n" >> .env
printf "MEILI_MASTER_KEY=$(openssl rand -hex 32)\n" >> .env
printf "POSTGRES_DB=librechat\nPOSTGRES_USER=librechat\nPOSTGRES_PASSWORD=$(openssl rand -hex 24)\n" >> .env
docker compose up -d --force-recreate --no-deps api
```

### 3) Verify health
On the VM:
```bash
curl -sSI http://127.0.0.1:3080 | head -n1   # HTTP/1.1 200 OK
```
From your machine:
```bash
curl -I https://chat.recruiter-assistant.com     # HTTP/2 200
```

### 4) Operations
- Restart API only after `.env` changes:
  ```bash
  docker compose up -d --force-recreate --no-deps api
  ```
- Tail logs:
  ```bash
  docker logs -f --tail=200 LibreChat
  ```
- Update images:
  ```bash
  docker compose pull && docker compose up -d
  ```

### Troubleshooting (quick reference)
- 502 from Caddy → check upstream on VM:
  ```bash
  curl -sSI http://127.0.0.1:3080 | head -n1
  docker logs --tail=200 LibreChat
  ```
  If you see `JwtStrategy requires a secret or key`, set `JWT_SECRET` and `JWT_REFRESH_SECRET` in `/opt/librechat/.env` and recreate API.

- Missing permissions for volumes → fix ownership:
  ```bash
  sudo chown -R $(id -u):$(id -g) /opt/librechat/{logs,meili_data_v1.12,uploads,images,data-node}
  ```

- Meilisearch key mismatch → keep `MEILI_MASTER_KEY` stable. To reset, clear `/opt/librechat/meili_data_v1.12` (data loss) and start again.

- Port mapping not working → ensure `.env` has `PORT=3080` before `docker compose up`.

- Caddy configuration → `/etc/caddy/Caddyfile` should contain:
  ```
  ${DOMAIN} {
    reverse_proxy 127.0.0.1:${APP_PORT}
  }
  ```
  Ensure DNS A records point to the VM static IPs.

- MCP warnings (Invalid Content-Type header) → non-blocking. Remove `mcpServers` from `librechat.yaml` to disable temporarily.

### Local troubleshooting (optional)
You can run the stack locally without domains for debugging:
```bash
cp .env.example .env || true
# Fill required keys (see configuration.md)
docker compose up -d
open http://localhost:3080
```

### Deployment (GCP standard)

This repository’s standard deployment targets Google Cloud on Compute Engine VMs with Caddy handling TLS. The application is served on your domains, not on localhost.

#### Primary domains
- Production: https://chat.recruiter-assistant.com
- Development: https://test-chat.recruiter-assistant.com

#### DNS
1. Run the deploy script (below). It will reserve two static IPs and print them.
2. Create A records:
   - `chat.recruiter-assistant.com` → prod IP
   - `test-chat.recruiter-assistant.com` → dev IP

#### Deploy
```bash
export PROJECT_ID=YOUR_PROJECT
export REGION=europe-west1
export ZONE=europe-west1-b
export PROD_DOMAIN=chat.recruiter-assistant.com
export DEV_DOMAIN=test-chat.recruiter-assistant.com
export REPO_URL=https://github.com/vova-ru/librechat-google-instance.git
export MCP_INSTANCE_URL=https://hiring-router-mcp-680223933889.europe-west1.run.app/mcp
./gcp/deploy.sh
```

The script will:
- Create/update two VMs and install Docker + Caddy
- Clone this repo to `/opt/librechat`
- Start the Docker stack
- Configure Caddy to serve your domain over HTTPS

After DNS propagates, access:
- Prod: https://chat.recruiter-assistant.com
- Dev: https://test-chat.recruiter-assistant.com

### Logs and observability (Compute Engine VMs)
- Application logs:
  - Inside container: standard output/error
  - On VM (mounted): `/opt/librechat/logs/*.log`
- Caddy access logs: `/var/log/caddy/access.log` (JSON)
- Docker container logs: `/var/lib/docker/containers/*/*.log`
- Cloud Logging: The VM installs Google Cloud Ops Agent and ships all of the above to Cloud Logging automatically.
  - View in Console: Navigation → Operations → Logging → Logs Explorer; filter by Resource type: GCE VM Instance
  - CLI examples:
    ```bash
    gcloud logging read 'resource.type="gce_instance" AND jsonPayload.container.name="LibreChat"' \
      --limit=50 --format=json | jq '.[].jsonPayload.message'

    gcloud logging read 'resource.type="gce_instance" AND logName:"caddy"' --limit=50 --format=json | jq '.[].textPayload'
    ```

#### Authentication mode
- No-auth (open) mode is enabled via environment flags. See `docs/configuration.md` under “Open access (no-auth)”. These settings are already wired through `docker-compose.override.yml`.

#### Operate on the VM
```bash
gcloud compute ssh librechat-prod --zone $ZONE
sudo -s
cd /opt/librechat
docker compose ps
docker logs -f --tail=200 LibreChat
```

Recreate only the API after env changes:
```bash
docker compose up -d --force-recreate --no-deps api
```

Health checks:
```bash
curl -sSI http://127.0.0.1:3080 | head -n1
```

#### Notes
- Localhost URLs are for troubleshooting only. Production traffic should use the domains above.
- If you require Cloud Run instead of Compute Engine, open a task; we can provide a Cloud Run deployment variant.


