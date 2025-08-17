# StarJourney Assistant (LibreChat + Hiring Router MCP)

## Prereqs
- Docker
- Docker Compose

## Setup
1. Copy envs
   ```bash
   cp .env.example .env
   ```
   Fill in strong values for:
   - `CREDS_KEY` (64 hex chars)
   - `CREDS_IV` (32 hex chars)
   - `JWT_SECRET` (random long)
   - `JWT_REFRESH_SECRET` (random long)

2. Start services
   ```bash
   docker-compose up -d
   ```

3. Open UI
   - `http(s)://<host>:3080`
   - Go to Admin → verify `Recruiter Assistant` is present
   - Click Assistant → no token prompt; MCP is open by URL (no Authorization header)

## Acceptance checks
- MCP health
  ```bash
  curl https://hiring-router-mcp-680223933889.europe-west1.run.app/health
  # {"ok": true}
  ```
- LibreChat boots: UI loads; can log in and see "Recruiter Assistant".
- Tool list loads: Tools from the MCP appear in the UI (no JSON editing).
- Happy path: "Generate job post for Senior Python in Milan" returns content.
- MCP calls succeed without auth headers: GET `/mcp/sse`, POST `/mcp/message`.

## Notes
- `docker-compose.override.yml` supplies secrets via env and mounts `librechat.yaml`.
- MCP SSE endpoint: `https://hiring-router-mcp-680223933889.europe-west1.run.app/mcp/sse`.

## Security posture (temporary)
- Open access by URL. When ready, add one of:
  - Simple server-side bearer check
  - Cloudflare Access or GCP IAP in front of Cloud Run
  - Reintroduce per-user token headers via `librechat.yaml` if needed

## Rollback
- Re-add in `librechat.yaml`:
  - `headers: Authorization: "Bearer {{MCP_TOKEN}}"`
  - `customUserVars` block for `MCP_TOKEN`
- Restore related doc steps prompting for a token
