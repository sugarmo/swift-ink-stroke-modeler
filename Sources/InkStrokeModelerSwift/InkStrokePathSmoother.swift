import Foundation
import CoreGraphics

// High-level helper to build a smoothed CGPath from streaming input points
// using InkStrokeModeler.
public final class InkStrokePathSmoother {
    private let modeler = StrokeModeler()

    private let wobble: WobbleSmootherParams
    private let position: PositionModelerParams
    private let sampling: SamplingParams
    private let stylus: StylusStateModelerParams
    private let prediction: PredictionParams

    private var started = false
    private var ended = false

    private var pathMutable = CGMutablePath()
    private var hasPathMove = false

    public private(set) var path: CGPath {
        get { pathMutable.copy() ?? pathMutable }
        set { /* ignore external set */ }
    }

    // Configure with explicit parameters.
    // Provide reasonable defaults for a smooth, high-frequency output.
    public init(
        wobble: WobbleSmootherParams = .init(isEnabled: false),
        position: PositionModelerParams = .init(),
        sampling: SamplingParams = .init(minOutputRate: 180,
                                         endOfStrokeStoppingDistance: 0.001,
                                         endOfStrokeMaxIterations: 20,
                                         maxOutputsPerCall: 100_000,
                                         maxEstimatedAngleToTraversePerInput: -1),
        stylus: StylusStateModelerParams = .init(useStrokeNormalProjection: false),
        prediction: PredictionParams = .strokeEnd
    ) {
        self.wobble = wobble
        self.position = position
        self.sampling = sampling
        self.stylus = stylus
        self.prediction = prediction
    }

    public func resetPath() {
        // Clear current path and internal state for a new stroke.
        pathMutable = CGMutablePath()
        started = false
        ended = false
        hasPathMove = false
    }

    // Begin a stroke at a point/time.
    public func start(at point: CGPoint, time: TimeInterval,
                      pressure: Float = -1, tilt: Float = -1, orientation: Float = -1) throws {
        guard !ended else { throw StrokeModelerError.failedPrecondition }
        guard !started else { throw StrokeModelerError.failedPrecondition }

        // Reset modeler with configured params
        try modeler.reset(wobble: wobble,
                          position: position,
                          sampling: sampling,
                          stylus: stylus,
                          prediction: prediction)

        started = true
        hasPathMove = false

        let results = try modeler.update(StrokeInput(eventType: .down,
                                               x: Float(point.x), y: Float(point.y),
                                               time: time,
                                               pressure: pressure,
                                               tilt: tilt,
                                               orientation: orientation))
        appendResultsToPath(results)
    }

    // Append a point/time update.
    public func append(point: CGPoint, time: TimeInterval,
                       pressure: Float = -1, tilt: Float = -1, orientation: Float = -1) throws {
        guard started, !ended else { throw StrokeModelerError.failedPrecondition }
        let res = try modeler.update(StrokeInput(eventType: .move,
                                           x: Float(point.x), y: Float(point.y),
                                           time: time,
                                           pressure: pressure,
                                           tilt: tilt,
                                           orientation: orientation))
        appendResultsToPath(res)
    }

    // End the stroke. Optionally specify a final time; if not, the last time
    // used in append should be reused by callers to determine timestamps.
    @discardableResult
    public func end(time: TimeInterval? = nil,
                    point: CGPoint? = nil,
                    pressure: Float = -1, tilt: Float = -1, orientation: Float = -1) throws -> CGPath {
        guard started, !ended else { throw StrokeModelerError.failedPrecondition }

        // Allow final move point right before up.
        if let p = point, let t = time {
            let resMove = try modeler.update(StrokeInput(eventType: .move,
                                                   x: Float(p.x), y: Float(p.y),
                                                   time: t,
                                                   pressure: pressure,
                                                   tilt: tilt,
                                                   orientation: orientation))
            appendResultsToPath(resMove)
        }

        let tUp = time ?? 0 // time is unit-agnostic; 0 is fine if not used by caller
        let res = try modeler.update(StrokeInput(eventType: .up,
                                           x: Float(point?.x ?? 0), y: Float(point?.y ?? 0),
                                           time: tUp,
                                           pressure: pressure,
                                           tilt: tilt,
                                           orientation: orientation))
        appendResultsToPath(res)

        ended = true
        return path
    }

    private func appendResultsToPath(_ results: [StrokeSample]) {
        guard !results.isEmpty else { return }
        for (idx, r) in results.enumerated() {
            let p = CGPoint(x: CGFloat(r.x), y: CGFloat(r.y))
            if !hasPathMove {
                pathMutable.move(to: p)
                hasPathMove = true
            } else {
                // Skip zero-length segments (can occur in dense outputs)
                if idx == 0 {
                    // Connect from existing current point to first new point
                    pathMutable.addLine(to: p)
                } else {
                    pathMutable.addLine(to: p)
                }
            }
        }
    }
}
