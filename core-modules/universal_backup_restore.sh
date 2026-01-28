#!/bin/bash

# Source colors if available
[[ -f "$BASE/modules/common/colors.sh" ]] && source "$BASE/modules/common/colors.sh"

###############################################
#  HEADER + STATUS FUNCTIONS
###############################################
header() {
    local text="$1"
    echo -e "\n${BOLD}${CYAN}========================================${RESET}"
    echo -e "${BOLD}${WHITE}$text${RESET}"
    echo -e "${BOLD}${CYAN}========================================${RESET}\n"
}

ok()    { echo -e "${GREEN}[OK]${RESET} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET} $1"; }
err()   { echo -e "${RED}[ERROR]${RESET} $1"; }
info()  { echo -e "${CYAN}[INFO]${RESET} $1"; }

pause() { read -rp "Press ENTER to continue..."; }

if [[ "$1" == "--auto" ]]; then
    # Skip the menu and just run perform_backup for all services
    for svc in "${SERVICES[@]}"; do
        perform_backup "$svc"
    done
    exit 0
fi

###############################################
#  PATHS
###############################################
SERVICES_DIR="/home/docker/services"
BACKUP_ROOT="/mnt/nas/universal_backup"
BACKUP_ROOT_2="/mnt/remote_backup"  # This now points to your Debian 12 server

timestamp() { date +"%Y-%m-%d_%H-%M-%S"; }

###############################################
#  DETECT SERVICES
###############################################
detect_services() {
    mapfile -t SERVICES < <(find "$SERVICES_DIR" -maxdepth 1 -mindepth 1 -type d | sort)
}

###############################################
#  SERVICE SELECTION
###############################################
select_service() {
    detect_services
    header "SELECT A SERVICE" >&2

    local i=1
    for svc in "${SERVICES[@]}"; do
        local name=$(basename "$svc")
        if [[ -f "$svc/backup.template" ]]; then
            echo -e "  ${BOLD}${WHITE}$i)${RESET} $name ${GREEN}[template found]${RESET}" >&2
        else
            echo -e "  ${BOLD}${WHITE}$i)${RESET} $name ${YELLOW}[AUTO-SYNC MODE]${RESET}" >&2
        fi
        ((i++))
    done

    echo -e "\n  ${BOLD}${MAGENTA}A)${RESET} Backup ALL services" >&2
    echo -e "  ${BOLD}${RED}M)${RESET} Return to Main Menu" >&2
    echo "" >&2
    read -rp "> " choice

    if [[ "$choice" =~ ^[Mm]$ ]]; then
        echo "MENU"
        return
    fi

    if [[ "$choice" =~ ^[Aa]$ ]]; then
        echo "ALL"
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        err "Invalid choice" >&2
        select_service
        return
    fi

    local index=$((choice - 1))
    echo "${SERVICES[$index]}"
}

