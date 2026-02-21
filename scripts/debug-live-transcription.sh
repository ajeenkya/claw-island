#!/bin/bash

echo "🔍 Debugging Live Transcription Issues"
echo ""

echo "📋 Checking system requirements..."
echo ""

# Check macOS version
echo "🖥️  macOS Version:"
sw_vers
echo ""

# Check microphone permission
echo "🎤 Microphone Permission Check:"
echo "   Run: System Preferences → Security & Privacy → Microphone"
echo "   Make sure clawIsland is enabled"
echo ""

# Check speech recognition permission  
echo "🗣️  Speech Recognition Permission:"
echo "   Run: System Preferences → Security & Privacy → Speech Recognition"
echo "   Make sure clawIsland is enabled"
echo ""

# Check available audio devices
echo "🔊 Available Audio Input Devices:"
system_profiler SPAudioDataType | grep -A 10 "Built-in Microphone\|USB"
echo ""

# Test system speech recognition
echo "🧪 Testing system say command:"
say -v "Samantha (English (US))" "Testing speech synthesis"
echo ""

echo "🎯 Common Issues & Solutions:"
echo ""
echo "1. **No microphone permission**"
echo "   → System Preferences → Security & Privacy → Microphone → Enable clawIsland"
echo ""
echo "2. **No speech recognition permission**" 
echo "   → System Preferences → Security & Privacy → Speech Recognition → Enable clawIsland"
echo ""
echo "3. **SFSpeechRecognizer unavailable**"
echo "   → macOS 10.15+ required, check macOS version above"
echo ""
echo "4. **Live transcription too sensitive**"
echo "   → Try speaking more clearly and loudly"
echo "   → Ensure good microphone positioning"
echo ""
echo "5. **Audio engine conflicts**"
echo "   → Close other audio apps (Zoom, Discord, etc.)"
echo "   → Restart clawIsland if needed"
echo ""

CONFIG_FILE="$HOME/.openclaw/clawIsland.json"
if [ -f "$CONFIG_FILE" ]; then
    echo "⚙️  Current clawIsland Config:"
    cat "$CONFIG_FILE" | jq .
else
    echo "❌ Config file not found: $CONFIG_FILE"
fi