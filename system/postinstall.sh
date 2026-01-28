#!/usr/bin/env bash
set -euo pipefail

###############################################
# Minimal Server Bootstrap
# Clean Header • Normalized Line Endings
# WireGuard • Docker • Baremetal
###############################################

# Normalize locale
export LC_ALL=C
export LANG=C

###############################################
# Global Paths
###############################################
BASE="/home/docker"
SERVICES_BASE="$BASE/services"

###############################################
# WireGuard Directory Layout
###############################################
WG_DIR="/etc/wireguard"
BASE_WG="$BASE/wireguard"
CLIENT_DIR="$BASE_WG/clients"
META_DIR="$BASE_WG/meta"
DOWNLOAD_DIR="$BASE_WG/downloads"

###############################################
# Create Required Directories
###############################################
mkdir -p "$WG_DIR" "$CLIENT_DIR" "$META_DIR" "$DOWNLOAD_DIR"
chmod 700 "$WG_DIR"
source "$BASE/core-modules/common/colors.sh"

###############################################
# Preflight: Print Resolved Paths
###############################################
echo -e "${CYAN}${BOLD}WireGuard Preflight Directory Check${RESET}"
echo "BASE:        $BASE"
echo "WG_DIR:      $WG_DIR"
echo "BASE_WG:     $BASE_WG"
echo "CLIENT_DIR:  $CLIENT_DIR"
echo "META_DIR:    $META_DIR"
echo "DOWNLOAD_DIR:$DOWNLOAD_DIR"
echo ""

###############################################
# Preflight: Verify Directories Exist
###############################################
missing=0

check_dir() {
    if [[ ! -d "$1" ]]; then
        echo -e "${RED}✗ Missing directory:${RESET} $1"
        missing=1
    else
        echo -e "${GREEN}✓ Exists:${RESET} $1"
    fi
}

check_dir "$WG_DIR"
check_dir "$BASE_WG"
check_dir "$CLIENT_DIR"
check_dir "$META_DIR"
check_dir "$DOWNLOAD_DIR"

if [[ $missing -eq 1 ]]; then
    echo -e "${RED}${BOLD}Preflight failed — required directories missing.${RESET}"
    echo -e "${YELLOW}Fix the paths above and rerun the script.${RESET}"
    exit 1
fi

echo -e "${GREEN}${BOLD}Preflight OK — all directories exist.${RESET}"
echo ""

###############################################
# Load Modules (Correct Order)
###############################################
source "$BASE/core-modules/nftables.sh"
source "$BASE/core-modules/baremetal.sh"
source "$BASE/core-modules/docker.sh"
source "$BASE/core-modules/wireguard.sh"
source "$BASE/core-modules/nas_manager.sh"
#source "$BASE/core-modules/universal_backup_restore.sh"
echo -e "${GREEN}Modules loaded successfully.${RESET}"
echo ""

echo "======================================"
echo "   Starting Minimal Server Bootstrap"
echo "======================================"

########################################
#   Create Network Proxy
########################################
create_proxy_network() {
    local NET="proxy"

    if docker network inspect "$NET" >/dev/null 2>&1; then
        echo -e "${YELLOW}⟳ Proxy network already exists. Skipping.${RESET}"
        return
    fi

    echo -e "${CYAN}Creating Docker proxy network...${RESET}"
    docker network create "$NET" >/dev/null

    echo -e "${GREEN}✓ Proxy network created.${RESET}"
}

###############################################
# 1. Disable IPv6 system-wide
###############################################
echo "[1/7] Disabling IPv6 system-wide..."

cat <<EOF > /etc/sysctl.d/99-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl --system

echo "IPv6 disabled."

###############################################
# 2. Create directory structure
###############################################
echo "[2/7] Creating directory layout..."

mkdir -p "$BASE"/{wireguard/clients,firewall,logs,modules}
mkdir -p "$SERVICES_BASE"

echo "Directory structure created at $BASE"

###############################################
# 3. Install required packages
###############################################
echo "[3/7] Installing packages..."

apt update
apt install -y wireguard curl wget ca-certificates gnupg lsb-release tcpdump

echo "Packages installed."

###############################################
# 4. Install Docker + Compose plugin (official repo)
###############################################
echo "[4/7] Installing Docker..."

if ! command -v docker >/dev/null 2>&1; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list

    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
#    systemctl start docker

    echo "Docker installed."
else
    echo "Docker already installed. Skipping."
fi

###############################################
# Add current user to docker group
###############################################
echo -e "${CYAN}Adding user ${BOLD}$SUDO_USER${RESET}${CYAN} to docker group...${RESET}"

# Ensure docker group exists
groupadd -f docker

# Add the invoking user (not root)
usermod -aG docker "$SUDO_USER"

echo -e "${GREEN}User added to docker group.${RESET}"
echo -e "${YELLOW}You must log out and back in for this to take effect.${RESET}"

###############################################
# 5. Optimize Docker Daemon (IPv6 & Live Restore)
###############################################
echo "[5/7] Checking Docker daemon configuration..."

