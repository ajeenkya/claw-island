#!/bin/bash

echo "🧪 Testing clawIsland Audio Pipeline"
echo ""

# Kill any existing clawIsland
pkill clawIsland 2>/dev/null

# Start a simple audio recording test first
echo "📡 Testing basic audio recording with ffmpeg..."
timeout 3 ffmpeg -f avfoundation -i ":0" -t 2 -y /tmp/test_recording.wav 2>/dev/null

if [ -f /tmp/test_recording.wav ]; then
    # Check if the file has actual audio content
    FILE_SIZE=$(wc -c < /tmp/test_recording.wav)
    if [ $FILE_SIZE -gt 1000 ]; then
        echo "✅ Basic audio recording works (${FILE_SIZE} bytes)"
        
        # Try to get audio info
        ffprobe -v quiet -show_entries stream=duration,sample_rate,channels -of csv=p=0 /tmp/test_recording.wav 2>/dev/null | head -1
    else
        echo "❌ Audio file too small (${FILE_SIZE} bytes) - likely no input"
    fi
    
    rm -f /tmp/test_recording.wav
else
    echo "❌ Basic audio recording failed - microphone permission issue"
fi

echo ""
echo "🎤 Testing system microphone access..."

# List audio devices
echo "Available audio input devices:"
ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep "\[AVFoundation.*audio" | head -5

echo ""
echo "🔐 Checking permissions..."

# Try to read TCC database for permissions
if [ -r ~/Library/Application\ Support/com.apple.TCC/TCC.db ]; then
    echo "TCC Database readable - checking permissions..."
    
    # Check for clawIsland microphone permission
    MIC_PERM=$(sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "SELECT service,client,allowed FROM access WHERE service='kTCCServiceMicrophone' AND client LIKE '%clawIsland%' ORDER BY last_modified DESC LIMIT 1;" 2>/dev/null)
    
    if [ -n "$MIC_PERM" ]; then
        echo "📊 Microphone permission: $MIC_PERM"
    else
        echo "⚠️  No microphone permission record found for clawIsland"
    fi
    
    # Check speech recognition permission
    SPEECH_PERM=$(sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "SELECT service,client,allowed FROM access WHERE service='kTCCServiceSpeechRecognition' AND client LIKE '%clawIsland%' ORDER BY last_modified DESC LIMIT 1;" 2>/dev/null)
    
    if [ -n "$SPEECH_PERM" ]; then
        echo "📊 Speech recognition permission: $SPEECH_PERM"
    else
        echo "⚠️  No speech recognition permission record found for clawIsland"
    fi
else
    echo "⚠️  Cannot read TCC database - check System Preferences manually"
fi

echo ""
echo "🚀 Starting clawIsland with enhanced debugging..."
echo "Press fn key to test - watch for audio level logs and transcript updates"
echo ""

# Start clawIsland in foreground so we can see all logs
cd "$(dirname "$0")/../src/clawIsland"
exec ./.build/release/clawIsland