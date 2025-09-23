import Foundation
import InkStrokeModelerFFI

public enum StrokeModelerError: Error {
    case invalidArgument
    case failedPrecondition
    case outOfRange
    case internalError
}

@inline(__always)
private func mapStatus(_ s: ism_Status) throws {
    switch s {
    case ISM_STATUS_OK: return
    case ISM_STATUS_INVALID_ARGUMENT: throw StrokeModelerError.invalidArgument
    case ISM_STATUS_FAILED_PRECONDITION: throw StrokeModelerError.failedPrecondition
    case ISM_STATUS_OUT_OF_RANGE: throw StrokeModelerError.outOfRange
    default: throw StrokeModelerError.internalError
    }
}

public enum EventType {
    case down
    case move
    case up

    var cEvent: ism_EventType {
        switch self {
        case .down: return ISM_EVENT_DOWN
        case .move: return ISM_EVENT_MOVE
        case .up: return ISM_EVENT_UP
        }
    }
}

public struct StrokeInput {
    public var eventType: EventType
    public var x: Float
    public var y: Float
    public var time: Double
    public var pressure: Float = -1
    public var tilt: Float = -1
    public var orientation: Float = -1

    public init(eventType: EventType, x: Float, y: Float, time: Double,
                pressure: Float = -1, tilt: Float = -1, orientation: Float = -1) {
        self.eventType = eventType
        self.x = x
        self.y = y
        self.time = time
        self.pressure = pressure
        self.tilt = tilt
        self.orientation = orientation
    }
}

public struct StrokeSample: Equatable {
    public var x: Float
    public var y: Float
    public var vx: Float
    public var vy: Float
    public var ax: Float
    public var ay: Float
    public var time: Double
    public var pressure: Float
    public var tilt: Float
    public var orientation: Float
}

public struct SamplingParams {
    public var minOutputRate: Double
    public var endOfStrokeStoppingDistance: Float
    public var endOfStrokeMaxIterations: Int32
    public var maxOutputsPerCall: Int32
    public var maxEstimatedAngleToTraversePerInput: Double // -1 to disable

    public init(minOutputRate: Double,
                endOfStrokeStoppingDistance: Float,
                endOfStrokeMaxIterations: Int32 = 20,
                maxOutputsPerCall: Int32 = 100_000,
                maxEstimatedAngleToTraversePerInput: Double = -1) {
        self.minOutputRate = minOutputRate
        self.endOfStrokeStoppingDistance = endOfStrokeStoppingDistance
        self.endOfStrokeMaxIterations = endOfStrokeMaxIterations
        self.maxOutputsPerCall = maxOutputsPerCall
        self.maxEstimatedAngleToTraversePerInput = maxEstimatedAngleToTraversePerInput
    }
}

public struct WobbleSmootherParams {
    public var isEnabled: Bool
    public var timeout: Double
    public var speedFloor: Float
    public var speedCeiling: Float
    public init(isEnabled: Bool = false, timeout: Double = 0,
                speedFloor: Float = -1, speedCeiling: Float = -1) {
        self.isEnabled = isEnabled
        self.timeout = timeout
        self.speedFloor = speedFloor
        self.speedCeiling = speedCeiling
    }
}

public struct LoopContractionMitigationParams {
    public var isEnabled: Bool
    public var speedLowerBound: Float
    public var speedUpperBound: Float
    public var interpolationStrengthAtSpeedLowerBound: Float
    public var interpolationStrengthAtSpeedUpperBound: Float
    public var minSpeedSamplingWindow: Double
    public init(isEnabled: Bool = false,
                speedLowerBound: Float = -1,
                speedUpperBound: Float = -1,
                interpolationStrengthAtSpeedLowerBound: Float = -1,
                interpolationStrengthAtSpeedUpperBound: Float = -1,
                minSpeedSamplingWindow: Double = 0) {
        self.isEnabled = isEnabled
        self.speedLowerBound = speedLowerBound
        self.speedUpperBound = speedUpperBound
        self.interpolationStrengthAtSpeedLowerBound = interpolationStrengthAtSpeedLowerBound
        self.interpolationStrengthAtSpeedUpperBound = interpolationStrengthAtSpeedUpperBound
        self.minSpeedSamplingWindow = minSpeedSamplingWindow
    }
}

