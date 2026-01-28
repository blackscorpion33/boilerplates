# Source colors if available
[[ -f "$BASE/modules/common/colors.sh" ]] && source "$BASE/modules/common/colors.sh"

###############################################
# WireGuard Module (Function‑Only)
# Don’s clean, final version
###############################################
echo "DEBUG (module load): CLIENT_DIR is '$CLIENT_DIR'"

# Detect server IP
wg_detect_server_ip() {
    curl -s https://api.ipify.org
}

# Detect outbound interface
wg_detect_iface() {
    ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}'
}

# Detect if server is installed
wg_is_installed() {
    [[ -f "$WG_DIR/wg0.conf" ]]
}

###############################################
# Install WireGuard Server
###############################################
wg_install_server() {

    if wg_is_installed; then
        echo -e "${YELLOW}⟳ WireGuard server already installed. Skipping.${RESET}"
        return
    fi

    echo -e "${CYAN}Installing WireGuard server...${RESET}"

    SERVER_IP=$(wg_detect_server_ip)
    WG_IFACE=$(wg_detect_iface)

    SERVER_PRIV=$(wg genkey)
    SERVER_PUB=$(echo "$SERVER_PRIV" | wg pubkey)

    echo "$SERVER_PRIV" > "$BASE_WG/privatekey"
    echo "$SERVER_PUB"  > "$BASE_WG/publickey"
    chmod 600 "$BASE_WG/privatekey"

    cat <<EOF > "$WG_DIR/wg0.conf"
[Interface]
Address = 10.10.2.1/24
ListenPort = 55107
PrivateKey = $SERVER_PRIV

PostUp   = iptables-legacy -t nat -A POSTROUTING -o ${WG_IFACE} -j MASQUERADE
PostDown = iptables-legacy -t nat -D POSTROUTING -o ${WG_IFACE} -j MASQUERADE
EOF

    # Baseline client
    CLIENT_PRIV=$(wg genkey)
    CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)
    CLIENT_IP="10.10.2.2"

    echo "$CLIENT_PRIV" > "$CLIENT_DIR/client-1.key"
    echo "$CLIENT_PUB"  > "$CLIENT_DIR/client-1.pub"
    chmod 600 "$CLIENT_DIR/client-1.key"

    cat <<EOF > "$CLIENT_DIR/client-1.conf"
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP/32
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $SERVER_IP:55107
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    cat <<EOF >> "$WG_DIR/wg0.conf"

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = $CLIENT_IP/32
EOF

    systemctl enable wg-quick@wg0
    systemctl restart wg-quick@wg0

    echo -e "${GREEN}WireGuard server installed with baseline client-1.${RESET}"
}

###############################################
# Install WireGuard Client
###############################################
wg_install_client() {

    if [[ -f "$CLIENT_DIR/client.conf" ]]; then
        echo -e "${YELLOW}⟳ WireGuard client already installed. Skipping.${RESET}"
        return
    fi

    if [[ ! -f "$BASE_WG/publickey" ]]; then
        echo -e "${RED}✗ WireGuard server is not installed.${RESET}"
        echo -e "${YELLOW}Install the server first (option 1).${RESET}"
        return 1
    fi

    echo -e "${CYAN}Installing WireGuard client...${RESET}"

    SERVER_IP=$(wg_detect_server_ip)
    SERVER_PUB=$(cat "$BASE_WG/publickey")

    CLIENT_PRIV=$(wg genkey)
    CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)

    echo "$CLIENT_PRIV" > "$CLIENT_DIR/client.conf.key"
    echo "$CLIENT_PUB"  > "$CLIENT_DIR/client.conf.pub"
    chmod 600 "$CLIENT_DIR/client.conf.key"

    cat <<EOF > "$CLIENT_DIR/client.conf"
[Interface]
PrivateKey = $CLIENT_PRIV
Address = 10.10.2.99/32
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $SERVER_IP:55107
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    echo -e "${GREEN}WireGuard client config created.${RESET}"
}

