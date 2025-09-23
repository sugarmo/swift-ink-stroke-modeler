# swift-ink-stroke-modeler

Swift Package that wraps Google’s [ink-stroke-modeler] C++ library and exposes a
clean Swift API for real‑time ink smoothing and prediction on Apple platforms.

- Targets
  - `InkStrokeModeler` (C++ sources from upstream, built via SwiftPM)
  - `InkStrokeModelerFFI` (C/ObjC++ shim; hides Abseil/C++ templates)
  - `InkStrokeModelerSwift` (Swift‑friendly API)
- Platforms: iOS 14+, macOS 12+
- Swift Tools: 5.9+

This package fetches Abseil via Firebase’s SPM distribution to support iOS/macOS
without system‑level installs.

[ink-stroke-modeler]: https://github.com/google/ink-stroke-modeler

## Installation

Add to your project’s `Package.swift` dependencies:

```swift
.package(url: "https://github.com/YOUR_ORG_OR_USER/swift-ink-stroke-modeler.git", branch: "main")
```

Then depend on the Swift target in your app or framework target:

```swift
.target(
  name: "MyApp",
  dependencies: [
    .product(name: "InkStrokeModelerSwift", package: "swift-ink-stroke-modeler")
  ]
)
```

Import in code:

```swift
import InkStrokeModelerSwift
```

## Quick Start (low‑level)

Use `StrokeModeler` for direct control over parameters and streaming inputs.

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

- `StrokeSample` exposes position/velocity/acceleration, timestamp and stylus
  attributes.
- Throws on invalid parameter combinations or ordering (e.g. calling `update`
  before `reset`, or sending inputs out of order).

## Quick Start (CGPath helper)

`InkStrokePathSmoother` helps build a smoothed `CGPath` from streaming input.

```swift
let smoother = InkStrokePathSmoother()
try smoother.start(at: CGPoint(x: 10, y: 20), time: 0.0)
try smoother.append(point: CGPoint(x: 20, y: 30), time: 0.01)
let path: CGPath = try smoother.end(time: 0.02)
```

- `start/append/end` updates an internal `CGMutablePath` incrementally.
- After `end`, `path` is the final smoothed path for the stroke.
- Call `resetPath()` to clear and begin a new stroke.

### End‑to‑end Swift usage example

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

// 2) Feed points
let down = StrokeInput(eventType: .down, x: 0, y: 0, time: 0)
let _ = try modeler.update(down)

for i in 1...5 {
  let t = Double(i) * 0.01
  let _ = try modeler.update(StrokeInput(eventType: .move,
                                         x: Float(i) * 10, y: Float(i) * 5,
                                         time: t))
}

// Optional: prediction while in progress
let predicted: [StrokeSample] = try modeler.predict(max: 128)

// 3) End stroke
let _ = try modeler.update(StrokeInput(eventType: .up, x: 60, y: 30, time: 0.06))

// 4) Build a CGPath using the helper
let smoother = InkStrokePathSmoother()
try smoother.start(at: CGPoint(x: 0, y: 0), time: 0)
try smoother.append(point: CGPoint(x: 50, y: 25), time: 0.05)
let finalPath = try smoother.end(time: 0.06)
```

## Parameters Overview

The Swift API exposes the major knob sets from the upstream library:

- `WobbleSmootherParams`
  - `isEnabled`, `timeout`, `speedFloor`, `speedCeiling`
- `PositionModelerParams`
  - `springMassConstant`, `dragConstant`, `loop: LoopContractionMitigationParams`
- `LoopContractionMitigationParams`
  - `isEnabled`, speed bounds, interpolation strengths, `minSpeedSamplingWindow`
  - When enabled, set `StylusStateModelerParams.useStrokeNormalProjection = true`.
- `SamplingParams`
  - `minOutputRate`, `endOfStrokeStoppingDistance`, `endOfStrokeMaxIterations`,
    `maxOutputsPerCall`, `maxEstimatedAngleToTraversePerInput`
- `StylusStateModelerParams`
  - `useStrokeNormalProjection`
- `PredictionParams`
  - `.strokeEnd`, `.disabled`, `.kalman(KalmanPredictorParams)`

All time/duration values are unit‑agnostic; keep the same units across your
inputs and parameters.

## Notes

- C++20 toolchain is required but handled by SwiftPM for Apple platforms.
- Abseil is provided via [firebase/abseil-cpp-SwiftPM], so no system install is
  needed.
- This package doesn’t include upstream tests; it builds the core library only.

### Error handling

Most API calls can throw `StrokeModelerError` if:
- parameters are invalid (e.g. loop mitigation enabled without `useStrokeNormalProjection`),
- inputs arrive out of order (e.g. `.move` before `.down`), or
- `update/predict` is called before `reset`.

Wrap calls in `do/catch` and report configuration issues early.

[firebase/abseil-cpp-SwiftPM]: https://github.com/firebase/abseil-cpp-SwiftPM

## License

This package wraps Google’s `ink-stroke-modeler` (Apache‑2.0). See upstream for
license details of the C++ sources. This repository’s Swift code is provided
under the same license.
