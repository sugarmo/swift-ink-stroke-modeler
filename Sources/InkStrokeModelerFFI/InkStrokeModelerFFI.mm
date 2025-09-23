// ObjC++ shim that bridges C API to C++ ink-stroke-modeler
#import <Foundation/Foundation.h>

#import "InkStrokeModelerFFI.h"

#include "params.h"
#include "stroke_modeler.h"
#include "types.h"

using namespace ink::stroke_model;

struct ism_Modeler {
  StrokeModeler impl;
  StrokeModelParams params;
  bool has_params = false;
};

static inline ism_Status to_status(const absl::Status& s) {
  if (s.ok()) return ISM_STATUS_OK;
  switch (s.code()) {
    case absl::StatusCode::kInvalidArgument:
      return ISM_STATUS_INVALID_ARGUMENT;
    case absl::StatusCode::kFailedPrecondition:
      return ISM_STATUS_FAILED_PRECONDITION;
    case absl::StatusCode::kOutOfRange:
      return ISM_STATUS_OUT_OF_RANGE;
    default:
      return ISM_STATUS_INTERNAL;
  }
}

static inline Input to_cpp_input(const ism_Input& in) {
  Input ci;
  switch (in.event_type) {
    case ISM_EVENT_DOWN:
      ci.event_type = Input::EventType::kDown; break;
    case ISM_EVENT_MOVE:
      ci.event_type = Input::EventType::kMove; break;
    case ISM_EVENT_UP:
      ci.event_type = Input::EventType::kUp; break;
  }
  ci.position = Vec2{in.position.x, in.position.y};
  ci.time = Time(in.time);
  ci.pressure = in.pressure;
  ci.tilt = in.tilt;
  ci.orientation = in.orientation;
  return ci;
}

static inline void from_cpp_result(const Result& r, ism_Result* out) {
  out->position = ism_Vec2{r.position.x, r.position.y};
  out->velocity = ism_Vec2{r.velocity.x, r.velocity.y};
  out->acceleration = ism_Vec2{r.acceleration.x, r.acceleration.y};
  out->time = r.time.Value();
  out->pressure = r.pressure;
  out->tilt = r.tilt;
  out->orientation = r.orientation;
}

ism_ModelerHandle ism_modeler_create(void) { return reinterpret_cast<ism_ModelerHandle>(new ism_Modeler()); }

void ism_modeler_destroy(ism_ModelerHandle m) { delete reinterpret_cast<ism_Modeler*>(m); }

static inline void apply_params_defaults(ism_StrokeModelParams const* ip,
                                         StrokeModelParams* out) {
  // Start from library defaults (already set in *out by default constructor),
  // then apply the incoming params.

  // Wobble smoother
  out->wobble_smoother_params.is_enabled = ip->wobble.is_enabled;
  out->wobble_smoother_params.timeout = ink::stroke_model::Duration(ip->wobble.timeout);
  out->wobble_smoother_params.speed_floor = ip->wobble.speed_floor;
  out->wobble_smoother_params.speed_ceiling = ip->wobble.speed_ceiling;

  // Position modeler
  out->position_modeler_params.spring_mass_constant = ip->position.spring_mass_constant;
  out->position_modeler_params.drag_constant = ip->position.drag_constant;
  out->position_modeler_params.loop_contraction_mitigation_params.is_enabled = ip->position.loop.is_enabled;
  out->position_modeler_params.loop_contraction_mitigation_params.speed_lower_bound = ip->position.loop.speed_lower_bound;
  out->position_modeler_params.loop_contraction_mitigation_params.speed_upper_bound = ip->position.loop.speed_upper_bound;
  out->position_modeler_params.loop_contraction_mitigation_params.interpolation_strength_at_speed_lower_bound = ip->position.loop.interpolation_strength_at_speed_lower_bound;
  out->position_modeler_params.loop_contraction_mitigation_params.interpolation_strength_at_speed_upper_bound = ip->position.loop.interpolation_strength_at_speed_upper_bound;
  out->position_modeler_params.loop_contraction_mitigation_params.min_speed_sampling_window = ink::stroke_model::Duration(ip->position.loop.min_speed_sampling_window);

  // Sampling params
  out->sampling_params.min_output_rate = ip->sampling.min_output_rate;
  out->sampling_params.end_of_stroke_stopping_distance = ip->sampling.end_of_stroke_stopping_distance;
  out->sampling_params.end_of_stroke_max_iterations = ip->sampling.end_of_stroke_max_iterations;
  out->sampling_params.max_outputs_per_call = ip->sampling.max_outputs_per_call;
  out->sampling_params.max_estimated_angle_to_traverse_per_input = ip->sampling.max_estimated_angle_to_traverse_per_input;

  // Stylus state
  out->stylus_state_modeler_params.use_stroke_normal_projection = ip->stylus_state.use_stroke_normal_projection;

  // Prediction params
  switch (ip->prediction.kind) {
    case ISM_PREDICTION_STROKE_END:
      out->prediction_params = StrokeEndPredictorParams{};
      break;
    case ISM_PREDICTION_DISABLED:
      out->prediction_params = DisabledPredictorParams{};
      break;
    case ISM_PREDICTION_KALMAN: {
      KalmanPredictorParams kp;
      kp.process_noise = ip->prediction.kalman.process_noise;
      kp.measurement_noise = ip->prediction.kalman.measurement_noise;
      kp.min_stable_iteration = ip->prediction.kalman.min_stable_iteration;
      kp.max_time_samples = ip->prediction.kalman.max_time_samples;
      kp.min_catchup_velocity = ip->prediction.kalman.min_catchup_velocity;
      kp.acceleration_weight = ip->prediction.kalman.acceleration_weight;
      kp.jerk_weight = ip->prediction.kalman.jerk_weight;
      kp.prediction_interval = ink::stroke_model::Duration(ip->prediction.kalman.prediction_interval);
      kp.confidence_params.desired_number_of_samples = ip->prediction.kalman.confidence.desired_number_of_samples;
      kp.confidence_params.max_estimation_distance = ip->prediction.kalman.confidence.max_estimation_distance;
      kp.confidence_params.min_travel_speed = ip->prediction.kalman.confidence.min_travel_speed;
      kp.confidence_params.max_travel_speed = ip->prediction.kalman.confidence.max_travel_speed;
      kp.confidence_params.max_linear_deviation = ip->prediction.kalman.confidence.max_linear_deviation;
      kp.confidence_params.baseline_linearity_confidence = ip->prediction.kalman.confidence.baseline_linearity_confidence;
      out->prediction_params = kp;
      break;
    }
  }
}

