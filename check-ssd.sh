#!/usr/bin/env bash

set -u

########################################
# Refurbisher Drive Health Audit
# Linux Mint / Ubuntu / Debian
########################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

LOGFILE="/tmp/drive_audit_$(date +%Y%m%d_%H%M%S).log"

banner() {
    echo -e "${BLUE}${BOLD}"
    echo "=============================================================="
    echo "              REFURBISHER DRIVE HEALTH AUDIT"
    echo "=============================================================="
    echo -e "${NC}"
}

install_smartctl() {
    if ! command -v smartctl >/dev/null 2>&1; then
        echo -e "${YELLOW}[INFO]${NC} Installing smartmontools..."
        apt-get update -qq
        apt-get install -y smartmontools
    fi
}

find_drives() {
    lsblk -dn -o NAME,TYPE,TRAN \
        | awk '$2=="disk" && $3!="usb" {print "/dev/"$1}'
}

get_attr() {
    local attr="$1"
    local data="$2"

    echo "$data" | awk -v a="$attr" '
        $2==a {print $10}
    ' | head -n1
}

grade_drive() {

    local realloc="$1"
    local pending="$2"
    local offline="$3"
    local smart_status="$4"

    if [[ "$smart_status" != "PASSED" ]]; then
        echo "F"
        return
    fi

    if (( pending > 0 )); then
        echo "F"
        return
    fi

    if (( offline > 0 )); then
        echo "F"
        return
    fi

    if (( realloc > 50 )); then
        echo "F"
        return
    fi

    if (( realloc > 0 )); then
        echo "C"
        return
    fi

    echo "A"
}

grade_color() {

    case "$1" in
        A) echo -e "${GREEN}A${NC}" ;;
        B) echo -e "${CYAN}B${NC}" ;;
        C) echo -e "${YELLOW}C${NC}" ;;
        F) echo -e "${RED}F${NC}" ;;
        *) echo "?" ;;
    esac
}

print_drive_report() {

    local drive="$1"

    echo
    echo -e "${MAGENTA}${BOLD}Drive:${NC} $drive"

    local info
    info=$(smartctl -i "$drive" 2>/dev/null)

    local model
    model=$(echo "$info" | grep -E "Model|Device Model" | head -n1 | cut -d: -f2- | xargs)

    echo -e "${CYAN}Model:${NC} ${model:-Unknown}"

    local smart
    smart=$(smartctl -A "$drive" 2>/dev/null)

    local health
    health=$(smartctl -H "$drive" 2>/dev/null \
        | awk '/result|PASSED|FAILED/ {print $NF}' \
        | tail -n1)

    local realloc
    realloc=$(get_attr Reallocated_Sector_Ct "$smart")
    realloc=${realloc:-0}

    local pending
    pending=$(get_attr Current_Pending_Sector "$smart")
    pending=${pending:-0}

    local offline
    offline=$(get_attr Offline_Uncorrectable "$smart")
    offline=${offline:-0}

    local poh
    poh=$(get_attr Power_On_Hours "$smart")
    poh=${poh:-Unknown}

    local temp
    temp=$(echo "$smart" \
        | awk '/Temperature_Celsius/ {print $10}' \
        | head -n1)
    temp=${temp:-Unknown}

    local wear
    wear=$(echo "$smart" \
        | awk '
            /Wear_Leveling_Count/ ||
            /Media_Wearout_Indicator/ ||
            /SSD_Life_Left/ ||
            /Percent_Lifetime_Remain/ {
                print $10
                exit
            }')

    wear=${wear:-Unknown}

    local grade
    grade=$(grade_drive \
        "$realloc" \
        "$pending" \
        "$offline" \
        "$health")

    echo "--------------------------------------------------"
    printf "%-28s %s\n" "SMART Status:" "$health"
    printf "%-28s %s\n" "Power On Hours:" "$poh"
    printf "%-28s %s\n" "Temperature:" "$temp °C"
    printf "%-28s %s\n" "Reallocated Sectors:" "$realloc"
    printf "%-28s %s\n" "Pending Sectors:" "$pending"
    printf "%-28s %s\n" "Offline Uncorrectable:" "$offline"
    printf "%-28s %s\n" "Wear Indicator:" "$wear"
    printf "%-28s " "Refurbisher Grade:"
    grade_color "$grade"
    echo "--------------------------------------------------"

    {
        echo "Drive: $drive"
        echo "Model: $model"
        echo "SMART: $health"
        echo "POH: $poh"
        echo "Temp: $temp"
        echo "Reallocated: $realloc"
        echo "Pending: $pending"
        echo "OfflineUncorrectable: $offline"
        echo "Wear: $wear"
        echo "Grade: $grade"
        echo
    } >> "$LOGFILE"
}

########################################

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo."
    exit 1
fi

banner

install_smartctl

echo -e "${CYAN}[INFO]${NC} Scanning drives..."
echo

drives=$(find_drives)

if [[ -z "$drives" ]]; then
    echo -e "${RED}[ERROR]${NC} No drives detected."
    exit 1
fi

for d in $drives
do
    print_drive_report "$d"
done

echo
echo -e "${GREEN}[DONE]${NC} Audit complete."
echo -e "${CYAN}[LOG]${NC} Saved to: $LOGFILE"
