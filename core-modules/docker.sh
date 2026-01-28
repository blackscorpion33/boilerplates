#!/bin/bash

# Source colors if available
[[ -f "$BASE/modules/common/colors.sh" ]] && source "$BASE/modules/common/colors.sh"

###############################################
# Helper: Install Docker app from services dir
###############################################
install_docker_app() {
    local app="$1"
    local svc_dir="$SERVICES_BASE/$app"
    local compose_file="$svc_dir/docker-compose.yml"

    echo ""
    echo -e "${CYAN}Installing ${BOLD}$app${RESET}${CYAN}...${RESET}"

    # Validate directory
    if [[ ! -d "$svc_dir" ]]; then
        echo -e "${RED}✗ Service directory not found:${RESET} $svc_dir"
        return 1
    fi

    # Validate compose file
    if [[ ! -f "$compose_file" ]]; then
        echo -e "${RED}✗ docker-compose.yml not found in:${RESET} $svc_dir"
        return 1
    fi

    # Detect if service is already installed
    if docker compose -f "$compose_file" ps --services --status running | grep -q .; then
        echo -e "${YELLOW}⟳ $app already installed and running. Skipping.${RESET}"
        return 0
    fi

    # Install service
    set +e
    ( cd "$svc_dir" && docker compose up -d )
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        echo -e "${GREEN}✓ $app installed successfully.${RESET}"
        INSTALLED_APPS+=("$app")
        return 0
    else
        echo -e "${RED}✗ Failed to install $app.${RESET}"
        return $status
    fi
}

###############################################
# Helper: Uninstall Docker app
###############################################
uninstall_docker_app() {
    local app="$1"
    local svc_dir="$SERVICES_BASE/$app"
    local compose_file="$svc_dir/docker-compose.yml"

    echo ""
    echo -e "${RED}Uninstalling ${BOLD}$app${RESET}${RED}...${RESET}"

    # Skip if directory missing
    if [[ ! -d "$svc_dir" ]]; then
        echo -e "${YELLOW}⟳ Skipping $app — service directory not found.${RESET}"
        return 0
    fi

    # Skip if compose file missing
    if [[ ! -f "$compose_file" ]]; then
        echo -e "${YELLOW}⟳ Skipping $app — docker-compose.yml missing.${RESET}"
        return 0
    fi

    # Skip if no containers exist
    if ! docker compose -f "$compose_file" ps --all | grep -q .; then
        echo -e "${YELLOW}⟳ $app is not installed. Skipping.${RESET}"
        return 0
    fi

    # Perform uninstall
    set +e
    ( cd "$svc_dir" && docker compose down )
    local status=$?
    set -e

    if [[ $status -ne 0 ]]; then
        echo -e "${RED}✗ Failed to stop/remove $app containers.${RESET}"
        return $status
    fi

    echo -e "${GREEN}✓ $app uninstalled successfully.${RESET}"
    UNINSTALLED_APPS+=("$app")
    return 0
}
