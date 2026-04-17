#!/bin/sh
set -e

# Capture runtime UID/GID from environment variables, defaulting to 1000
PUID=${USER_UID:-1000}
PGID=${USER_GID:-1000}

# Adjust the node user's UID/GID if they differ from the runtime request
if [ "$(id -u node)" -ne "$PUID" ]; then
    echo "Updating node UID to $PUID"
    usermod -o -u "$PUID" node
fi

if [ "$(id -g node)" -ne "$PGID" ]; then
    echo "Updating node GID to $PGID"
    groupmod -o -g "$PGID" node
    usermod -g "$PGID" node
fi

# Always ensure /paperclip is owned by node (handles DO App Platform ephemeral FS)
chown -R node:node /paperclip

# Auto-generate config.json from env vars if missing or in wrong deployment mode
CONFIG_FILE="${PAPERCLIP_CONFIG:-/paperclip/instances/default/config.json}"
CONFIG_DIR=$(dirname "$CONFIG_FILE")
DEPLOY_MODE="${PAPERCLIP_DEPLOYMENT_MODE:-authenticated}"
DEPLOY_EXPOSURE="${PAPERCLIP_DEPLOYMENT_EXPOSURE:-private}"
PUBLIC_URL="${PAPERCLIP_PUBLIC_URL:-}"
DB_URL="${DATABASE_URL:-}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "No config.json found — generating from environment variables..."
    mkdir -p "$CONFIG_DIR"
    chown -R node:node "$(dirname "$CONFIG_DIR")"

    # Determine bind/host based on exposure
    if [ "$DEPLOY_EXPOSURE" = "public" ]; then
        BIND="lan"
        HOST="0.0.0.0"
        BASE_URL_MODE="explicit"
    else
        BIND="lan"
        HOST="0.0.0.0"
        BASE_URL_MODE="auto"
    fi

    # Write config.json
    cat > "$CONFIG_FILE" << CONFIGEOF
{
  "\$meta": { "version": 1, "source": "docker-entrypoint" },
  "database": {
    "mode": "postgres",
    "connectionString": "${DB_URL}",
    "embeddedPostgresDataDir": "${CONFIG_DIR}/../db",
    "embeddedPostgresPort": 54329,
    "backup": { "enabled": true, "intervalMinutes": 60, "retentionDays": 30, "dir": "${CONFIG_DIR}/data/backups" }
  },
  "logging": { "mode": "file", "logDir": "${CONFIG_DIR}/logs" },
  "server": {
    "deploymentMode": "${DEPLOY_MODE}",
    "exposure": "${DEPLOY_EXPOSURE}",
    "bind": "${BIND}",
    "host": "${HOST}",
    "port": 3100,
    "allowedHostnames": [],
    "serveUi": true
  },
  "auth": {
    "baseUrlMode": "${BASE_URL_MODE}",
    "publicBaseUrl": "${PUBLIC_URL}",
    "disableSignUp": false
  },
  "telemetry": { "enabled": true },
  "storage": {
    "provider": "local_disk",
    "localDisk": { "baseDir": "${CONFIG_DIR}/data/storage" }
  },
  "secrets": {
    "provider": "local_encrypted",
    "strictMode": false,
    "localEncrypted": { "keyFilePath": "${CONFIG_DIR}/secrets/master.key" }
  }
}
CONFIGEOF
    chown node:node "$CONFIG_FILE"
    echo "Config generated: ${DEPLOY_MODE}/${DEPLOY_EXPOSURE} at ${CONFIG_FILE}"
fi

exec gosu node "$@"