public struct PositionModelerParams {
    public var springMassConstant: Float
    public var dragConstant: Float
    public var loop: LoopContractionMitigationParams
    public init(springMassConstant: Float = 11.0/32400.0,
                dragConstant: Float = 72.0,
                loop: LoopContractionMitigationParams = .init()) {
        self.springMassConstant = springMassConstant
        self.dragConstant = dragConstant
        self.loop = loop
    }
}

public struct StylusStateModelerParams {
    public var useStrokeNormalProjection: Bool
    public init(useStrokeNormalProjection: Bool = false) {
        self.useStrokeNormalProjection = useStrokeNormalProjection
    }
}

public enum PredictionKind { case strokeEnd, kalman, disabled }

public struct KalmanConfidenceParams {
    public var desiredNumberOfSamples: Int32
    public var maxEstimationDistance: Float
    public var minTravelSpeed: Float
    public var maxTravelSpeed: Float
    public var maxLinearDeviation: Float
    public var baselineLinearityConfidence: Float
}

public struct KalmanPredictorParams {
    public var processNoise: Double
    public var measurementNoise: Double
    public var minStableIteration: Int32
    public var maxTimeSamples: Int32
    public var minCatchupVelocity: Float
    public var accelerationWeight: Float
    public var jerkWeight: Float
    public var predictionInterval: Double
    public var confidence: KalmanConfidenceParams
}

public enum PredictionParams {
    case strokeEnd
    case kalman(KalmanPredictorParams)
    case disabled
}

public final class StrokeModeler {
    private var handle: UnsafeMutableRawPointer!

    public init() {
        self.handle = ism_modeler_create()
    }

    deinit {
        if let h = handle {
            ism_modeler_destroy(h)
        }
    }

    public func reset(wobble: WobbleSmootherParams = .init(),
                      position: PositionModelerParams = .init(),
                      sampling: SamplingParams,
                      stylus: StylusStateModelerParams = .init(),
                      prediction: PredictionParams = .strokeEnd) throws {
        var cp = ism_StrokeModelParams(
            wobble: ism_WobbleSmootherParams(
                is_enabled: wobble.isEnabled,
                timeout: wobble.timeout,
                speed_floor: wobble.speedFloor,
                speed_ceiling: wobble.speedCeiling
            ),
            position: ism_PositionModelerParams(
                spring_mass_constant: position.springMassConstant,
                drag_constant: position.dragConstant,
                loop: ism_LoopContractionMitigationParameters(
                    is_enabled: position.loop.isEnabled,
                    speed_lower_bound: position.loop.speedLowerBound,
                    speed_upper_bound: position.loop.speedUpperBound,
                    interpolation_strength_at_speed_lower_bound: position.loop.interpolationStrengthAtSpeedLowerBound,
                    interpolation_strength_at_speed_upper_bound: position.loop.interpolationStrengthAtSpeedUpperBound,
                    min_speed_sampling_window: position.loop.minSpeedSamplingWindow
                )
            ),
            sampling: ism_SamplingParams(
                min_output_rate: sampling.minOutputRate,
                end_of_stroke_stopping_distance: sampling.endOfStrokeStoppingDistance,
                end_of_stroke_max_iterations: sampling.endOfStrokeMaxIterations,
                max_outputs_per_call: sampling.maxOutputsPerCall,
                max_estimated_angle_to_traverse_per_input: sampling.maxEstimatedAngleToTraversePerInput
            ),
            stylus_state: ism_StylusStateModelerParams(
                use_stroke_normal_projection: stylus.useStrokeNormalProjection
            ),
            prediction: ism_PredictionParams(kind: ISM_PREDICTION_STROKE_END,
                                             kalman: ism_KalmanPredictorParams(
                                                process_noise: 0, measurement_noise: 0,
                                                min_stable_iteration: 4, max_time_samples: 20,
                                                min_catchup_velocity: 0, acceleration_weight: 0.5,
                                                jerk_weight: 0.1, prediction_interval: -1,
                                                confidence: ism_KalmanConfidenceParams(
                                                    desired_number_of_samples: 20,
                                                    max_estimation_distance: -1,
                                                    min_travel_speed: -1,
                                                    max_travel_speed: -1,
                                                    max_linear_deviation: -1,
                                                    baseline_linearity_confidence: 0.4
                                                )
                                             ))
        )
        switch prediction {
        case .strokeEnd:
            cp.prediction.kind = ISM_PREDICTION_STROKE_END
        case .disabled:
            cp.prediction.kind = ISM_PREDICTION_DISABLED
        case .kalman(let k):
            cp.prediction.kind = ISM_PREDICTION_KALMAN
            cp.prediction.kalman = ism_KalmanPredictorParams(
                process_noise: k.processNoise,
                measurement_noise: k.measurementNoise,
                min_stable_iteration: k.minStableIteration,
                max_time_samples: k.maxTimeSamples,
                min_catchup_velocity: k.minCatchupVelocity,
                acceleration_weight: k.accelerationWeight,
                jerk_weight: k.jerkWeight,
                prediction_interval: k.predictionInterval,
                confidence: ism_KalmanConfidenceParams(
                    desired_number_of_samples: k.confidence.desiredNumberOfSamples,
                    max_estimation_distance: k.confidence.maxEstimationDistance,
                    min_travel_speed: k.confidence.minTravelSpeed,
                    max_travel_speed: k.confidence.maxTravelSpeed,
                    max_linear_deviation: k.confidence.maxLinearDeviation,
                    baseline_linearity_confidence: k.confidence.baselineLinearityConfidence
                )
            )
        }
        try mapStatus(ism_modeler_reset_with_params(handle, &cp))
    }

