# Fix & Tone Down Audio Visualizer

## Problem

The `AudioVisualizerView` animates but does not respond to the user's voice. Bars wave independently of actual audio input. Additionally, the visualizer is visually too intense (36 bars, 40pt height, constant motion even during silence).

## Root Cause

ffmpeg buffers its WAV output and only flushes to disk on process termination. The level monitor reads the growing WAV file during recording but always sees 0 bytes, so `audioLevel` never updates. The original visualizer appeared to work only because it had a hardcoded minimum base that produced visible waves regardless of actual audio input.

## Fix

1. Add `-flush_packets 1` to the ffmpeg arguments in `AudioRecorder.swift` so audio data is written to disk in real time.
2. Replace the bar-based visualizer with a Canvas-based flowing waveform that smoothly responds to the audio level.

## Implementation

The new `AudioVisualizerView` uses a SwiftUI `Canvas` to draw 3 layered sine curves (defined by `WaveLayer` structs) that flow horizontally. A timer at 25ms intervals drives `advancePhase()` which advances the wave phase and smooths the incoming `level` into `smoothLevel` (fast attack 0.4, slow decay 0.08). The `drawWaves()` method renders each layer as a composite of two sine frequencies with edge-fade and amplitude scaling.

| Parameter | Value |
|-----------|-------|
| Timer interval | 0.025s (~40fps) |
| Wave layers | 3 (primary, harmonic, sub-bass) |
| Phase increment | 0.06/frame |
| Gain multiplier | 1.974 |
| Idle minimum | 0.08 |
| Amplitude scale | 0.42 * height |
| Container height | 32pt |

## Other Changes

- Removed `MiniLevelDots` from the recording HUD (top-right corner dots)
- Replaced hardcoded "Claw Island" label with `model.agentName.capitalized` in the speaking state
- Removed `.shadow()` from the HUD to eliminate gray corner artifacts
- Switched clip shape from custom `IslandShellShape` to `UnevenRoundedRectangle`

## Files Changed

- `src/clawIsland/Sources/clawIsland/AudioRecorder.swift` (added `-flush_packets 1`)
- `src/clawIsland/Sources/clawIsland/RecordingHUD.swift` (new waveform visualizer, HUD model changes)
- `src/clawIsland/Sources/clawIsland/clawIslandApp.swift` (set `hudModel.agentName` from config)

## Expected Behavior

- Silence: gentle idle wave with minimal amplitude
- Soft speech: small flowing waveform
- Normal speech: moderate wave clearly showing voice modulation
- Loud speech: tall waves filling the visualizer height
