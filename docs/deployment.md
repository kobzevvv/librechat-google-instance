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


