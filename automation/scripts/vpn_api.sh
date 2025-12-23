#!/bin/bash
# Backend API Wrapper for WG-Easy
# Usage: ./vpn_api.sh <PASSWORD> <ACTION> [ARGS...]

PASS="$1"
ACTION="$2"
ARG1="$3"

API="http://172.20.0.6:51821/api"
COOKIE="/tmp/wg_cookie"

# Ensure jq is installed
if ! command -v jq &> /dev/null;
    then
    sudo apt-get update -qq && sudo apt-get install -y -qq jq
fi

# 1. Login
AUTH_RESP=$(curl -s -c "$COOKIE" -H "Content-Type: application/json" -d "{\"password\":\"$PASS\"}" "$API/session")

if [[ "$AUTH_RESP" == *"Unauthorized"* ]]; then
    echo "ERROR: Invalid Password"
    exit 1
fi

# 2. Handle Actions
case "$ACTION" in
    "list")
        # Returns: ID | NAME | IP | ENABLED
        curl -s -b "$COOKIE" "$API/wireguard/client" | jq -r '.[] | "\(.id) | \(.name) | \(.address) | \(.enabled)"'
        ;;
    
    "create")
        # ARG1 = Name
        if [ -z "$ARG1" ]; then echo "ERROR: Name required"; exit 1; fi
        curl -s -b "$COOKIE" -H "Content-Type: application/json" -d "{\"name\":\"$ARG1\"}" "$API/wireguard/client" > /dev/null
        echo "OK"
        ;;
    
    "delete")
        # ARG1 = ID
        if [ -z "$ARG1" ]; then echo "ERROR: ID required"; exit 1; fi
        curl -s -b "$COOKIE" -X DELETE "$API/wireguard/client/$ARG1" > /dev/null
        echo "OK"
        ;;
        
    "get")
        # ARG1 = ID
        if [ -z "$ARG1" ]; then echo "ERROR: ID required"; exit 1; fi
        # Get Config
        curl -s -b "$COOKIE" "$API/wireguard/client/$ARG1/configuration"
        ;;

    "get-by-name")
        # ARG1 = Name
        if [ -z "$ARG1" ]; then echo "ERROR: Name required"; exit 1; fi
        ID=$(curl -s -b "$COOKIE" "$API/wireguard/client" | jq -r ".[] | select(.name==\"$ARG1\") | .id")
        if [ -z "$ID" ]; then
            echo "ERROR: User not found"
            exit 1
        fi
        curl -s -b "$COOKIE" "$API/wireguard/client/$ID/configuration"
        ;;

    "qr")
        # ARG1 = ID
        if [ -z "$ARG1" ]; then echo "ERROR: ID required"; exit 1; fi
        # Get QR (SVG) - Not easy to render in terminal, prefer Config text
        echo "ERROR: QR not supported in CLI, use 'get' for config text."
        ;;
        
    *)
        echo "Unknown command"
        ;;
esac

# Cleanup
rm -f "$COOKIE"
