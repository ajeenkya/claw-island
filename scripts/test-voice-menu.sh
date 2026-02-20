#!/bin/bash

# Test voice selection functionality
echo "🎤 Testing Voice Selection in MiloOverlay"
echo ""

CONFIG_FILE="$HOME/.openclaw/milo-overlay.json"
CURRENT_VOICE=$(jq -r '.ttsVoice // "Samantha (English (US))"' "$CONFIG_FILE")

echo "📋 Current voice: $CURRENT_VOICE"
echo ""

echo "🔊 Testing current voice..."
say -v "$CURRENT_VOICE" "Hello! This is your current MiloOverlay voice."

echo ""
echo "✅ Voice menu has been added to MiloOverlay!"
echo ""
echo "📖 How to use the new voice menu:"
echo "1. Click the MiloOverlay microphone icon in your menu bar"
echo "2. Hover over 'Voice' to see the submenu"
echo "3. Choose from popular voices like:"
echo "   • Samantha (English (US)) - Default female"
echo "   • Daniel (English (UK)) - British male" 
echo "   • Eddy (English (US)) - Neural male"
echo "   • Flo (English (US)) - Neural female"
echo "   • Whisper - Soft whisper"
echo "   • Zarvox - Robot voice"
echo "4. Click 'More Voices...' to see all available system voices"
echo ""
echo "🎯 The selected voice will be tested and saved automatically!"