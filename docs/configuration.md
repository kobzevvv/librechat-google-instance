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


