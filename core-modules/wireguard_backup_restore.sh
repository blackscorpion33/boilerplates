#!/bin/bash
# Unified WireGuard Backup & Restore Tool (No Compression)
# --------------------------------------------------------
# Features:
#   - Menu-driven interface
#   - Backup WireGuard configs + keys + metadata
#   - Restore from a backup folder
#   - Dual backup destinations:
#         /mnt/pub/wg_backups
#         /mnt/remote_backup/wg_backups
#   - No Traefik logic

# Auto-elevate
if [ "$(id -u)" -ne 0 ]; then
    exec sudo /bin/bash "$(realpath "$0")" "$@"
fi

WG_DIR="/etc/wireguard"
WG_META="/home/docker/wireguard"

DEST1="/mnt/pub/wg_backups"
DEST2="/mnt/remote_backup/wg_backups"

DATE=$(date +"%Y-%m-%d_%H-%M-%S")

backup_wireguard() {
    echo "Starting WireGuard backup..."

    # Create timestamped folders
    mkdir -p "$DEST1/$DATE"
    mkdir -p "$DEST2/$DATE"

    # Copy configs
    cp -v "$WG_DIR"/*.conf "$DEST1/$DATE"/ 2>/dev/null
    cp -v "$WG_DIR"/*.conf "$DEST2/$DATE"/ 2>/dev/null

    # Copy keys
    if [ -d "$WG_DIR/keys" ]; then
        mkdir -p "$DEST1/$DATE/keys"
        mkdir -p "$DEST2/$DATE/keys"
        cp -vr "$WG_DIR/keys"/. "$DEST1/$DATE/keys"/
        cp -vr "$WG_DIR/keys"/. "$DEST2/$DATE/keys"/
    fi

    # Copy metadata
    if [ -d "$WG_META" ]; then
        mkdir -p "$DEST1/$DATE/wireguard-meta"
        mkdir -p "$DEST2/$DATE/wireguard-meta"
        cp -vr "$WG_META"/. "$DEST1/$DATE/wireguard-meta"/
        cp -vr "$WG_META"/. "$DEST2/$DATE/wireguard-meta"/
    fi

    # Backup nftables
    if command -v nft >/dev/null 2>&1; then
        nft list ruleset > "$DEST1/$DATE/nftables.rules"
        cp "$DEST1/$DATE/nftables.rules" "$DEST2/$DATE/nftables.rules"
    fi

    echo ""
    echo "Backup complete:"
    echo "  $DEST1/$DATE/"
    echo "  $DEST2/$DATE/"
}

restore_wireguard() {
    SRC="$1"

    if [ -z "$SRC" ]; then
        echo "Usage: restore <backup_folder>"
        return
    fi

    if [ ! -d "$SRC" ]; then
        echo "Backup folder not found: $SRC"
        return
    fi

    echo "Restoring WireGuard from: $SRC"

    wg-quick down wg0 2>/dev/null

    # Restore configs
    cp -v "$SRC"/*.conf "$WG_DIR"/

    # Restore keys
    if [ -d "$SRC/keys" ]; then
        mkdir -p "$WG_DIR/keys"
        cp -vr "$SRC/keys"/. "$WG_DIR/keys"/
    fi

    # Restore metadata
    if [ -d "$SRC/wireguard-meta" ]; then
        mkdir -p "$WG_META"
        cp -vr "$SRC/wireguard-meta"/. "$WG_META"/
    fi

    # Restore nftables
    if [ -f "$SRC/nftables.rules" ]; then
        echo "Restoring nftables ruleset..."
        nft -f "$SRC/nftables.rules"
    fi

    chmod 600 "$WG_DIR"/*.conf
    [ -d "$WG_DIR/keys" ] && chmod 600 "$WG_DIR/keys"/*

    wg-quick up wg0

    echo "Restore complete."
}

list_backups() {
    echo "Backups in $DEST1:"
    ls -1 "$DEST1"
    echo ""
    echo "Backups in $DEST2:"
    ls -1 "$DEST2"
}

menu() {
    while true; do
        echo ""
        echo "WireGuard Backup & Restore"
        echo "--------------------------------"
        echo "1) Backup WireGuard"
        echo "2) Restore WireGuard"
        echo "3) List Backups"
        echo "4) Exit"
        echo -n "Choose an option: "
        read -r CHOICE

        case "$CHOICE" in
            1) backup_wireguard ;;
            2)
                echo -n "Enter path to backup folder: "
                read -r SRC
                restore_wireguard "$SRC"
                ;;
            3) list_backups ;;
            4) exit 0 ;;
            *) echo "Invalid option" ;;
        esac
    done
}

men
