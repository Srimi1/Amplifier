#include "GainDSP.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>

struct AMPGainDSP {
    atomic_uint references;
    _Atomic(float) gainDB;
    _Atomic(float) linearGain;
    atomic_bool enabled;
    atomic_ullong processedFrames;
    atomic_bool unsupportedFormat;
};

static float clamp_gain(float gainDB) {
    return isfinite(gainDB) ? fminf(15.0f, fmaxf(0.0f, gainDB)) : 0.0f;
}

AMPGainDSP *AMPGainDSPCreate(float gainDB, bool enabled) {
    AMPGainDSP *dsp = calloc(1, sizeof(*dsp));
    if (!dsp) return NULL;
    float clamped = clamp_gain(gainDB);
    atomic_init(&dsp->references, 1);
    atomic_init(&dsp->gainDB, clamped);
    atomic_init(&dsp->linearGain, powf(10.0f, clamped / 20.0f));
    atomic_init(&dsp->enabled, enabled);
    atomic_init(&dsp->processedFrames, 0);
    atomic_init(&dsp->unsupportedFormat, false);
    return dsp;
}

void AMPGainDSPRetain(AMPGainDSP *dsp) {
    if (dsp) atomic_fetch_add_explicit(&dsp->references, 1, memory_order_relaxed);
}

void AMPGainDSPRelease(AMPGainDSP *dsp) {
    if (dsp && atomic_fetch_sub_explicit(&dsp->references, 1, memory_order_acq_rel) == 1) {
        free(dsp);
    }
}

void AMPGainDSPSetGain(AMPGainDSP *dsp, float gainDB) {
    if (!dsp) return;
    float clamped = clamp_gain(gainDB);
    atomic_store_explicit(&dsp->gainDB, clamped, memory_order_relaxed);
    atomic_store_explicit(&dsp->linearGain, powf(10.0f, clamped / 20.0f), memory_order_relaxed);
}

float AMPGainDSPGetGain(const AMPGainDSP *dsp) {
    return dsp ? atomic_load_explicit(&dsp->gainDB, memory_order_relaxed) : 0.0f;
}

void AMPGainDSPSetEnabled(AMPGainDSP *dsp, bool enabled) {
    if (dsp) atomic_store_explicit(&dsp->enabled, enabled, memory_order_relaxed);
}

bool AMPGainDSPIsEnabled(const AMPGainDSP *dsp) {
    return dsp && atomic_load_explicit(&dsp->enabled, memory_order_relaxed);
}

static float processing_gain(const AMPGainDSP *dsp) {
    return AMPGainDSPIsEnabled(dsp) ? atomic_load_explicit(&dsp->linearGain, memory_order_relaxed) : 1.0f;
}

static double process_sample(double sample, double gain) {
    if (!isfinite(sample)) return 0.0;
    double boosted = sample * gain;
    double magnitude = fabs(boosted);
    if (magnitude <= 0.8) return boosted;
    // Continuous slope at the knee, with a bounded output instead of hard clipping.
    return copysign(0.8 + 0.2 * tanh((magnitude - 0.8) / 0.2), boosted);
}

void AMPGainDSPApplyFloat32(const AMPGainDSP *dsp, float *samples, size_t count) {
    float gain = processing_gain(dsp);
    if (!samples || gain == 1.0f) return;
    for (size_t index = 0; index < count; index++) {
        samples[index] = (float)process_sample(samples[index], gain);
    }
}

void AMPGainDSPApplyInt16(const AMPGainDSP *dsp, int16_t *samples, size_t count) {
    float gain = processing_gain(dsp);
    if (!samples || gain == 1.0f) return;
    for (size_t index = 0; index < count; index++) {
        long value = lround(process_sample(samples[index] / 32768.0, gain) * 32768.0);
        samples[index] = (int16_t)(value > INT16_MAX ? INT16_MAX : (value < INT16_MIN ? INT16_MIN : value));
    }
}

void AMPGainDSPApplyInt32(const AMPGainDSP *dsp, int32_t *samples, size_t count) {
    float gain = processing_gain(dsp);
    if (!samples || gain == 1.0f) return;
    for (size_t index = 0; index < count; index++) {
        long long value = llround(process_sample(samples[index] / 2147483648.0, gain) * 2147483648.0);
        samples[index] = (int32_t)(value > INT32_MAX ? INT32_MAX : (value < INT32_MIN ? INT32_MIN : value));
    }
}

void AMPGainDSPNoteFrames(AMPGainDSP *dsp, uint64_t frames) {
    if (dsp) atomic_fetch_add_explicit(&dsp->processedFrames, frames, memory_order_relaxed);
}

uint64_t AMPGainDSPProcessedFrames(const AMPGainDSP *dsp) {
    return dsp ? atomic_load_explicit(&dsp->processedFrames, memory_order_relaxed) : 0;
}

void AMPGainDSPMarkUnsupported(AMPGainDSP *dsp) {
    if (dsp) atomic_store_explicit(&dsp->unsupportedFormat, true, memory_order_relaxed);
}

bool AMPGainDSPHasUnsupportedFormat(const AMPGainDSP *dsp) {
    return dsp && atomic_load_explicit(&dsp->unsupportedFormat, memory_order_relaxed);
}