ism_Status ism_modeler_reset_with_params(ism_ModelerHandle m,
                                         const ism_StrokeModelParams* params) {
  if (!m || !params) return ISM_STATUS_INVALID_ARGUMENT;
  auto* mm = reinterpret_cast<ism_Modeler*>(m);
  apply_params_defaults(params, &mm->params);
  auto st = ValidateStrokeModelParams(mm->params);
  if (!st.ok()) return to_status(st);
  mm->has_params = true;
  return to_status(mm->impl.Reset(mm->params));
}

ism_Status ism_modeler_reset(ism_ModelerHandle m) {
  if (!m) return ISM_STATUS_INVALID_ARGUMENT;
  auto* mm = reinterpret_cast<ism_Modeler*>(m);
  if (!mm->has_params) return ISM_STATUS_FAILED_PRECONDITION;
  return to_status(mm->impl.Reset());
}

ism_Status ism_modeler_update(ism_ModelerHandle m, const ism_Input* input,
                              ism_Result* out_results, size_t max_results,
                              size_t* out_count) {
  if (!m || !input || !out_count) return ISM_STATUS_INVALID_ARGUMENT;
  auto* mm = reinterpret_cast<ism_Modeler*>(m);
  std::vector<Result> results;
  auto st = mm->impl.Update(to_cpp_input(*input), results);
  if (!st.ok()) {
    *out_count = 0;
    return to_status(st);
  }
  *out_count = results.size();
  if (out_results && max_results > 0) {
    const size_t n = std::min(max_results, results.size());
    for (size_t i = 0; i < n; ++i) from_cpp_result(results[i], &out_results[i]);
  }
  return ISM_STATUS_OK;
}

ism_Status ism_modeler_predict(ism_ModelerHandle m, ism_Result* out_results,
                               size_t max_results, size_t* out_count) {
  if (!m || !out_count) return ISM_STATUS_INVALID_ARGUMENT;
  auto* mm = reinterpret_cast<ism_Modeler*>(m);
  std::vector<Result> results;
  auto st = mm->impl.Predict(results);
  if (!st.ok()) {
    *out_count = 0;
    return to_status(st);
  }
  *out_count = results.size();
  if (out_results && max_results > 0) {
    const size_t n = std::min(max_results, results.size());
    for (size_t i = 0; i < n; ++i) from_cpp_result(results[i], &out_results[i]);
  }
  return ISM_STATUS_OK;
}

void ism_modeler_save(ism_ModelerHandle m) { if (m) reinterpret_cast<ism_Modeler*>(m)->impl.Save(); }
void ism_modeler_restore(ism_ModelerHandle m) { if (m) reinterpret_cast<ism_Modeler*>(m)->impl.Restore(); }
