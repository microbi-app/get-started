#!/usr/bin/env bash
# Micro BI — one-line installer
# Usage: curl -fsSL https://microbi.app/install.sh | bash
set -euo pipefail

BASE_URL="https://raw.githubusercontent.com/microbi-app/get-started/main"
INSTALL_DIR="micro-bi"

echo "Micro BI — Installer"
echo "====================="
echo

# --- sanity checks ---
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: Docker is not installed. Install Docker first: https://docs.docker.com/engine/install/"
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "Error: Docker Compose v2 plugin not found. See: https://docs.docker.com/compose/install/"
  exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl is required to generate secrets but was not found."
  exit 1
fi

# --- ask the one thing we can't guess ---
echo "What address will you use to reach Micro BI?"
echo "Examples: http://203.0.113.10:8080  or  https://bi.yourcompany.com"
read -rp "Public URL: " APP_URL
APP_URL="${APP_URL%/}"

echo
echo "Which local port should Micro BI listen on? [8080]: "
read -rp "> " HTTP_PORT
HTTP_PORT="${HTTP_PORT:-8080}"

# --- set up working directory ---
if [ -d "$INSTALL_DIR" ]; then
  echo
  echo "Directory './${INSTALL_DIR}' already exists."
  read -rp "Continue and overwrite its config files? [y/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
fi
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo
echo "Downloading configuration..."
curl -fsSL -o docker-compose.prod.yml "${BASE_URL}/docker-compose.prod.yml"
curl -fsSL -o .env.example "${BASE_URL}/.env.example"

echo "Generating secrets..."
PG_PASSWORD=$(openssl rand -hex 24)
JWT_SECRET=$(openssl rand -hex 32)
SERVICE_TOKEN=$(openssl rand -hex 32)

cp .env.example .env

sed -i.bak \
  -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${PG_PASSWORD}|" \
  -e "s|^DATABASE_URL=.*|DATABASE_URL=postgresql+asyncpg://microbi:${PG_PASSWORD}@postgres:5432/microbi|" \
  -e "s|^JWT_SECRET_KEY=.*|JWT_SECRET_KEY=${JWT_SECRET}|" \
  -e "s|^SERVICE_TOKEN=.*|SERVICE_TOKEN=${SERVICE_TOKEN}|" \
  -e "s|^APP_PUBLIC_URL=.*|APP_PUBLIC_URL=${APP_URL}|" \
  -e "s|^CORS_ORIGINS=.*|CORS_ORIGINS=${APP_URL}|" \
  -e "s|^HTTP_PORT=.*|HTTP_PORT=${HTTP_PORT}|" \
  .env
rm -f .env.bak

echo
echo "Starting Micro BI (this pulls four images from GHCR, may take a minute)..."
docker compose -f docker-compose.prod.yml up -d

echo
echo "Waiting for the backend to come online..."
for i in $(seq 1 30); do
  if docker compose -f docker-compose.prod.yml exec -T backend true >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo
echo "============================================="
echo " Micro BI is starting up."
echo
echo " Open: ${APP_URL}"
echo " (give it a minute if the page doesn't load immediately —"
echo "  database migrations run automatically on first start)"
echo
echo " You'll land on a setup wizard to create your admin account,"
echo " then go to Settings → License to activate your beta key."
echo
echo " Your generated secrets are saved in: $(pwd)/.env"
echo " Keep this file safe — it's needed to reconnect to your database"
echo " if you ever move or rebuild this server."
echo
echo " To check status:  docker compose -f docker-compose.prod.yml ps"
echo " To view logs:      docker compose -f docker-compose.prod.yml logs -f backend"
echo " To update later:   docker compose -f docker-compose.prod.yml pull && docker compose -f docker-compose.prod.yml up -d"
echo "============================================="