#!/bin/bash
# Check for required tools
dependencies=("aircrack-ng" "macchanger" "iw" "iwconfig" "xterm")
for tool in "${dependencies[@]}"; do
    if ! command -v $tool &> /dev/null; then
        echo "[!] Installing $tool..."
        apt-get update && apt-get install -y $tool
    fi
    if  command -v $tool &> /dev/null; then
        echo "[ $tool is installed :) ] "
    fi

done

#https://github.com/RMNO21