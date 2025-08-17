### Deploying to Google Cloud Run (standard)

Production URL: https://chat.recruiter-assistant.com

This guide deploys the LibreChat API/UI container to Cloud Run. It assumes you have managed services reachable over the network (e.g., MongoDB Atlas for `MONGO_URI`, Meilisearch on a public URL, a RAG API endpoint, and a Postgres with pgvector such as Cloud SQL for PostgreSQL with the pgvector extension enabled).

#### Prereqs
- `gcloud` authenticated
- A GCP project selected
- Custom domain `chat.recruiter-assistant.com` controlled by you

#### Choose env vars (no-auth + secrets)
Set these for open access and required secrets (replace values as needed):

```bash
PROJECT_ID=your-project
REGION=europe-west1
SERVICE_NAME=librechat

# External services
MONGO_URI="mongodb+srv://user:pass@cluster.mongodb.net/LibreChat?retryWrites=true&w=majority"
MEILI_HOST="https://your-meili.example.com"  # include protocol
RAG_API_URL="https://your-rag.example.com"   # include protocol

# Required app secrets
JWT_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_SECRET=$(openssl rand -hex 32)
CREDS_KEY=$(openssl rand -hex 32) # 64 hex chars
CREDS_IV=$(openssl rand -hex 16)  # 32 hex chars

# Open (no-auth) flags
ALLOW_EMAIL_LOGIN=false
ALLOW_REGISTRATION=false
ALLOW_SOCIAL_LOGIN=false
ALLOW_SOCIAL_REGISTRATION=false
```

#### Deploy to Cloud Run
Use the upstream image (no build required):

```bash
gcloud run deploy "$SERVICE_NAME" \
  --image=ghcr.io/danny-avila/librechat-dev:latest \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --platform=managed \
  --execution-environment=gen2 \
  --memory=2Gi --cpu=2 \
  --allow-unauthenticated \
  --set-env-vars=HOST=0.0.0.0 \
  --set-env-vars=MONGO_URI="$MONGO_URI" \
  --set-env-vars=MEILI_HOST="$MEILI_HOST" \
  --set-env-vars=RAG_API_URL="$RAG_API_URL" \
  --set-env-vars=JWT_SECRET="$JWT_SECRET" \
  --set-env-vars=JWT_REFRESH_SECRET="$JWT_REFRESH_SECRET" \
  --set-env-vars=CREDS_KEY="$CREDS_KEY" \
  --set-env-vars=CREDS_IV="$CREDS_IV" \
  --set-env-vars=ALLOW_EMAIL_LOGIN=$ALLOW_EMAIL_LOGIN \
  --set-env-vars=ALLOW_REGISTRATION=$ALLOW_REGISTRATION \
  --set-env-vars=ALLOW_SOCIAL_LOGIN=$ALLOW_SOCIAL_LOGIN \
  --set-env-vars=ALLOW_SOCIAL_REGISTRATION=$ALLOW_SOCIAL_REGISTRATION
```

Notes:
- Cloud Run sets `PORT` automatically; the image listens on `$PORT` via `HOST=0.0.0.0`.
- Ensure external services are reachable from Cloud Run (public endpoints or VPC connectors as needed).

#### Logs and observability (Cloud Run)
- Application logs are automatically shipped to Cloud Logging.
  - View in Console: Navigation → Operations → Logging → Logs Explorer; filter by Resource type: Cloud Run Revision and by service name.
  - CLI example:
    ```bash
    gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME" \
      --limit=100 --format=json | jq '.[].jsonPayload.message? // .[].textPayload?'
    ```

#### Map custom domain
Create a domain mapping and follow the DNS prompts:

```bash
gcloud run domain-mappings create \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --service="$SERVICE_NAME" \
  --domain=chat.recruiter-assistant.com
```

Then add the suggested DNS records at your DNS provider. When validated, your service is live at:

https://chat.recruiter-assistant.com

#### Verifications
```bash
gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format json | jq '.status.url'
curl -I https://chat.recruiter-assistant.com | head -n1
```

If you need MCP over SSE, mount `librechat.yaml` into Cloud Run is not supported directly. Configure MCP endpoints via environment and ensure they are publicly reachable, or run a thin proxy and point the app accordingly.


