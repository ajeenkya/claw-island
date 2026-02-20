#!/bin/bash

# MiloOverlay Voice Changer
# Quick script to change TTS voice

CONFIG_FILE="$HOME/.openclaw/milo-overlay.json"

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    exit 1
fi

# Popular voice options
echo "🎤 Available Voice Options:"
echo ""
echo "English Voices:"
echo "1. Samantha (English (US)) - Default female"
echo "2. Daniel (English (UK)) - British male"
echo "3. Karen (English (AU)) - Australian female"
echo "4. Fred (English (US)) - Classic male"
echo "5. Moira (English (IE)) - Irish female"
echo "6. Tessa (English (ZA)) - South African female"
echo ""
echo "Neural Voices (High Quality):"
echo "7. Eddy (English (US)) - Neural male"
echo "8. Flo (English (US)) - Neural female"
echo "9. Grandma (English (US)) - Warm older female"
echo "10. Reed (English (US)) - Professional male"
echo ""
echo "Fun Voices:"
echo "11. Whisper - Soft whisper"
echo "12. Zarvox - Robot voice"
echo "13. Good News - Cheerful"
echo "14. Bad News - Ominous"
echo ""
echo "15. Custom - Enter your own voice name"
echo "16. List all available voices"
echo ""

read -p "Choose a voice (1-16): " choice

case $choice in
    1) VOICE="Samantha (English (US))" ;;
    2) VOICE="Daniel (English (UK))" ;;
    3) VOICE="Karen (English (AU))" ;;
    4) VOICE="Fred (English (US))" ;;
    5) VOICE="Moira (English (IE))" ;;
    6) VOICE="Tessa (English (ZA))" ;;
    7) VOICE="Eddy (English (US))" ;;
    8) VOICE="Flo (English (US))" ;;
    9) VOICE="Grandma (English (US))" ;;
    10) VOICE="Reed (English (US))" ;;
    11) VOICE="Whisper" ;;
    12) VOICE="Zarvox" ;;
    13) VOICE="Good News" ;;
    14) VOICE="Bad News" ;;
    15) 
        echo ""
        read -p "Enter voice name (see 'say -v ?' for full list): " VOICE
        ;;
    16)
        echo ""
        echo "All available voices:"
        say -v '?'
        exit 0
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

# Test the voice
echo "🔊 Testing voice: $VOICE"
say -v "$VOICE" "Hello! I'm your new Milo voice. How do I sound?"

echo ""
read -p "Do you like this voice? (y/n): " confirm

if [[ $confirm =~ ^[Yy]$ ]]; then
    # Update the config file
    jq --arg voice "$VOICE" '.ttsVoice = $voice' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    echo "✅ Voice changed to: $VOICE"
    echo "🔄 Restart MiloOverlay for the change to take effect"
else
    echo "❌ Voice change cancelled"
fi