###############################################
# Add New Client
###############################################
wg_add_client() {

    if [[ ! -f "$BASE_WG/publickey" ]]; then
        echo -e "${RED}✗ WireGuard server is not installed.${RESET}"
        return
    fi

    SERVER_IP=$(wg_detect_server_ip)
    SERVER_PUB=$(cat "$BASE_WG/publickey")

    echo -e "${YELLOW}Enter client name (leave blank for auto):${RESET}"
    read -r CUSTOM_NAME

    LAST_NUM=0
    shopt -s nullglob
    for f in "$CLIENT_DIR"/client-*.conf; do
        NUM=$(basename "$f" | sed 's/client-\([0-9]*\)\.conf/\1/')
        (( NUM > LAST_NUM )) && LAST_NUM=$NUM
    done
    shopt -u nullglob

    if [[ -n "$CUSTOM_NAME" ]]; then
        CLIENT_NAME="$CUSTOM_NAME"
    else
        CLIENT_NAME="client-$((LAST_NUM + 1))"
    fi

    CLIENT_IP="10.10.2.$((LAST_NUM + 2))"

    CLIENT_PRIV=$(wg genkey)
    CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)

    echo "$CLIENT_PRIV" > "$CLIENT_DIR/$CLIENT_NAME.key"
    echo "$CLIENT_PUB"  > "$CLIENT_DIR/$CLIENT_NAME.pub"
    chmod 600 "$CLIENT_DIR/$CLIENT_NAME.key"

    cat <<EOF > "$CLIENT_DIR/$CLIENT_NAME.conf"
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP/32
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $SERVER_IP:55107
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    cat <<EOF >> "$WG_DIR/wg0.conf"

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = $CLIENT_IP/32
EOF

    systemctl restart wg-quick@wg0

    echo -e "${GREEN}Client added:${RESET} ${CYAN}$CLIENT_NAME${RESET}"
    echo -e "${YELLOW}Config:${RESET} $CLIENT_DIR/$CLIENT_NAME.conf"
}

