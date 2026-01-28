#!/bin/bash

# Source colors if available
[[ -f "$BASE/modules/common/colors.sh" ]] && source "$BASE/modules/common/colors.sh"

###############################################
# Bare-metal: Pi-hole
###############################################
install_pihole() {
    echo -e "${CYAN}Installing Pi-hole (bare-metal)...${RESET}"

    if command -v pihole >/dev/null 2>&1; then
        echo -e "${YELLOW}⟳ Pi-hole already installed. Skipping.${RESET}"
        INSTALLED_APPS+=("pihole")
        return 0
    fi

    curl -sSL https://install.pi-hole.net | bash
    local status=$?

    if [[ $status -eq 0 ]]; then
        echo -e "${GREEN}✓ Pi-hole installed successfully.${RESET}"
        INSTALLED_APPS+=("pihole")
    else
        echo -e "${RED}✗ Pi-hole installation failed.${RESET}"
    fi
}

uninstall_pihole() {
    echo -e "${RED}Uninstalling Pi-hole...${RESET}"

    if ! command -v pihole >/dev/null 2>&1; then
        echo -e "${YELLOW}⟳ Pi-hole not installed.${RESET}"
        return 0
    fi

    pihole uninstall || true
    echo -e "${GREEN}✓ Pi-hole removed.${RESET}"
    UNINSTALLED_APPS+=("pihole")
}

###############################################
# Bare-metal: Unbound
###############################################
install_unbound() {
    echo -e "${CYAN}Installing Unbound (bare-metal)...${RESET}"

    if systemctl is-active --quiet unbound; then
        echo -e "${YELLOW}⟳ Unbound already running. Skipping.${RESET}"
        INSTALLED_APPS+=("unbound")
        return 0
    fi

    apt update
    apt install -y unbound

    cat <<EOF >/etc/unbound/unbound.conf.d/pi-hole.conf
server:
    verbosity: 0
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: yes
    edns-buffer-size: 1232
    prefetch: yes
    num-threads: 1
EOF

    systemctl enable unbound
    systemctl restart unbound

    echo -e "${GREEN}✓ Unbound installed and configured.${RESET}"
    INSTALLED_APPS+=("unbound")
}

uninstall_unbound() {
    echo -e "${RED}Uninstalling Unbound...${RESET}"

    if ! systemctl list-unit-files | grep -q '^unbound\.service'; then
        echo -e "${YELLOW}⟳ Unbound not installed.${RESET}"
        return 0
    fi

    systemctl stop unbound || true
    apt purge -y unbound || true

    echo -e "${GREEN}✓ Unbound removed.${RESET}"
    UNINSTALLED_APPS+=("unbound")
}

#################################
#            Yams
#################################
run_external_script() {
    local script="$1"
    local target_dir="$2"

    echo ""
    echo -e "${CYAN}Running external installer:${RESET} $script"

    # Create install directory
    if [[ -n "$target_dir" ]]; then
        mkdir -p "$target_dir"
    fi

    # Validate script exists
    if [[ ! -f "$script" ]]; then
        echo -e "${RED}✗ Script not found:${RESET} $script"
        return 1
    fi

    chmod +x "$script"

    # Run safely without letting it kill the bootstrap
    set +e
    (
        cd "$(dirname "$script")" || exit 1
        "./$(basename "$script")"
    )
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        echo -e "${GREEN}✓ External script completed successfully.${RESET}"
    else
        echo -e "${RED}✗ External script failed with exit code $status.${RESET}"
    fi

    return $status
}

###############################################
#                Fail2ban
###############################################

install_fail2ban() {
    echo -e "${CYAN}Installing Fail2Ban...${RESET}"

    # Skip if already installed
    if command -v fail2ban-server >/dev/null 2>&1; then
        echo -e "${YELLOW}Fail2Ban already installed. Skipping.${RESET}"
    else
        apt update -y
        apt install -y fail2ban
    fi

# 1. Create jail.local if missing
if [[ ! -f /etc/fail2ban/jail.local ]]; then
    cat <<EOF >/etc/fail2ban/jail.local
[sshd]
enabled = true

[wireguard]
enabled = true
filter = wireguard
logpath = /var/log/syslog
maxretry = 5
findtime = 10m
bantime = 1h
backend = systemd

EOF
fi



# 2. WireGuard filter
if [[ ! -f /etc/fail2ban/filter.d/wireguard.conf ]]; then
    cat <<EOF >/etc/fail2ban/filter.d/wireguard.conf
[Definition]
failregex = .*Handshake for peer .* did not complete.*
ignoreregex =
EOF
fi


    ###############################################
    # 4. Restart Fail2Ban
    ###############################################
    systemctl enable fail2ban
    systemctl restart fail2ban

    echo -e "${GREEN}Fail2Ban installed and configured.${RESET}"
}