    public func reset() throws { try mapStatus(ism_modeler_reset(handle)) }

    public func save() { ism_modeler_save(handle) }
    public func restore() { ism_modeler_restore(handle) }

    public func update(_ input: StrokeInput) throws -> [StrokeSample] {
        var cin = ism_Input(
            event_type: input.eventType.cEvent,
            position: ism_Vec2(x: input.x, y: input.y),
            time: input.time,
            pressure: input.pressure,
            tilt: input.tilt,
            orientation: input.orientation
        )

        // Allocate a reasonably large buffer; the model typically produces a
        // small number of outputs per call.
        let capacity = 1024
        var out = Array<ism_Result>(repeating: ism_Result(
            position: ism_Vec2(x: 0, y: 0),
            velocity: ism_Vec2(x: 0, y: 0),
            acceleration: ism_Vec2(x: 0, y: 0),
            time: 0,
            pressure: -1,
            tilt: -1,
            orientation: -1
        ), count: capacity)

        var produced: Int = 0
        try out.withUnsafeMutableBufferPointer { buf in
            var count: Int = 0
            try mapStatus(ism_modeler_update(handle, &cin, buf.baseAddress, buf.count, &count))
            produced = count
        }

        let n = min(produced, capacity)
        return out.prefix(n).map { r in
            StrokeSample(x: r.position.x, y: r.position.y,
                   vx: r.velocity.x, vy: r.velocity.y,
                   ax: r.acceleration.x, ay: r.acceleration.y,
                   time: r.time, pressure: r.pressure, tilt: r.tilt, orientation: r.orientation)
        }
    }

    public func predict(max: Int = 1024) throws -> [StrokeSample] {
        var out = Array<ism_Result>(repeating: ism_Result(
            position: ism_Vec2(x: 0, y: 0),
            velocity: ism_Vec2(x: 0, y: 0),
            acceleration: ism_Vec2(x: 0, y: 0),
            time: 0,
            pressure: -1,
            tilt: -1,
            orientation: -1
        ), count: max)
        var produced: Int = 0
        try out.withUnsafeMutableBufferPointer { buf in
            var count: Int = 0
            try mapStatus(ism_modeler_predict(handle, buf.baseAddress, buf.count, &count))
            produced = count
        }
        let n = min(produced, max)
        return out.prefix(n).map { r in
            StrokeSample(x: r.position.x, y: r.position.y,
                   vx: r.velocity.x, vy: r.velocity.y,
                   ax: r.acceleration.x, ay: r.acceleration.y,
                   time: r.time, pressure: r.pressure, tilt: r.tilt, orientation: r.orientation)
        }
    }
}
