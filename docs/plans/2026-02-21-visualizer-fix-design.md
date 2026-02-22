# Fix & Tone Down Audio Visualizer

## Problem

The `AudioVisualizerView` animates but does not respond to the user's voice. Bars wave independently of actual audio input. Additionally, the visualizer is visually too intense (36 bars, 40pt height, constant motion even during silence).

## Root Cause

`AudioVisualizerView` receives `level` as a plain `let` property. Its internal timer calls `updateBars()` which reads `level`, but SwiftUI may not re-render the view body on every fast audio level change from the parent `@ObservedObject`. The `level` value read inside `updateBars()` can be stale, causing the animation to run with an outdated (often initial) level value.

## Fix

Use `.onChange(of: level)` to sync incoming level into a local `@State var currentLevel`. Read `currentLevel` inside `updateBars()` so the animation always uses the latest value.

## Visual Changes

| Parameter | Before | After |
|-----------|--------|-------|
| Bar count | 36 | 20 |
| Max bar height | 40pt | 24pt |
| Bar width | 2.5pt | 2pt |
| Bar spacing | 1.5pt | 1.5pt |
| Base at silence | 0.06 | 0.0 |
| Gain multiplier | 1.35 | 1.2 |
| Wave amplitude | 0.3 | 0.15 |
| Noise range | 0.9-1.1 | 0.95-1.05 |
| Envelope exponent | 2.0 | 2.5 |
| Opacity range | 0.4-1.0 | 0.3-0.8 |

## Files Changed

- `src/clawIsland/Sources/clawIsland/RecordingHUD.swift` (AudioVisualizerView, lines 361-418)

## Expected Behavior

- Silence: bars rest at near-zero height
- Soft speech: gentle, low-amplitude wave
- Normal speech: moderate wave showing voice modulation
- Loud speech: full height, lively but not overwhelming
