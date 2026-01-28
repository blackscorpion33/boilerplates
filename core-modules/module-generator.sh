#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Module Generator Script (Namespace-Safe + Custom Configs)
# ============================================

SERVICE_NAME="${1:-}"

if [[ -z "$SERVICE_NAME" ]]; then
    echo "Usage: $0 <service>"
    exit 1
fi

# Sanitize service name for variable usage
VAR_PREFIX=$(echo "$SERVICE_NAME" | tr '[:lower:]' '[:upper:]' | tr -d '-' | tr -d '.')
MODULE_OUTPUT_DIR="/home/docker/modules"
mkdir -p "$MODULE_OUTPUT_DIR"
MODULE_FILE="${MODULE_OUTPUT_DIR}/${SERVICE_NAME}.sh"

# Pre-expand function names
INSTALL_FUNC="install_${SERVICE_NAME}"
UNINSTALL_FUNC="uninstall_${SERVICE_NAME}"
HEALTH_FUNC="health_${SERVICE_NAME}"
MENU_FUNC="${SERVICE_NAME}_menu"

cat <<EOF > "$MODULE_FILE"
#!/usr/bin/env bash
# Module: $SERVICE_NAME

# --- Namespaced Variables ---
${VAR_PREFIX}_NAME="$SERVICE_NAME"
${VAR_PREFIX}_BASE="/home/docker/services/\$${VAR_PREFIX}_NAME"
${VAR_PREFIX}_COMPOSE="\$${VAR_PREFIX}_BASE/docker-compose.yml"

# ADD EXTRA DIRECTORIES HERE (e.g., "tor" "config" "logs")
EXTRA_DIRS=("uploads" "db")

# --------------------------------------------
# WRITE EXTRA CONFIG FILES
# --------------------------------------------
_write_${SERVICE_NAME}_configs() {
    echo "Writing custom configuration files..."

    # Example for Tor or custom configs:
    # cat <<'CONF' > "\$${VAR_PREFIX}_BASE/config/custom_settings.conf"
    # setting=enabled

    # CONF
}

# --------------------------------------------
# WRITE COMPOSE
# --------------------------------------------
_write_${SERVICE_NAME}_compose() {
    mkdir -p "\$${VAR_PREFIX}_BASE"
    cat <<'YAML' > "\$${VAR_PREFIX}_COMPOSE"
services:
  ${SERVICE_NAME}:
    image: ${SERVICE_NAME}:latest
    container_name: ${SERVICE_NAME}
    restart: always
    env_file: .env
    # volumes:
    #   - ./uploads:/uploads
    #   - ./db:/db

##########################################################
#  Do not remove # change th efollowing for your network
##########################################################
    networks:
      - proxy
networks:
  proxy:
    external: true
YAML
}

# --------------------------------------------
# WRITE ENV
# --------------------------------------------
_write_${SERVICE_NAME}_env() {
    cat <<ENV > "\$${VAR_PREFIX}_BASE/.env"
# Environment for \$${VAR_PREFIX}_NAME

#####################################################################
#  used as hardcoded env below Add other environment variables above
#####################################################################
PUID=1000
PGID=1000
TZ=America/Detroit
# Paths used by script
UPLOAD_LOCATION=\$${VAR_PREFIX}_BASE/uploads
DB_DATA_LOCATION=\$${VAR_PREFIX}_BASE/db
ENV
}
# --------------------------------------------
# INSTALL
# --------------------------------------------
$INSTALL_FUNC() {
    echo "=== Installing \$${VAR_PREFIX}_NAME ==="
    mkdir -p "\$${VAR_PREFIX}_BASE"

    # 1. Create Extra Directories from the array
    for dir in "\${EXTRA_DIRS[@]}"; do
        mkdir -p "\$${VAR_PREFIX}_BASE/\$dir"
        echo "Created directory: \$dir"
    done

    # 2. Run the writers
    _write_${SERVICE_NAME}_env
    _write_${SERVICE_NAME}_configs
    _write_${SERVICE_NAME}_compose

    # 3. Permissions Check (Fixes Tor/DB permission issues)
    # chown -R 1000:1000 "\$${VAR_PREFIX}_BASE"

    cd "\$${VAR_PREFIX}_BASE"
    docker compose up -d
    echo "✓ \$${VAR_PREFIX}_NAME installed."
}

# --------------------------------------------
# UNINSTALL / HEALTH / MENU (Standard Logic)
# --------------------------------------------
$UNINSTALL_FUNC() {
    echo "=== Uninstalling \$${VAR_PREFIX}_NAME ==="
    if [[ -d "\$${VAR_PREFIX}_BASE" ]]; then
        cd "\$${VAR_PREFIX}_BASE"
        docker compose down || true
    fi
}

$HEALTH_FUNC() {
    if docker ps --format '{{.Names}}' | grep -q "^\$${VAR_PREFIX}_NAME\\$"; then
        echo -e "✓ \$${VAR_PREFIX}_NAME is running"
    else
        echo -e "✗ \$${VAR_PREFIX}_NAME is not running"
    fi
}

$MENU_FUNC() {
    while true; do
        clear
        echo "=== \$${VAR_PREFIX}_NAME Manager ==="
        echo "1) Install / Update"
        echo "2) Uninstall (Stop)"
        echo "3) Health Check"
        echo "0) Return"
        echo ""
        read -rp "Select Choice: " c
        case "\$c" in
            1) $INSTALL_FUNC ;;
            2) $UNINSTALL_FUNC ;;
            3) $HEALTH_FUNC ;;
            0) return ;;
            *) echo "Invalid option" ;;
        esac
        read -rp "Press Enter to continue..."
    done
}

if [[ "\${BASH_SOURCE[0]}" == "\$0" ]]; then
    $MENU_FUNC
fi
EOF

chmod +x "$MODULE_FILE"
echo "Module created with Config/Directory support: $MODULE_FILE"
