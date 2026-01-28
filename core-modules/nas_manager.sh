# Source colors if available
[[ -f "$BASE/modules/common/colors.sh" ]] && source "$BASE/modules/common/colors.sh"

###############################################
# NAS Manager (Multi-Mount Edition)
###############################################

# Mount 1: Media/Jelly
NAS_IP="192.168.1.193"
NAS_SHARE="jelly"
NAS_MOUNT="/mnt/nas"

# Mount 2: Public/Compose Data
PUB_MOUNT="/mnt/pub"
SERVICE_SOURCE="/mnt/pub/Compose/postinstall/services"
SERVICE_DEST="/home/docker/services"

# fstab line for the primary NAS mount
NAS_FSTAB_LINE="//${NAS_IP}/${NAS_SHARE} ${NAS_MOUNT} cifs credentials=/root/.nascreds,iocharset=utf8,uid=1000,gid=1000,file_mode=0777,dir_mode=0777,nofail,x-systemd.automount,x-systemd.requires=network-online.target 0 0"

# Ensure mount points exist
mkdir -p "$NAS_MOUNT" "$PUB_MOUNT"

nas_ensure_fstab() {
    if ! grep -q "^//${NAS_IP}/${NAS_SHARE}" /etc/fstab; then
        echo "$NAS_FSTAB_LINE" >> /etc/fstab
        echo -e "${GREEN}✓ NAS (jelly) entry added to /etc/fstab${RESET}"
    else
        echo -e "${YELLOW}⟳ NAS (jelly) entry already exists in /etc/fstab${RESET}"
    fi
}

nas_mount() {
    nas_ensure_fstab
    mount -a

    # Check both mounts
    for mnt in "$NAS_MOUNT" "$PUB_MOUNT"; do
        if mountpoint -q "$mnt"; then
            echo -e "${GREEN}✓ $mnt is mounted.${RESET}"
        else
            echo -e "${RED}✗ $mnt failed to mount.${RESET}"
        fi
    done
}

# ==========================================
# Sync & Setup Services
# ==========================================
nas_install_services() {
    echo -e "${BOLD}${BLUE}=== Syncing Services from $PUB_MOUNT ===${RESET}"

    # 1. Verify /mnt/pub is actually there
    if ! mountpoint -q "$PUB_MOUNT"; then
        echo -e "${RED}✗ Error: /mnt/pub is not mounted. Cannot sync services.${RESET}"
        return 1
    fi

    # 2. Verify the specific service path exists
    if [ ! -d "$SERVICE_SOURCE" ]; then
        echo -e "${RED}✗ Error: Path not found: $SERVICE_SOURCE${RESET}"
        return 1
    fi

    # 3. Perform the Sync
    mkdir -p "$SERVICE_DEST"
    echo -e "${CYAN}Syncing: $SERVICE_SOURCE -> $SERVICE_DEST${RESET}"
    rsync -avz --delete "$SERVICE_SOURCE/" "$SERVICE_DEST/"

    # 4. Run Setup Scripts
    echo -e "${CYAN}Checking for setup scripts...${RESET}"
    for dir in "$SERVICE_DEST"/*/; do
        if [ -f "${dir}setup.sh" ]; then
            service_name=$(basename "$dir")
            echo -e "${YELLOW}⚙ Executing setup.sh for: ${service_name}...${RESET}"
            chmod +x "${dir}setup.sh"
            (cd "$dir" && ./setup.sh)
        fi
    done
    echo -e "${GREEN}✓ All services synced and initialized.${RESET}"
}

nas_status() {
    echo -e "${BOLD}${BLUE}=== Storage Status ===${RESET}"
    mountpoint -q "$NAS_MOUNT" && echo -e "${GREEN}✓ /mnt/nas (Jelly) is mounted${RESET}" || echo -e "${RED}✗ /mnt/nas is NOT mounted${RESET}"
    mountpoint -q "$PUB_MOUNT" && echo -e "${GREEN}✓ /mnt/pub (Services) is mounted${RESET}" || echo -e "${RED}✗ /mnt/pub is NOT mounted${RESET}"
}

nas_menu() {
    while true; do
        clear
        echo -e "${BOLD}${BLUE}==============================="
        echo -e "           NAS Manager         "
        echo -e "===============================${RESET}"
        echo -e "${CYAN}1)${RESET} Show Storage Status"
        echo -e "${CYAN}2)${RESET} Mount All Drives"
        echo -e "${CYAN}3)${RESET} Sync & Run Service Setups"
        echo -e "${CYAN}4)${RESET} Back to Main Menu"
        echo -e "${BOLD}${BLUE}===============================${RESET}"
        read -r NAS_CHOICE
        case "$NAS_CHOICE" in
            1) nas_status ;;
            2) nas_mount ;;
            3) nas_install_services ;;
            4) break ;;
            *) echo -e "${RED}Invalid choice.${RESET}" ;;
        esac
        echo ""; read -rp "Press ENTER to continue..."
    done
}
