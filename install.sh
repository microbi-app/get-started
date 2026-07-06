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

# When run via `curl | bash`, stdin is the script itself being streamed in —
# so any `read` here must come from the controlling terminal explicitly,
# not from stdin, or it silently consumes the script's own remaining bytes.
if [ ! -r /dev/tty ]; then
  echo "Error: no interactive terminal available (/dev/tty not readable)."
  echo "Run this script directly instead of through a non-interactive pipe:"
  echo "  curl -fsSL https://microbi.app/install.sh -o install.sh && bash install.sh"
  exit 1
fi

# --- detect the server's address so we only have to ask what we can't guess ---
DETECTED_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')
if [ -z "$DETECTED_IP" ]; then
  DETECTED_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi

echo
read -rp "Local port to expose Micro BI on [8080]: " HTTP_PORT < /dev/tty
HTTP_PORT="${HTTP_PORT:-8080}"

DEFAULT_URL="http://${DETECTED_IP:-CHANGE_ME}:${HTTP_PORT}"
echo
echo "Detected address: ${DEFAULT_URL}"
echo "If this server has a domain name or sits behind a reverse proxy,"
echo "enter that instead — otherwise just press Enter to accept it."
read -rp "Public URL [${DEFAULT_URL}]: " APP_URL_INPUT < /dev/tty
APP_URL="${APP_URL_INPUT:-$DEFAULT_URL}"
APP_URL="${APP_URL%/}"

if [ -z "$DETECTED_IP" ] && [ "$APP_URL" = "${DEFAULT_URL%/}" ]; then
  echo "Error: could not auto-detect this server's address, and none was provided."
  exit 1
fi

# --- set up working directory ---
if [ -d "$INSTALL_DIR" ]; then
  echo
  echo "Directory './${INSTALL_DIR}' already exists."
  read -rp "Continue and overwrite its config files? [y/N]: " CONFIRM < /dev/tty
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
fi
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
INSTALL_PATH="$(pwd)"


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
echo " Your generated secrets are saved in: ${INSTALL_PATH}/.env"
echo " Keep this file safe — it's needed to reconnect to your database"
echo " if you ever move or rebuild this server."
echo
echo " Note: if this address is a private/LAN IP (e.g. 192.168.x.x) and you"
echo " plan to access Micro BI from outside this network, make sure the IP"
echo " is static (reserved in your router/DHCP) or use a domain name instead"
echo " — otherwise this address may change after a reboot."
echo
echo " -------------------------------------------"
echo " Useful commands — run these from ${INSTALL_PATH}:"
echo
echo "   docker compose -f docker-compose.prod.yml ps"
echo "     Check status"
echo
echo "   docker compose -f docker-compose.prod.yml logs -f backend"
echo "     View logs"
echo
echo "   docker compose -f docker-compose.prod.yml pull && docker compose -f docker-compose.prod.yml up -d"
echo "     Update to the latest version"
echo
echo " If you ever edit .env by hand (e.g. changing the public address),"
echo " apply it with 'up -d' — NOT 'restart'. Plain 'restart' reuses the"
echo " container's old environment and ignores your .env changes."
echo "============================================="
