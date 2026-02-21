#!/bin/bash
set -euo pipefail

CLIENT_FILTER="(client LIKE '%clawIsland%' OR client LIKE '%VyomOverlay%' OR client='com.openclaw.clawIsland' OR client='com.openclaw.vyom-overlay')"

echo "🔐 Checking clawIsland Permissions"
echo ""

# Check current permissions using tccutil if available
echo "🎤 Microphone Access:"
if command -v tccutil &> /dev/null; then
    # Check microphone permission
    MIC_STATUS=$(sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "SELECT allowed FROM access WHERE service='kTCCServiceMicrophone' AND ${CLIENT_FILTER} ORDER BY last_modified DESC LIMIT 1;" 2>/dev/null || echo "unknown")
    if [ "$MIC_STATUS" = "1" ]; then
        echo "   ✅ Microphone permission: GRANTED"
    elif [ "$MIC_STATUS" = "0" ]; then
        echo "   ❌ Microphone permission: DENIED"
    else
        echo "   ⚠️  Microphone permission: UNKNOWN (may need to grant)"
    fi
    
    # Check speech recognition permission
    SPEECH_STATUS=$(sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "SELECT allowed FROM access WHERE service='kTCCServiceSpeechRecognition' AND ${CLIENT_FILTER} ORDER BY last_modified DESC LIMIT 1;" 2>/dev/null || echo "unknown")
    if [ "$SPEECH_STATUS" = "1" ]; then
        echo "   ✅ Speech Recognition permission: GRANTED"
    elif [ "$SPEECH_STATUS" = "0" ]; then
        echo "   ❌ Speech Recognition permission: DENIED"
    else
        echo "   ⚠️  Speech Recognition permission: UNKNOWN (may need to grant)"
    fi
else
    echo "   ℹ️  Cannot check permissions automatically"
    echo "   ℹ️  Please manually check System Preferences → Security & Privacy"
fi

echo ""
echo "📋 Manual Permission Check:"
echo "1. Open System Preferences"
echo "2. Go to Security & Privacy → Privacy"
echo "3. Check both:"
echo "   • Microphone → Make sure clawIsland is checked"
echo "   • Speech Recognition → Make sure clawIsland is checked"
echo ""

# Test basic audio recording
echo "🧪 Testing basic audio access..."
timeout 2 ffmpeg -f avfoundation -i ":0" -t 1 /tmp/test_audio.wav &>/dev/null
if [ $? -eq 0 ]; then
    echo "   ✅ Basic audio recording works"
    rm -f /tmp/test_audio.wav
else
    echo "   ❌ Basic audio recording failed - microphone permission issue"
fi

echo ""
echo "🚀 To fix live transcription:"
echo "1. Grant microphone permission if needed"
echo "2. Grant speech recognition permission if needed"  
echo "3. Restart clawIsland"
echo "4. Test with fn key - speak clearly and loudly"
echo ""
echo "🖥️ For screen capture issues (OpenClaw screenshots), run:"
echo "   ./scripts/screen-recording-doctor.sh"
