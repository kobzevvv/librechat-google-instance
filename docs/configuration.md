## Configuration Reference

This document lists the key environment variables and configuration files used by this deployment.

### Core environment variables (API container)
- `PORT` (default: 3080) — Port the API/UI listens on. Must be set because compose maps `${PORT}:${PORT}`.
- `JWT_SECRET` — Required. Long random string.
- `JWT_REFRESH_SECRET` — Required. Long random string.
- `CREDS_KEY` — Required. 64 hex chars (32 bytes). Use `openssl rand -hex 32`.
- `CREDS_IV` — Required. 32 hex chars (16 bytes). Use `openssl rand -hex 16`.
- `MONGO_URI` — Defaults to `mongodb://mongodb:27017/LibreChat` via compose.
- `MEILI_HOST` — Defaults to `http://meilisearch:7700` via compose.
- `MEILI_MASTER_KEY` — Required for Meilisearch access. Keep stable across restarts.
- `RAG_API_URL` — Defaults to `http://rag_api:${RAG_PORT}`.
- `RAG_PORT` — Defaults to 8000.

### Vector DB (pgvector)
- `POSTGRES_DB` — Required.
- `POSTGRES_USER` — Required.
- `POSTGRES_PASSWORD` — Required; choose a strong value.

### Optional login flags (for closed deployments)
- `ALLOW_EMAIL_LOGIN`, `ALLOW_REGISTRATION`, `ALLOW_SOCIAL_LOGIN`, `ALLOW_SOCIAL_REGISTRATION`
  - Set to `false` to keep the instance closed for public signups/logins.

### Files and mounts
- `.env` (project root) — Bind-mounted into API container as `/app/.env`.
- `docker-compose.override.yml` — Adds `environment:` for `JWT_*` and `CREDS_*`, mounts `librechat.yaml`.
- `librechat.yaml` — Custom configuration loaded by the app. This repo sets the MCP SSE endpoint.
- Volumes:
  - `/opt/librechat/images` → `/app/client/public/images`
  - `/opt/librechat/uploads` → `/app/uploads`
  - `/opt/librechat/logs` → `/app/api/logs`
  - `/opt/librechat/meili_data_v1.12` → `/meili_data`

### MCP configuration
In `librechat.yaml`:
```yaml
version: "1.2.8"
mcpServers:
  hiring-router:
    type: sse
    url: https://hiring-router-mcp-680223933889.europe-west1.run.app/mcp/sse
```
To disable temporarily, remove the `mcpServers` section and restart the API.

### Security notes
- Treat `.env` as sensitive. Avoid committing secrets.
- Consider adding Cloudflare Access or GCP IAP in front of your domain.
- If you require per-user tokens for MCP, add an `Authorization` header in `librechat.yaml` and wire a user-variable.

### Configuration reference

This repo deploys a LibreChat instance via Docker. Configure it primarily through environment variables. For convenience, see `config/settings.example.yaml` for a human-friendly template you can copy from.

#### Core
- **PORT**: UI/API listen port. Must match `docker-compose.yml` port mapping. Example: `3080`.
- **MCP_INSTANCE_URL**: Base URL to your MCP instance (without trailing `/sse`). Example: `https://your-mcp.run.app/mcp`.

#### Secrets
- **CREDS_KEY**: 64 hex chars (encryption key for stored credentials).
- **CREDS_IV**: 32 hex chars (initialization vector for stored credentials).
- **JWT_SECRET**: Random long string for access tokens.
- **JWT_REFRESH_SECRET**: Random long string for refresh tokens.
- **MEILI_MASTER_KEY**: Master key for Meilisearch.

#### Authentication controls
- **ALLOW_EMAIL_LOGIN**: `true|false`. If `false`, disables email/password login.
- **ALLOW_REGISTRATION**: `true|false`. If `false`, disables self-registration.
- **ALLOW_SOCIAL_LOGIN**: `true|false`. If `false`, hides social login buttons.
- **ALLOW_SOCIAL_REGISTRATION**: `true|false`. If `false`, prevents creating new accounts via social providers.

To run the instance “open” (no authentication), set all four flags above to `false`.

#### RAG/Vector DB
- **RAG_PORT**: Port exposed by the RAG API service (default `8000`).
- **POSTGRES_DB**: Database name for the vector DB.
- **POSTGRES_USER**: Database user for the vector DB.
- **POSTGRES_PASSWORD**: Database password for the vector DB.

#### Notes
- Populate secrets for production. Do not commit real secrets.
- Ensure `PORT` in your environment matches the compose port mapping and any reverse proxy settings.
- `librechat.yaml` in the project root is mounted into the container and may reference `MCP_INSTANCE_URL`.

### Quick recipes

#### Open access (no-auth)
Set in your environment (or compose overrides):

```
ALLOW_EMAIL_LOGIN=false
ALLOW_REGISTRATION=false
ALLOW_SOCIAL_LOGIN=false
ALLOW_SOCIAL_REGISTRATION=false
```

Then restart the stack.

#### Standard secured setup
Set the four flags above to `true` as appropriate, generate strong values for all secrets, and keep `MEILI_MASTER_KEY` private.

### Applying configuration
- Local Docker: set variables in `.env` or in `docker-compose.override.yml` under `services.api.environment`.
- GCP VM (via `gcp/deploy.sh`): a minimal `.env` is created on first boot; update it with your values and restart Docker.


