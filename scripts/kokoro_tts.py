#!/usr/bin/env python3
"""
Generate a WAV file with Kokoro-82M.

Usage:
  kokoro_tts.py --text "hello" --voice af_heart --lang a --speed 1.0 --output /tmp/out.wav
"""

from __future__ import annotations

import argparse
import os
import sys


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Synthesize speech with Kokoro")
    parser.add_argument("--text", required=True, help="Input text to synthesize")
    parser.add_argument("--voice", default="af_heart", help="Kokoro voice id")
    parser.add_argument("--lang", default="a", help="KPipeline language code")
    parser.add_argument("--speed", type=float, default=1.0, help="Speech rate multiplier")
    parser.add_argument("--output", required=True, help="Output WAV path")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    text = args.text.strip()
    if not text:
        print("empty text", file=sys.stderr)
        return 2

    try:
        import numpy as np
        import soundfile as sf
        from kokoro import KPipeline
    except Exception as exc:  # pragma: no cover - runtime dependency path
        print(f"import error: {exc}", file=sys.stderr)
        return 3

    try:
        pipeline = KPipeline(lang_code=args.lang)
        generator = pipeline(
            text,
            voice=args.voice,
            speed=args.speed,
            split_pattern=r"\n+",
        )

        chunks = []
        for _graphemes, _phonemes, audio in generator:
            if audio is None:
                continue
            chunks.append(np.asarray(audio, dtype=np.float32))

        if not chunks:
            print("no audio chunks produced", file=sys.stderr)
            return 4

        audio_all = np.concatenate(chunks, axis=0)
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        sf.write(args.output, audio_all, 24000)
        return 0
    except Exception as exc:  # pragma: no cover - runtime synthesis path
        print(f"synthesis error: {exc}", file=sys.stderr)
        return 5


if __name__ == "__main__":
    raise SystemExit(main())
