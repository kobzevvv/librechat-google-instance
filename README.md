# StarJourney Assistant (LibreChat + Hiring Router MCP)

This repository deploys a production-ready LibreChat instance (API + UI) fronted by Caddy with automatic TLS, plus supporting services (MongoDB, Meilisearch, Postgres pgvector, RAG API). It also integrates a Hiring Router MCP over SSE via `librechat.yaml`.

## Architecture at a glance
- Caddy terminates TLS for your domain and reverse-proxies to `127.0.0.1:3080`.
- LibreChat API/UI container (`ghcr.io/danny-avila/librechat-dev:latest`) listens on `PORT` (default 3080).
- Datastores/services:
  - MongoDB for primary data
  - Meilisearch for search
  - Postgres (pgvector) for embeddings (used by `rag_api`)
  - RAG API (`ghcr.io/danny-avila/librechat-rag-api-dev-lite:latest`) talking to Postgres
- Configuration and secrets come from `.env` and `docker-compose.override.yml`.

## Deploying

### Option A: Local (single host)
1. Create and fill `.env` (you can start from the example below):
   ```bash
   cp .env.example .env || true
   ```
   Required keys (generate strong values):
   - `PORT=3080`
   - `JWT_SECRET` (long random string)
   - `JWT_REFRESH_SECRET` (long random string)
   - `CREDS_KEY` (64 hex chars, e.g. `openssl rand -hex 32`)
   - `CREDS_IV` (32 hex chars, e.g. `openssl rand -hex 16`)
   - `MEILI_MASTER_KEY` (any strong string; must be stable across restarts)
   - `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` (strong password)

2. Start services:
   ```bash
   docker compose up -d
   ```

3. Open the UI: `http://localhost:3080`

### Option B: GCP (fully automated VM with Caddy + TLS)
Prereqs: `gcloud` CLI authenticated, a GCP project, and DNS control for your domain.

1. Set environment and run deploy script:
   ```bash
   export PROJECT_ID=qalearn
   export REGION=europe-west1
   export ZONE=europe-west1-b
   export PROD_DOMAIN=chat.recruiter-assistant.com
   export DEV_DOMAIN=test-chat.recruiter-assistant.com
   export REPO_URL=https://github.com/vova-ru/librechat-google-instance.git
   export MCP_INSTANCE_URL=https://hiring-router-mcp-680223933889.europe-west1.run.app/mcp
   ./gcp/deploy.sh
   ```

2. The script:
   - Reserves static IPs and prompts you to set A records for `PROD_DOMAIN` and `DEV_DOMAIN`.
   - Creates/updates two VMs (`librechat-prod`, `librechat-dev`) and boots Docker/Caddy.
   - Clones this repo into `/opt/librechat` on each VM and starts `docker compose`.
   - Writes `/etc/caddy/Caddyfile` to proxy `${DOMAIN}` → `127.0.0.1:${PORT}` and restarts Caddy.

3. Fill secrets on the VM:
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

4. Verify:
   ```bash
   # On the VM
   curl -sSI http://127.0.0.1:3080 | head -n1   # HTTP/1.1 200 OK
   # From your machine
   curl -I https://chat.recruiter-assistant.com  # HTTP/2 200
   ```

## Operations (Day 2)
- Restart only API after editing `.env`:
  ```bash
  docker compose up -d --force-recreate --no-deps api
  ```
- Tail logs:
  ```bash
  docker logs -f --tail=200 LibreChat
  ```
- Update to latest images:
  ```bash
  docker compose pull && docker compose up -d
  ```
- Where things live on the VM:
  - Repo and compose project: `/opt/librechat`
  - Volumes: `/opt/librechat/{images,uploads,logs,data-node,meili_data_v1.12}`
  - Caddy config: `/etc/caddy/Caddyfile`

## Acceptance checks
- MCP health
  ```bash
  curl https://hiring-router-mcp-680223933889.europe-west1.run.app/health
  # {"ok": true}
  ```
- LibreChat boots: UI loads; can log in and see "Recruiter Assistant".
- Tool list loads: Tools from the MCP appear in the UI.
- Happy path: "Generate job post for Senior Python in Milan" returns content.
- MCP calls succeed without auth headers (current config uses open SSE URL).

## Common pitfalls (dangerous/complicated) and fixes