###############################################
#  BACKUP LOGIC
###############################################
perform_backup() {
    local svc_path="$1"
    [[ "$svc_path" == "MENU" || -z "$svc_path" ]] && return

    local svc_name=$(basename "$svc_path")
    header "BACKING UP: $svc_name"

    # Reset variables for each run
    CONFIG_DIR=""
    COMPOSE_FILE=""
    ENV_FILE=""
    EXTRA_PATHS=()

    local dest="$BACKUP_ROOT/$svc_name/$(timestamp)"
    mkdir -p "$dest"

    if [[ -f "$svc_path/backup.template" ]]; then
        info "Template found. Selective backup starting..."
        source "$svc_path/backup.template"

        # Selective Copy Logic
        [[ -n "$CONFIG_DIR" && -d "$svc_path/$CONFIG_DIR" ]] && cp -r "$svc_path/$CONFIG_DIR" "$dest/" && ok "Config copied"
        [[ -n "$COMPOSE_FILE" && -f "$svc_path/$COMPOSE_FILE" ]] && cp "$svc_path/$COMPOSE_FILE" "$dest/" && ok "Compose copied"
#        [[ -n "$ENV_FILE" && -f "$svc_path/$ENV_FILE" ]] && cp "$svc_path/$ENV_FILE" "$dest/" && ok "Env copied"
        # --- AUTOMATIC ENV BACKUP & RENAME ---
        # We look for a .env first, then fall back to the template variable
        local source_env=""
    if [[ -f "$svc_path/.env" ]]; then
        source_env="$svc_path/.env"
    elif [[ -n "$ENV_FILE" && -f "$svc_path/$ENV_FILE" ]]; then
        source_env="$svc_path/$ENV_FILE"
    fi

    if [[ -n "$source_env" ]]; then
        cp "$source_env" "$dest/${svc_name}.env"
        ok "Environment file saved as ${svc_name}.env"
    else
        warn "No .env found (skipped)"
    fi
#        for item in "${EXTRA_PATHS[@]}"; do
#            [[ -e "$svc_path/$item" ]] && cp -r "$svc_path/$item" "$dest/" && ok "Extra path copied: $item"
#        done

    # --- EXTRA PATHS LOGIC ---
    if [[ -n "$EXTRA_PATHS" ]]; then
        info "Copying extra paths..."
        for path in "${EXTRA_PATHS[@]}"; do
            if [[ -e "$svc_path/$path" ]]; then
                # We add sudo here to bypass the acme.json lock
                sudo cp -a "$svc_path/$path" "$dest/"
                ok "Copied: $path"
            else
                warn "Extra path not found: $path"
            fi
        done
    fi

   else
        warn "No template! Performing full folder sync..."
        # Copy everything inside the directory to the destination
        cp -a "$svc_path/." "$dest/"
        ok "Full directory sync complete"
    fi

    ok "Backup saved to: $dest"

# --- SECONDARY SAFETY NET ---
    # This triggers after the primary backup to $dest is finished
    if [[ -d "$BACKUP_ROOT_2" ]]; then
        info "Syncing to secondary safety net (Debian 12)..."

        # We define the destination folder on the second server
        # $(basename "$dest") ensures the timestamped folder name is identical
        local dest2="$BACKUP_ROOT_2/$svc_name/$(basename "$dest")"

        # Create the directory on the remote mount
        mkdir -p "$dest2"

        # Copy from the finished primary backup to the secondary
        # This is often faster than reading from the source disk again
        cp -a "$dest/." "$dest2/"

        if [ $? -eq 0 ]; then
            ok "Secondary backup complete → $dest2"
        else
            err "Secondary backup failed during copy"
        fi
    else
        warn "Secondary destination ($BACKUP_ROOT_2) not mounted. Skipping."
    fi

}

backup_all() {
    header "BACKING UP ALL SERVICES"
    detect_services
    for svc in "${SERVICES[@]}"; do
        perform_backup "$svc"
    done
}

###############################################
#  RESTORE LOGIC
###############################################
select_restore_app() {
    mapfile -t APPS < <(find "$BACKUP_ROOT" -maxdepth 1 -mindepth 1 -type d | sort)
    header "SELECT SERVICE TO RESTORE" >&2

    local i=1
    for app in "${APPS[@]}"; do
        echo -e "  ${BOLD}${WHITE}$i)${RESET} $(basename "$app")" >&2
        ((i++))
    done
    echo -e "\n  ${BOLD}${RED}M)${RESET} Return to Main Menu" >&2

    read -rp "> " choice
    [[ "$choice" =~ ^[Mm]$ ]] && echo "MENU" && return

    local index=$((choice - 1))
    echo "${APPS[$index]}"
}

select_restore_timestamp() {
    local app_path="$1"
    [[ "$app_path" == "MENU" ]] && echo "MENU" && return

    mapfile -t TS < <(find "$app_path" -maxdepth 1 -mindepth 1 -type d | sort)
    header "SELECT TIMESTAMP" >&2

    local i=1
    for t in "${TS[@]}"; do
        echo -e "  ${BOLD}${WHITE}$i)${RESET} $(basename "$t")" >&2
        ((i++))
    done
    read -rp "> " choice
    local index=$((choice - 1))
    echo "${TS[$index]}"
}