mkdir -p /etc/docker

# The optimized config we want
WANTED_CONFIG='{"ipv6":false,"live-restore":true}'

# 1. Create the file if it doesn't exist
if [ ! -f /etc/docker/daemon.json ]; then
    echo "$WANTED_CONFIG" > /etc/docker/daemon.json
    systemctl restart docker
    echo "Created daemon.json and started Docker."
else
    # 2. Compare existing config (stripped of whitespace) to our wanted config
    CURRENT_CONFIG=$(tr -d '[:space:]' < /etc/docker/daemon.json)

    if [ "$CURRENT_CONFIG" == "$WANTED_CONFIG" ]; then
        echo "Docker config already optimized. Skipping restart."
    else
        echo "Config mismatch detected. Updating and restarting..."
        echo "$WANTED_CONFIG" > /etc/docker/daemon.json
        systemctl restart docker
        echo "Docker service updated."
    fi
fi

###############################################
# Main Menu (Multi‑Select)
###############################################

while true; do
    echo ""
    echo -e "${BLUE}=== Bare-Metal Services ===${RESET}"
    echo "A) Install Fail2Ban"
    echo "B) Firewall Manager"
    echo "C) NAS Manager"
    echo "D) Vaultwarden Tools"
    echo "E) WireGuard Manager"
    echo "F) Yams Backup & Restore"
    echo "G) Universal Backup"
    echo "H) Uninstall Docker app (by folder name)"
    echo ""

    ###############################################
    # NEW: Dynamic Modules (Under Static Menu)
    ###############################################
    echo -e "${CYAN}=== Dynamic Modules (Auto‑Discovered) ===${RESET}"

    MODULES=()
    i=1
    for mod in "$BASE/modules"/*.sh; do
        [[ -f "$mod" ]] || continue
        modname=$(basename "$mod")
        MODULES+=("$modname")
        echo "  $i) ${modname%.sh}"
        ((i++))
    done

    echo ""

    echo ""
    echo "Q) Quit and show summary"
    echo ""
    echo -e "${YELLOW}You may enter MULTIPLE choices separated by spaces (e.g., A 3 M2 F)${RESET}"
    read -r -a CHOICES

    # Process each choice
    for CHOICE in "${CHOICES[@]}"; do

# Normalize all input to uppercase
CHOICE="${CHOICE^^}"

        case "$CHOICE" in
            # ---------- Static Options ----------
            A) install_fail2ban ;;
            B) firewall_menu ;;
            C) nas_menu ;;
            D) vaultwarden_menu ;;
            E) wireguard_menu ;;
            F) /home/docker/modules/yams_backup_restore.sh ;;
            G) /home/docker/modules/universal_backup_restore.sh ;;
            Q) break 2 ;;

            H)
                echo ""
                read -r -p "Enter Docker app folder name to uninstall (e.g., jellyfin): " APP_TO_REMOVE
                [[ -n "$APP_TO_REMOVE" ]] && uninstall_docker_app "$APP_TO_REMOVE"
                ;;

            # ---------- Dynamic Module Selection ----------
            *)
                num="${CHOICE#M}"
                index=$((num - 1))
                mod="${MODULES[$index]:-}"

                if [[ -n "$mod" ]]; then
                    echo -e "${CYAN}Running module:${RESET} $mod"
                    bash "$BASE/modules/$mod" --interactive
                else
                    echo -e "${YELLOW}Unknown module option:${RESET} $CHOICE"
                fi
                ;;

        esac

    done
done

###############################################
# Post-Install Summary
###############################################
echo -e "${BOLD}${CYAN}======================================${RESET}"
echo -e "${BOLD}${CYAN}        Post-Install Summary          ${RESET}"
echo -e "${BOLD}${CYAN}======================================${RESET}"

# Installed apps
if [[ ${INSTALLED_APPS+x} ]]; then
    INSTALLED_COUNT=${#INSTALLED_APPS[@]}
else
    INSTALLED_COUNT=0
fi

if (( INSTALLED_COUNT > 0 )); then
    echo -e "${GREEN}Installed Apps:${RESET}"
    for app in "${INSTALLED_APPS[@]}"; do
        echo -e "  ${BOLD}- $app${RESET}"
    done
else
    echo -e "${YELLOW}No apps were installed.${RESET}"
fi

# Uninstalled apps
if [[ ${UNINSTALLED_APPS+x} ]]; then
    UNINSTALLED_COUNT=${#UNINSTALLED_APPS[@]}
else
    UNINSTALLED_COUNT=0
fi

if (( UNINSTALLED_COUNT > 0 )); then
    echo ""
    echo -e "${RED}Uninstalled Apps:${RESET}"
    for app in "${UNINSTALLED_APPS[@]}"; do
        echo -e "  ${BOLD}- $app${RESET}"
    done
fi

###############################################
# Done
###############################################

echo "======================================"
echo "Minimal Bootstrap complete."
echo "======================================"
