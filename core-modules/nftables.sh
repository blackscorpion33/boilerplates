#!/usr/bin/env bash
# ============================
# nftables Installer + Helpers
# ============================

# Source colors if available
[[ -f "$BASE/modules/common/colors.sh" ]] && source "$BASE/modules/common/colors.sh"

###############################################
# Auto‑elevate if not root
###############################################
if [[ $EUID -ne 0 ]]; then
    echo "This module must be run as root (sudo)."
    return 1 2>/dev/null || exit 1
fi

NFT_DIR="/etc/nftables"
NFT_OPEN="$NFT_DIR/nftables-open.conf"
NFT_RESTRICTED="$NFT_DIR/nft-restricted.conf"
NFT_ACTIVE="$NFT_DIR/ruleset.nft"
NFT_LOADER="/etc/nftables.conf"

fw_install_rulesets() {
    echo -e "${CYAN}Installing nftables rulesets...${RESET}"
    apt-get update -y && apt-get install -y nftables
    mkdir -p "$NFT_DIR"

    # --- OPEN ruleset ---
    cat > "$NFT_OPEN" << 'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
    chain input { type filter hook input priority 0; policy accept; }
    chain forward {
        type filter hook forward priority -10; policy accept;
        tcp flags & (syn | rst) == syn tcp option maxseg size set rt mtu
    }
    chain output { type filter hook output priority 0; policy accept; }
}
table ip nat {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        ip saddr 10.10.2.0/24 oifname "enp2s0" masquerade
    }
}
EOF

    # --- RESTRICTED ruleset (FIXED) ---
    cat > "$NFT_RESTRICTED" << 'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # 1. Allow existing connections (Keep your SSH alive!)
        ct state established,related accept
        iifname "lo" accept

        # 2. Allow Docker & Internal Bridges
        iifname "docker0" accept
        iifname "br-*" accept

        # 3. Open Ports (Port 8086 added for Pi-hole)
        tcp dport { 22, 80, 443, 222, 3014, 3020, 3030, 8000, 8018, 8082, 8086, 8156, 9000, 9055, 9097, 9100, 9443, 9444, 61208, 61209 } accept

        # 4. DNS & VPN
        udp dport { 53, 55107 } accept
        tcp dport 53 accept
        ip saddr { 10.5.5.0/24, 10.10.2.0/24 } accept
    }

    chain forward {
        type filter hook forward priority 0; policy accept;
        tcp flags & (syn | rst) == syn tcp option maxseg size set rt mtu
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}

table ip nat {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname "enp2s0" masquerade
    }
}

EOF

    # --- Loader file ---
    cat > "$NFT_LOADER" << EOF
#!/usr/sbin/nft -f
include "$NFT_ACTIVE"
EOF

    chmod +x "$NFT_LOADER"
    ln -sf "$NFT_OPEN" "$NFT_ACTIVE"
    systemctl enable nftables
    systemctl restart nftables
    echo -e "${GREEN}nftables rulesets installed.${RESET}"
}

fw_nft_apply() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1
    nft -f "$file"
}

fw_open() {
    echo -e "${CYAN}Switching to OPEN firewall mode...${RESET}"
    ln -sf "$NFT_OPEN" "$NFT_ACTIVE"
    fw_nft_apply "$NFT_LOADER"
    systemctl restart docker
    echo -e "${GREEN}Firewall is now in OPEN mode.${RESET}"
}

fw_wg_restricted() {
    echo -e "${CYAN}Applying WireGuard-restricted firewall (No Timer)...${RESET}"

    # Switch the symbolic link to the restricted config
    ln -sf "$NFT_RESTRICTED" "$NFT_ACTIVE"

    # Apply the rules
    if fw_nft_apply "$NFT_LOADER"; then
        systemctl restart docker
        echo -e "${GREEN}Restricted mode active.${RESET}"
    else
        echo -e "${RED}Error applying rules. Reverting to Open mode...${RESET}"
        fw_open
    fi
}

fw_show() {
    echo -e "${BOLD}${BLUE}=== Active nftables Ruleset ===${RESET}"
    nft list ruleset
}

fw_status() {
    echo -e "${BOLD}${BLUE}=== Firewall Status ===${RESET}"
    [[ "$(readlink -f "$NFT_ACTIVE")" = "$NFT_RESTRICTED" ]] && echo -e "${GREEN}Mode: RESTRICTED${RESET}" || echo -e "${YELLOW}Mode: OPEN${RESET}"
}

firewall_menu() {
    while true; do
        clear
        echo -e "${BOLD}${BLUE}==============================="
        echo -e "        Firewall Manager        "
        echo -e "===============================${RESET}"
        echo -e "${CYAN}1)${RESET} Open firewall (safe mode)"
        echo -e "${CYAN}2)${RESET} Apply WireGuard-restricted firewall"
        echo -e "${CYAN}3)${RESET} Show active firewall rules"
        echo -e "${CYAN}4)${RESET} Firewall status"
        echo -e "${CYAN}5)${RESET} Install/Repair nftables rulesets"
        echo -e "${CYAN}6)${RESET} Back to main menu"
        echo -e "${BOLD}${BLUE}===============================${RESET}"

        read -r FW_CHOICE
        case "$FW_CHOICE" in
            1) fw_open ;;
            2) fw_wg_restricted ;;
            3) fw_show ;;
            4) fw_status ;;
            5) fw_install_rulesets ;;
            6) break ;;
            *) echo -e "${RED}Invalid choice.${RESET}" ;;
        esac

        if [[ "$FW_CHOICE" != "6" ]]; then
            echo -e "\n${YELLOW}Press any key to return to the Firewall Menu...${RESET}"
            read -n 1 -s -r
        fi
    done
}
