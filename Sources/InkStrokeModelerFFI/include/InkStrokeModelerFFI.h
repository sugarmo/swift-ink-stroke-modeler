// C API for ink-stroke-modeler usable from Swift without exposing C++/Abseil
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle to the C++ StrokeModeler instance
typedef void* ism_ModelerHandle;

// Error/status codes (subset mapped from absl::StatusCode)
typedef enum {
  ISM_STATUS_OK = 0,
  ISM_STATUS_INVALID_ARGUMENT = 1,
  ISM_STATUS_FAILED_PRECONDITION = 2,
  ISM_STATUS_OUT_OF_RANGE = 3,
  ISM_STATUS_INTERNAL = 4,
} ism_Status;

// Event type for input
typedef enum {
  ISM_EVENT_DOWN = 0,
  ISM_EVENT_MOVE = 1,
  ISM_EVENT_UP = 2,
} ism_EventType;

typedef struct {
  float x;
  float y;
} ism_Vec2;

// Wobble smoother params
typedef struct {
  bool is_enabled;     // if false, other fields ignored
  double timeout;      // seconds (unit-agnostic)
  float speed_floor;
  float speed_ceiling;
} ism_WobbleSmootherParams;

// Loop contraction mitigation params
typedef struct {
  bool is_enabled;
  float speed_lower_bound;
  float speed_upper_bound;
  float interpolation_strength_at_speed_lower_bound;
  float interpolation_strength_at_speed_upper_bound;
  double min_speed_sampling_window; // seconds (unit-agnostic)
} ism_LoopContractionMitigationParameters;

// Position model params
typedef struct {
  float spring_mass_constant;
  float drag_constant;
  ism_LoopContractionMitigationParameters loop;
} ism_PositionModelerParams;

// Minimal sampling params required by the modeler
typedef struct {
  double min_output_rate;                 // > 0
  float end_of_stroke_stopping_distance;  // > 0
  int32_t end_of_stroke_max_iterations;   // > 0 (<= 1000)
  int32_t max_outputs_per_call;           // > 0 (default 100000)
  double max_estimated_angle_to_traverse_per_input; // radians, (-1 disables)
} ism_SamplingParams;

// Stylus state modeling params
typedef struct {
  bool use_stroke_normal_projection;
} ism_StylusStateModelerParams;

// Prediction params
typedef enum {
  ISM_PREDICTION_STROKE_END = 0,
  ISM_PREDICTION_KALMAN = 1,
  ISM_PREDICTION_DISABLED = 2,
} ism_PredictionKind;

typedef struct {
  int32_t desired_number_of_samples;
  float max_estimation_distance;
  float min_travel_speed;
  float max_travel_speed;
  float max_linear_deviation;
  float baseline_linearity_confidence;
} ism_KalmanConfidenceParams;

typedef struct {
  double process_noise;
  double measurement_noise;
  int32_t min_stable_iteration;
  int32_t max_time_samples;
  float min_catchup_velocity;
  float acceleration_weight;
  float jerk_weight;
  double prediction_interval;
  ism_KalmanConfidenceParams confidence;
} ism_KalmanPredictorParams;

typedef struct {
  ism_PredictionKind kind;
  ism_KalmanPredictorParams kalman; // used when kind == ISM_PREDICTION_KALMAN
} ism_PredictionParams;

// Full parameter set surfaced to Swift
typedef struct {
  ism_WobbleSmootherParams wobble;
  ism_PositionModelerParams position;
  ism_SamplingParams sampling;
  ism_StylusStateModelerParams stylus_state;
  ism_PredictionParams prediction;
} ism_StrokeModelParams;

typedef struct {
  ism_EventType event_type;
  ism_Vec2 position;
  double time;  // unit-agnostic
  float pressure;     // [-1 for unknown]
  float tilt;         // [-1 for unknown]
  float orientation;  // [-1 for unknown]
} ism_Input;

typedef struct {
  ism_Vec2 position;
  ism_Vec2 velocity;
  ism_Vec2 acceleration;
  double time;
  float pressure;
  float tilt;
  float orientation;
} ism_Result;

// Lifecycle
ism_ModelerHandle ism_modeler_create(void);
void ism_modeler_destroy(ism_ModelerHandle m);

// Reset with default parameters for position model, StrokeEnd prediction, and
// wobble smoothing disabled. Sampling must be provided.
ism_Status ism_modeler_reset_with_params(ism_ModelerHandle m,
                                         const ism_StrokeModelParams* params);

// Reset keeping existing parameters.
ism_Status ism_modeler_reset(ism_ModelerHandle m);

// Update: appends newly generated results. Writes up to `max_results` into
// out_results. Sets `out_count` to the total number of results generated (may
// be greater than max_results, in which case results are truncated).
ism_Status ism_modeler_update(ism_ModelerHandle m, const ism_Input* input,
                              ism_Result* out_results, size_t max_results,
                              size_t* out_count);

// Predict: fills results for the current stroke without changing state.
ism_Status ism_modeler_predict(ism_ModelerHandle m, ism_Result* out_results,
                               size_t max_results, size_t* out_count);

// Save/Restore state across updates of an in-progress stroke
void ism_modeler_save(ism_ModelerHandle m);
void ism_modeler_restore(ism_ModelerHandle m);

#ifdef __cplusplus
}  // extern "C"
#endif
