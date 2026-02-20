#!/bin/bash
set -euo pipefail

echo "Installing whisper-cpp via Homebrew..."
brew install whisper-cpp

echo "Downloading base.en model..."
mkdir -p ~/.openclaw/models
MODEL_PATH="$HOME/.openclaw/models/ggml-base.en.bin"
if [ ! -f "$MODEL_PATH" ]; then
    curl -L -o "$MODEL_PATH" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
    echo "✅ Model downloaded to $MODEL_PATH"
else
    echo "✅ Model already exists at $MODEL_PATH"
fi
