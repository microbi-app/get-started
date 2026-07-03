# Micro BI — Installation Guide (Beta)

Micro BI is self-hosted business intelligence software. This guide walks you through deploying it on your own server.

## Requirements

- A Linux server (or VM) with **Docker** and **Docker Compose v2** installed
- At least **2 GB RAM** and **10 GB free disk space** (more if you expect large ETL imports)
- An open port for the web interface (default `8080`) and, if you plan to use SFTP data sources, port `2222`
- A Micro BI beta license key (request one at [microbi.app](https://microbi.app) — you'll receive it by email)

## Quick install

One command downloads the configuration, generates secure secrets, and starts Micro BI:

```bash
curl -fsSL https://microbi.app/install.sh | bash
```

You'll be asked two things: the public address you'll use to reach Micro BI (e.g. `http://203.0.113.10:8080` or `https://bi.yourcompany.com`), and which local port to listen on (default `8080`). Everything else — database password, JWT signing key, internal service token — is generated automatically with `openssl rand`, each one unique.

Prefer to review the script before running it?

```bash
curl -fsSL https://microbi.app/install.sh -o install.sh
less install.sh
bash install.sh
```

Once it finishes, open the URL you provided. Give it a minute if the page doesn't load right away — database migrations run automatically on first start.

## Manual install

If you'd rather configure things by hand:

```bash
mkdir micro-bi && cd micro-bi
curl -O https://microbi.app/downloads/docker-compose.prod.yml
curl -O https://microbi.app/downloads/.env.example
cp .env.example .env
nano .env
```

Every value marked `CHANGE_ME` **must** be changed before starting:

| Variable | What to set it to |
|---|---|
| `POSTGRES_PASSWORD` | A strong password of your choice. **Must match** the password embedded in `DATABASE_URL` below it — copy it into both places. |
| `DATABASE_URL` | Same password as above, rest of the connection string stays as-is (points to the internal `postgres` service). |
| `JWT_SECRET_KEY` | A random string. Generate one with: `openssl rand -hex 32` |
| `SERVICE_TOKEN` | Another random string, same command — **use a different value than `JWT_SECRET_KEY`**, don't reuse it. |
| `APP_PUBLIC_URL` | The address people will use to reach Micro BI — e.g. `http://203.0.113.10:8080` or `https://bi.yourcompany.com` if you're putting it behind a reverse proxy with TLS. Used in share links and email notifications. |
| `CORS_ORIGINS` | Same value as `APP_PUBLIC_URL`, as a comma-separated list if you have more than one (e.g. an IP and a domain). |
| `ACTIVATION_SERVER_URL` | Leave as `https://activation.microbi.app/api/v1` — this is our license server, not something you host yourself. |
| `HTTP_PORT` | The port you'll access Micro BI on. Default `8080` is fine unless it's already in use on your server. |
| `MICROBI_TAG` | Leave as `beta` to always get the latest beta release, or pin a specific version (e.g. `1.0.0-beta.4`) if you want manual control over updates. |

A few things worth knowing before you fill this in:

- **Never put a `#` comment on the same line as a value.** Docker Compose treats everything after `=` — including a trailing comment — as part of the value itself. Put comments on their own line, above the variable.
- Don't reuse the example passwords in production. They're placeholders for a reason.

Then start it:

```bash
docker compose -f docker-compose.prod.yml up -d
```

This pulls the four pre-built images (`backend`, `frontend`, `sftp`, `pdf-service`) from our public registry, starts PostgreSQL, Redis, and all Micro BI services, and automatically runs database migrations on first start.

Check that everything came up healthy:

```bash
docker compose -f docker-compose.prod.yml ps
```

All services should show `Up` (Postgres and Redis should show `Up (healthy)`).

## First-time setup

Open `http://<your-server>:8080` (or whatever `HTTP_PORT` you chose) in a browser. Since this is a fresh installation, you'll be automatically taken to a **setup wizard** — no need to touch the database directly. Follow the prompts to create your first admin account.

## Activate your license

Once logged in, go to **Settings → License**, paste the license key you received by email, and click **Activate**. Your installation will show as **Pro** during the beta, with the tier badge and expiration date visible on that same page.

If your license approaches its expiry date, you'll see a countdown on the License page. Contact [contact@microbi.app](mailto:contact@microbi.app) if you need it extended.

## Updating to a new version

When we release a new beta version, updating is two commands, run from the folder containing your `docker-compose.prod.yml`:

```bash
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
```

Your data (database, uploaded files, DuckDB warehouse) lives in Docker volumes and is untouched by this process — only the application containers are replaced. Database migrations, if any, run automatically on startup, same as the first install.

**Never run `docker compose down -v`** — the `-v` flag deletes all volumes, which means all your data. A plain `down` (without `-v`) is always safe; it only stops containers.

## Backups

Micro BI stores data in four places, all as Docker volumes:

- `postgres_data` — your projects, users, report definitions, settings
- `duckdb_data` — your imported business data (the analytical warehouse)
- `uploads` — uploaded files
- `etl_inbox` — files staged for ETL processing

Back these up regularly. A simple approach:

```bash
docker run --rm -v micro-bi_postgres_data:/data -v $(pwd):/backup alpine \
  tar czf /backup/postgres_backup_$(date +%Y%m%d).tar.gz -C /data .
```

(repeat for `duckdb_data` and `uploads` with the appropriate volume name)

## Troubleshooting

**Backend keeps restarting / migration errors in logs** — check `docker compose -f docker-compose.prod.yml logs backend`. The most common cause is a typo or trailing comment in `.env` (see the warning above).

**502 Bad Gateway in the browser** — usually means the `backend` container isn't reachable yet. Give it a minute after startup; if it persists, check `docker compose -f docker-compose.prod.yml logs frontend` and `... logs backend`.

**Can't activate a license / "Activation failed"** — confirm your server can reach `https://activation.microbi.app` (no firewall blocking outbound HTTPS), and that you copied the license key exactly as received, with no extra spaces.

**Need help?** [contact@microbi.app](mailto:contact@microbi.app)

---

## What's included in the beta

- Full "Pro" tier feature set (SFTP data sources, scheduled reports, kiosk mode, unlimited users/projects)
- Regular updates as we fix bugs and add features based on your feedback
- Direct line to the developer for support and feature requests

## What to expect as the beta evolves

This is beta software: expect occasional bugs, and please back up your data. When the beta concludes, licenses will transition to the Free tier (5 users, 2 projects, 20 data sources) unless you choose to purchase a Pro subscription — we'll give advance notice by email before this happens. See our [Terms of Service](https://microbi.app/terms.html) for details.