- 502 from Caddy
  - **Symptom:** Browser shows Caddy 502 Bad Gateway.
  - **Root cause:** Upstream app on `127.0.0.1:3080` not healthy.
  - **Fix:** Check locally on the VM:
    ```bash
    curl -sSI http://127.0.0.1:3080 | head -n1
    docker logs --tail=200 LibreChat
    ```
    If you see `JwtStrategy requires a secret or key`, populate `JWT_SECRET` and `JWT_REFRESH_SECRET` in `/opt/librechat/.env`, then restart only the API:
    ```bash
    docker compose up -d --force-recreate --no-deps api
    ```

- JwtStrategy requires a secret or key
  - **Symptom:** API container restarts; logs show the error above.
  - **Cause:** Missing/empty `JWT_SECRET` and/or `JWT_REFRESH_SECRET` at runtime.
  - **Fix:** Ensure `/opt/librechat/.env` contains non-empty values for `JWT_SECRET`, `JWT_REFRESH_SECRET`, `CREDS_KEY`, `CREDS_IV`, and `PORT=3080`. Verify inside the container:
    ```bash
    docker exec LibreChat sh -lc 'sed -n 1,200p /app/.env | grep -E "PORT=|JWT_SECRET=|JWT_REFRESH_SECRET=|CREDS_KEY=|CREDS_IV="'
    ```
    Then recreate API.

- Volume permissions / write errors
  - **Symptom:** Errors writing logs or Meilisearch data.
  - **Cause:** Host directories not writable by the container UID/GID.
  - **Fix:** On the VM:
    ```bash
    sudo chown -R $(id -u):$(id -g) /opt/librechat/{logs,meili_data_v1.12,uploads,images,data-node}
    ```

- Meilisearch master key mismatch
  - **Symptom:** 401/invalid key when the app reads/writes.
  - **Cause:** `MEILI_MASTER_KEY` changed after data initialization.
  - **Fix:** Keep a stable key. If you must rotate, stop Meili, clear `/opt/librechat/meili_data_v1.12` (data loss), set the new key, and start again.

- Postgres (pgvector) required vars missing
  - **Symptom:** `vectordb` service fails to start.
  - **Fix:** Ensure `.env` provides `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`.

- Port not exposed because `PORT` undefined
  - **Symptom:** API starts but not reachable; compose shows `${PORT}:${PORT}` mapping.
  - **Fix:** Set `PORT=3080` in `.env` before `docker compose up`.

- `.env` vs runtime `env`
  - **Note:** The image loads `/app/.env` via dotenv; `env` inside the container may not show secrets. Trust `/app/.env` content.

- Caddy misconfiguration
  - **Symptom:** Wrong upstream/no TLS.
  - **Fix:** Ensure your Caddyfile is:
    ```
    ${DOMAIN} {
      reverse_proxy 127.0.0.1:3080
    }
    ```
    And that DNS A record points to the VM’s static IP.

- MCP "Invalid Content-Type header"
  - **Symptom:** Non-blocking errors in logs when connecting to the MCP SSE endpoint.
  - **Fix:** App runs fine without MCP. To disable temporarily, remove the `mcpServers` section from `librechat.yaml` and restart API.

## Configuration notes
- `docker-compose.override.yml` injects `CREDS_*` and `JWT_*` from `.env` and mounts `librechat.yaml` into `/app/librechat.yaml`.
- `docker-compose.yml` binds project `.env` into `/app/.env` inside the API container and maps `${PORT}:${PORT}`.
- MCP SSE endpoint in this repo: `https://hiring-router-mcp-680223933889.europe-west1.run.app/mcp/sse`.

## Security posture (temporary)
- Open access by URL. When ready, add one of:
  - Simple server-side bearer check
  - Cloudflare Access or GCP IAP in front of Cloud Run
  - Reintroduce per-user token headers via `librechat.yaml` if needed

## Rollback
- To revert to token-protected MCP, re-add in `librechat.yaml`:
  - `headers: Authorization: "Bearer {{MCP_TOKEN}}"`
  - `customUserVars` block for `MCP_TOKEN`
- Restore related flows that prompt for a token in the UI.

## Quick diagnostics (copy/paste)
```bash
# Container health and logs
docker ps --filter name=LibreChat
docker logs --tail=200 LibreChat

# Secrets inside container (.env contents)
docker exec LibreChat sh -lc 'sed -n 1,200p /app/.env | grep -E "PORT=|JWT_SECRET=|JWT_REFRESH_SECRET=|CREDS_KEY=|CREDS_IV="'

# Local and public reachability
curl -sSI http://127.0.0.1:3080 | head -n1
curl -I https://chat.recruiter-assistant.com | head -n1

# Recreate only the API service
docker compose up -d --force-recreate --no-deps api
```