perform_restore() {
    local app_path="$1"
    local ts_path="$2"
    [[ "$app_path" == "MENU" || "$ts_path" == "MENU" || -z "$ts_path" ]] && return

    local svc_name=$(basename "$app_path")

    # --- NEW: CHOOSE DESTINATION ---
    header "RESTORE DESTINATION"
    echo -e "  ${BOLD}${WHITE}1)${RESET} Original Location ($SERVICES_DIR/$svc_name)"
    echo -e "  ${BOLD}${WHITE}2)${RESET} Test Location ($SERVICES_DIR/${svc_name}_test)"
    read -rp "> " loc_choice

    if [[ "$loc_choice" == "2" ]]; then
        local svc_target="$SERVICES_DIR/${svc_name}_test"
    else
        local svc_target="$SERVICES_DIR/$svc_name"
    fi
    # -------------------------------

    info "Restoring to: $svc_target"

    # Ensure the directory exists
    sudo mkdir -p "$svc_target"

    # Perform the copy
    sudo cp -av "$ts_path/." "$svc_target/"

# --- RESTORE: ENVIRONMENT FILE RENAME ---
    if [[ -f "$svc_target/${svc_name}.env" ]]; then
        info "Standardizing environment file..."
        sudo mv "$svc_target/${svc_name}.env" "$svc_target/.env"
    fi

    # Ensure it's hidden and protected
    if [[ -f "$svc_target/.env" ]]; then
        sudo chmod 600 "$svc_target/.env"
        ok "Environment file restored as .env (Protected)"
    fi
    # --- TRAEFIK HARDENING ---
    if [[ "$svc_name" == "traefik" ]]; then
        local acme_file=$(find "$svc_target" -name "acme.json")
        if [[ -f "$acme_file" ]]; then
            sudo chown root:root "$acme_file"
            sudo chmod 600 "$acme_file"
            ok "Hardened acme.json permissions."
        fi
    fi

    ok "Restore complete for $svc_name"
}
# ... (all your functions go above here) ...

# --- EXECUTION LOGIC ---

if [[ "$1" == "--auto" ]]; then
    # This runs when Cron triggers it
    header "STARTING AUTOMATED BI-WEEKLY BACKUP"
    for svc in "${SERVICES[@]}"; do
        # Dynamically find the path for each service
        service_path="$SERVICES_DIR/$svc"
        if [ -d "$service_path" ]; then
            perform_backup "$service_path"
        fi
    done
    
    cleanup_old_backups # Delete stuff older than 60 days
    ok "Automated task finished."
    exit 0
else
    # This runs when you launch it manually
    show_menu
fi
###############################################
#  MAIN MENU
###############################################
main_menu() {
    clear
    header "UNIVERSAL BACKUP ENGINE"

    echo -e "${BOLD}${WHITE}1)${RESET} Backup a service"
    echo -e "${BOLD}${WHITE}2)${RESET} Restore a service"
    echo -e "${BOLD}${WHITE}3)${RESET} Backup ALL services"
    echo -e "${BOLD}${WHITE}4)${RESET} Exit"
    echo ""

    read -rp "> " choice

    case "$choice" in
        1)
            svc=$(select_service)
            if [[ "$svc" == "ALL" ]]; then
                backup_all
            elif [[ "$svc" != "MENU" ]]; then
                perform_backup "$svc"
            fi
            pause
            ;;
        2)
            app=$(select_restore_app)
            if [[ "$app" != "MENU" ]]; then
                ts=$(select_restore_timestamp "$app")
                perform_restore "$app" "$ts"
            fi
            pause
            ;;
        3)
            backup_all
            pause
            ;;
        4)
            exit 0
            ;;
        *)
            err "Invalid choice"
            pause
            ;;
    esac
    main_menu
}

main_menu
