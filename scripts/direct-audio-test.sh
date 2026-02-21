#!/bin/bash

echo "🧪 DIRECT AUDIO TEST - No UI, Just Core Functionality"
echo "================================================="
echo ""

# Kill any existing clawIsland
pkill clawIsland 2>/dev/null

echo "🎤 Testing basic audio recording..."

# Test 1: Can we record audio at all?
echo "Recording 3 seconds of audio..."
timeout 3 ffmpeg -f avfoundation -i ":0" -t 3 -y /tmp/test_audio.wav 2>/dev/null

if [ ! -f /tmp/test_audio.wav ]; then
    echo "❌ FAILED: Cannot record audio - microphone permission issue"
    echo "   Please grant microphone permission to Terminal in System Preferences"
    exit 1
fi

FILE_SIZE=$(wc -c < /tmp/test_audio.wav)
echo "✅ Audio recorded: ${FILE_SIZE} bytes"

# Test 2: Can we transcribe with Whisper?
echo ""
echo "🔍 Testing Whisper transcription..."
cd "$(dirname "$0")/../src/clawIsland/.build/release"

if command -v whisper >/dev/null 2>&1; then
    echo "Using system whisper..."
    TRANSCRIPT=$(whisper /tmp/test_audio.wav --model tiny --output_format txt 2>/dev/null | tail -1)
elif [ -f whisper-cpp ]; then
    echo "Using whisper-cpp..."
    TRANSCRIPT=$(./whisper-cpp -f /tmp/test_audio.wav -m models/ggml-base.en.bin 2>/dev/null | grep -v "whisper_" | tail -1)
else
    echo "❌ No Whisper found - trying basic test"
    TRANSCRIPT="whisper_not_available"
fi

echo "📝 Transcript: '$TRANSCRIPT'"

# Test 3: Can we make HTTP request to OpenClaw?
echo ""
echo "📡 Testing OpenClaw connection..."
RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null http://localhost:18789/api/chat/completions)
if [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "401" ] || [ "$RESPONSE" = "405" ]; then
    echo "✅ OpenClaw reachable (HTTP $RESPONSE)"
else
    echo "❌ OpenClaw not reachable (HTTP $RESPONSE)"
fi

# Cleanup
rm -f /tmp/test_audio.wav

echo ""
echo "🎯 RESULTS:"
echo "   Audio recording: $([ $FILE_SIZE -gt 1000 ] && echo "✅ WORKING" || echo "❌ FAILED")"
echo "   Whisper transcription: $([ -n "$TRANSCRIPT" ] && echo "✅ AVAILABLE" || echo "❌ MISSING")"
echo "   OpenClaw connection: $([ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "401" ] || [ "$RESPONSE" = "405" ] && echo "✅ WORKING" || echo "❌ FAILED")"
echo ""

if [ $FILE_SIZE -gt 1000 ]; then
    echo "🚀 BASIC AUDIO WORKS! The issue is likely with clawIsland's UI/permissions."
    echo "   Try this: Record a voice memo and speak: 'Hello, this is a test'"
    echo ""
    read -p "Press Enter after you've spoken, then I'll record and transcribe..."
    echo ""
    echo "🎤 Recording NOW - speak clearly..."
    timeout 5 ffmpeg -f avfoundation -i ":0" -t 5 -y /tmp/voice_test.wav 2>/dev/null
    
    if [ -f /tmp/voice_test.wav ]; then
        FILE_SIZE2=$(wc -c < /tmp/voice_test.wav)
        echo "✅ Recorded ${FILE_SIZE2} bytes"
        
        # Try to transcribe with system tools
        if command -v whisper >/dev/null 2>&1; then
            echo "🔍 Transcribing..."
            whisper /tmp/voice_test.wav --model tiny --output_format txt 2>/dev/null
        else
            echo "🔍 Whisper not available for transcription test"
        fi
        
        rm -f /tmp/voice_test.wav
    else
        echo "❌ Recording failed"
    fi
else
    echo "❌ AUDIO NOT WORKING - microphone permission issue"
    echo "   Grant microphone permission to Terminal in System Preferences"
fi