#!/bin/bash

echo "🔧 Changing MiloOverlay Hotkey"
echo ""
echo "Current hotkey options:"
echo "1. fn (default)"
echo "2. Option+Space" 
echo "3. Cmd+Space"
echo "4. Control+Space"
echo "5. Custom"
echo ""

CONFIG_FILE="$HOME/.openclaw/milo-overlay.json"

read -p "Choose hotkey (1-5): " choice

case $choice in
    1) HOTKEY="fn" ;;
    2) HOTKEY="Option+Space" ;;
    3) HOTKEY="Cmd+Space" ;;
    4) HOTKEY="Control+Space" ;;
    5) 
        read -p "Enter custom hotkey (e.g., 'F1', 'Control+R'): " HOTKEY
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

echo "🔧 Setting hotkey to: $HOTKEY"

# Update config
jq --arg hotkey "$HOTKEY" '.hotkey = $hotkey' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

echo "✅ Hotkey changed! Restart MiloOverlay for changes to take effect."
echo ""
echo "Current config:"
jq . "$CONFIG_FILE"