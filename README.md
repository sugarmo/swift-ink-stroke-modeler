# InkStrokeModeler for Swift

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-Apache%202.0-lightgrey.svg)](https://opensource.org/licenses/Apache-2.0)

A Swift Package that wraps Google’s [ink-stroke-modeler](https://github.com/google/ink-stroke-modeler) C++ library, exposing a clean, idiomatic Swift API for real-time ink smoothing and prediction on Apple platforms.

This library turns noisy, raw pointer input from a touch device or stylus into beautiful, smooth stroke patterns, ideal for drawing and handwriting applications. It models the physics of a pen tip to create aesthetically pleasing curves while minimizing latency through motion prediction.

![Position Model Diagram](https://raw.githubusercontent.com/google/ink-stroke-modeler/refs/heads/main/position_model.svg)

## Features

- **Real-time Smoothing**: Smooths jitter and noise from raw touch/stylus input.
- **Latency-masking Prediction**: Predicts the stroke's path to provide a more responsive drawing experience.
- **Configurable Physics**: Fine-tune parameters like spring-mass, drag, wobble smoothing, and more.
- **Multiple Prediction Engines**: Choose between a simple stroke-end predictor or an advanced Kalman filter predictor.
- **High-level Helpers**: Includes a `CGPath` helper to easily generate smoothed paths from a series of points.
- **Type-Safe & Idiomatic API**: A pure Swift interface that handles the complexity of C++ interop for you.
- **Self-Contained**: All dependencies (Abseil, C++ sources) are managed internally by the Swift package.

## How It Works

The package is structured in three layers to safely bridge the underlying C++ library with a pure Swift interface:

- `InkStrokeModeler` (C++): The core C++ sources from Google's upstream repository, compiled directly by SwiftPM.
- `InkStrokeModelerFFI` (C/Objective-C++): A thin C-style shim that hides C++ templates and Abseil details from Swift.
- `InkStrokeModelerSwift` (Swift): The public, Swift-friendly API that your application will consume.

## Requirements

- **Swift Tools**: 5.9+
- **Platforms**: iOS 14+, macOS 12+

## Installation

Add the package to your project’s `Package.swift` dependencies:

```swift
.package(url: "https://github.com/sugarmo/swift-ink-stroke-modeler.git", branch: "main")
```

Then, add the `InkStrokeModelerSwift` product to your app or framework target:

```swift
.target(
  name: "MyApp",
  dependencies: [
    .product(name: "InkStrokeModelerSwift", package: "swift-ink-stroke-modeler")
  ]
)
```

Finally, import the module in your code:

```swift
import InkStrokeModelerSwift
```

## Quick Start

### 1. Low-Level: `StrokeModeler`

Use `StrokeModeler` for direct control over parameters and streaming individual input points.

```swift
let modeler = StrokeModeler()

// Configure parameters (values shown are a reasonable starting point)
let sampling = SamplingParams(minOutputRate: 180,
                              endOfStrokeStoppingDistance: 0.001,
                              endOfStrokeMaxIterations: 20,
                              maxOutputsPerCall: 100_000,
                              maxEstimatedAngleToTraversePerInput: -1)
try modeler.reset(
  wobble: WobbleSmootherParams(isEnabled: false),
  position: PositionModelerParams(),
  sampling: sampling,
  stylus: StylusStateModelerParams(useStrokeNormalProjection: false),
  prediction: .strokeEnd
)

// Stream points (down/move/up)
let down = StrokeInput(eventType: .down, x: 10, y: 20, time: 0.0)
let resDown: [StrokeSample] = try modeler.update(down)

let move = StrokeInput(eventType: .move, x: 20, y: 30, time: 0.01,
                       pressure: 0.3, tilt: 0.2, orientation: .pi/4)
let resMove: [StrokeSample] = try modeler.update(move)

// Optionally get a prediction during a stroke
let prediction: [StrokeSample] = try modeler.predict(max: 256)

let up = StrokeInput(eventType: .up, x: 25, y: 35, time: 0.02)
let resUp: [StrokeSample] = try modeler.update(up)
```

- `StrokeSample` exposes position, velocity, acceleration, timestamp, and stylus attributes.
- The API throws a `StrokeModelerError` on invalid parameter combinations or if inputs are sent in the wrong order (e.g., `.move` before `.down`).

### 2. High-Level: `InkStrokePathSmoother`

`InkStrokePathSmoother` is a convenient helper for building a smoothed `CGPath` from a stream of points.

```swift
let smoother = InkStrokePathSmoother()
try smoother.start(at: CGPoint(x: 10, y: 20), time: 0.0)
try smoother.append(point: CGPoint(x: 20, y: 30), time: 0.01)
let path: CGPath = try smoother.end(time: 0.02)
```

- `start/append/end` methods update an internal `CGMutablePath` incrementally.
- After `end`, `path` contains the final smoothed path for the stroke.
- Call `resetPath()` to clear the state and begin a new stroke.

## End-to-End Example

This example configures the modeler with a Kalman predictor and feeds it a series of points.

```swift
import InkStrokeModelerSwift
import CoreGraphics

// 1) Configure a modeler with Kalman prediction
let kalman = KalmanPredictorParams(
  processNoise: 0.002,
  measurementNoise: 0.001,
  minStableIteration: 4,
  maxTimeSamples: 20,
  minCatchupVelocity: 0.0003,
  accelerationWeight: 0.5,
  jerkWeight: 0.1,
  predictionInterval: 0.02,
  confidence: KalmanConfidenceParams(
    desiredNumberOfSamples: 20,
    maxEstimationDistance: 0.005,
    minTravelSpeed: 0.0005,
    maxTravelSpeed: 0.01,
    maxLinearDeviation: 0.01,
    baselineLinearityConfidence: 0.4
  )
)

let sampling = SamplingParams(
  minOutputRate: 180,
  endOfStrokeStoppingDistance: 0.001,
  endOfStrokeMaxIterations: 20,
  maxOutputsPerCall: 100_000,
  maxEstimatedAngleToTraversePerInput: -1
)

let modeler = StrokeModeler()
try modeler.reset(
  wobble: WobbleSmootherParams(isEnabled: false),
  position: PositionModelerParams(),
  sampling: sampling,
  stylus: StylusStateModelerParams(useStrokeNormalProjection: false),
  prediction: .kalman(kalman)
)

// 2) Feed points to the modeler
let down = StrokeInput(eventType: .down, x: 0, y: 0, time: 0)
let _ = try modeler.update(down)

for i in 1...5 {
  let t = Double(i) * 0.01
  let _ = try modeler.update(StrokeInput(eventType: .move,
                                         x: Float(i) * 10, y: Float(i) * 5,
                                         time: t))
}

// 3) Get an optional prediction while the stroke is in progress
let predicted: [StrokeSample] = try modeler.predict(max: 128)
print("Received \(predicted.count) predicted samples.")

// 4) End the stroke
let _ = try modeler.update(StrokeInput(eventType: .up, x: 60, y: 30, time: 0.06))

// 5) Build a final CGPath using the helper
let smoother = InkStrokePathSmoother()
try smoother.start(at: CGPoint(x: 0, y: 0), time: 0)
try smoother.append(point: CGPoint(x: 50, y: 25), time: 0.05)
let finalPath = try smoother.end(time: 0.06)
print("Final path created: \(finalPath)")
```

## Parameters Overview

The Swift API exposes the major parameter sets from the upstream library:

- `WobbleSmootherParams`
- `PositionModelerParams`
- `LoopContractionMitigationParams`
- `SamplingParams`
- `StylusStateModelerParams`
- `PredictionParams` (as an enum: `.strokeEnd`, `.disabled`, `.kalman(KalmanPredictorParams)`)

All time and duration values are unit-agnostic; ensure you use consistent units across all inputs and parameters.

## Contributing

Pull requests are welcome! Please open an issue to discuss major changes.

## License

This repository's Swift wrapper code is provided under the Apache 2.0 license, consistent with the underlying C++ library from Google. See the `LICENSE` file in the `ink-stroke-modeler` submodule for details on the C++ sources.