###############################################
# List Clients
###############################################
wg_list_clients() {
    echo -e "${BOLD}=== Existing WireGuard Clients ===${RESET}"
    shopt -s nullglob
    for f in "$CLIENT_DIR"/*.conf; do
        echo -e " - ${CYAN}$(basename "$f" .conf)${RESET}"
    done
    shopt -u nullglob
}

###############################################
# Show QR Code
###############################################
wg_qr() {
    read -r -p "$(echo -e "${YELLOW}Enter client name:${RESET} ")" client
    qrencode -t ansiutf8 < "$CLIENT_DIR/$client.conf"
}

###############################################
# Download Client Config
###############################################
wg_download() {
    read -r -p "$(echo -e "${YELLOW}Enter client name:${RESET} ")" client
    cp "$CLIENT_DIR/$client.conf" "$DOWNLOAD_DIR/$client.conf"
    echo -e "${GREEN}Saved to:${RESET} $DOWNLOAD_DIR/$client.conf"
}

###############################################
# Reset WireGuard
###############################################
wg_reset() {
    echo -e "${RED}${BOLD}⚠ WARNING: This will completely reset WireGuard.${RESET}"
    echo -e "${YELLOW}All keys, configs, clients, and wg0.conf will be deleted.${RESET}"
    echo -e "${YELLOW}This action cannot be undone.${RESET}"
    echo ""

    read -r -p "$(echo -e "${CYAN}Type YES to confirm reset:${RESET} ")" confirm

    if [[ "${confirm^^}" != "YES" ]]; then
        echo -e "${YELLOW}Reset cancelled.${RESET}"
        return
    fi

    systemctl stop wg-quick@wg0 2>/dev/null || true
    rm -f "$WG_DIR/wg0.conf"
    rm -rf "$BASE_WG"

    echo -e "${GREEN}✓ WireGuard has been fully reset.${RESET}"
    echo -e "${YELLOW}You may now reinstall the server from the WireGuard menu.${RESET}"
}
###############################################
# WireGuard Health Check
###############################################
wg_health() {
    echo -e "${CYAN}${BOLD}WireGuard Health Check${RESET}"

    # Check server config
    if [[ -f "$WG_DIR/wg0.conf" ]]; then
        echo -e "${GREEN}✓ Server config exists:${RESET} $WG_DIR/wg0.conf"
    else
        echo -e "${RED}✗ Server config missing:${RESET} $WG_DIR/wg0.conf"
    fi

    # Check key files
    if [[ -f "$BASE_WG/privatekey" ]]; then
        echo -e "${GREEN}✓ Server private key exists${RESET}"
    else
        echo -e "${RED}✗ Missing server private key${RESET}"
    fi

    if [[ -f "$BASE_WG/publickey" ]]; then
        echo -e "${GREEN}✓ Server public key exists${RESET}"
    else
        echo -e "${RED}✗ Missing server public key${RESET}"
    fi

    # Check client directory
    if compgen -G "$CLIENT_DIR/*.conf" > /dev/null; then
        echo -e "${GREEN}✓ Clients found in:${RESET} $CLIENT_DIR"
    else
        echo -e "${YELLOW}No clients found in:${RESET} $CLIENT_DIR"
    fi

    # Check service status
    if systemctl is-active --quiet wg-quick@wg0; then
        echo -e "${GREEN}✓ wg-quick@wg0 is running${RESET}"
    else
        echo -e "${RED}✗ wg-quick@wg0 is NOT running${RESET}"
    fi

    echo ""
}
###############################################
# Show Client Config
###############################################
wg_show_client() {
    echo -e "${YELLOW}Enter client name (example: client-1):${RESET}"
    read -r client

    local file="$CLIENT_DIR/$client.conf"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}✗ Client config not found:${RESET} $file"
        return
    fi

    echo -e "${CYAN}${BOLD}=== $client.conf ===${RESET}"
    cat "$file"
    echo -e "${CYAN}${BOLD}====================${RESET}"
}
###############################################
# WireGuard Menu (Looping)
###############################################
wireguard_menu() {
    while true; do
        clear
        echo -e "${BOLD}${BLUE}===============================${RESET}"
        echo -e "${BOLD}${BLUE}      WireGuard Manager       ${RESET}"
        echo -e "${BOLD}${BLUE}===============================${RESET}"
        echo -e "${CYAN}1)${RESET} Install WireGuard SERVER"
        echo -e "${CYAN}2)${RESET} Install WireGuard CLIENT"
        echo -e "${CYAN}3)${RESET} Add new WireGuard client"
        echo -e "${CYAN}4)${RESET} Show existing clients"
        echo -e "${CYAN}5)${RESET} Generate QR for a client"
        echo -e "${CYAN}6)${RESET} Download client config"
        echo -e "${CYAN}7)${RESET} Reset WireGuard (wipe all configs)"
        echo -e "${CYAN}8)${RESET} WireGuard Health Check"
        echo -e "${CYAN}9)${RESET} Show client config"
        echo -e "${CYAN}10)${RESET} Back to main menu"
        echo -e "${BOLD}${BLUE}===============================${RESET}"
        read -r WG_CHOICE

        case "$WG_CHOICE" in
            1) wg_install_server ;;
            2) wg_install_client ;;
            3) wg_add_client ;;
            4) wg_list_clients ;;
            5) wg_qr ;;
            6) wg_download ;;
            7) wg_reset ;;
            8) wg_health ;;
            9) wg_show_client ;;
            10) break ;;
            *) echo -e "${RED}Invalid choice.${RESET}" ;;
        esac

        echo ""
        read -rp "$(echo -e "${YELLOW}Press ENTER to return to WireGuard menu...${RESET}")"
    done
}
