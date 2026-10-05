#include "GainDSP.h"
#include <assert.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

static void *change_controls(void *context) {
    AMPGainDSP *dsp = context;
    for (int i = 0; i < 20000; i++) {
        AMPGainDSPSetGain(dsp, (float)(i % 16));
        AMPGainDSPSetEnabled(dsp, i % 2 == 0);
    }
    return NULL;
}

int main(void) {
    AMPGainDSP *dsp = AMPGainDSPCreate(6, true);
    assert(dsp);
    float quiet[] = {0.1f, -0.1f, 0};
    AMPGainDSPApplyFloat32(dsp, quiet, 3);
    assert(fabsf(quiet[0] - 0.1f * powf(10, 6.0f / 20)) < 1e-6f);
    assert(quiet[1] == -quiet[0] && quiet[2] == 0);
    AMPGainDSPSetGain(dsp, 0);
    float original[] = {0.95f, -0.95f};
    AMPGainDSPApplyFloat32(dsp, original, 2);
    assert(original[0] == 0.95f && original[1] == -0.95f);
    AMPGainDSPSetGain(dsp, 15);
    AMPGainDSPSetEnabled(dsp, false);
    AMPGainDSPApplyFloat32(dsp, original, 2);
    assert(original[0] == 0.95f && original[1] == -0.95f);
    AMPGainDSPSetEnabled(dsp, true);
    float loud[] = {1, -1, 100, -100, NAN, INFINITY};
    AMPGainDSPApplyFloat32(dsp, loud, 6);
    for (int i = 0; i < 6; i++) assert(isfinite(loud[i]) && fabsf(loud[i]) <= 1);
    assert(loud[0] == -loud[1] && loud[4] == 0 && loud[5] == 0);
    AMPGainDSPSetGain(dsp, 6);
    int16_t shortSamples[] = {1000, -1000, INT16_MAX, INT16_MIN};
    int32_t longSamples[] = {1000000, -1000000, INT32_MAX, INT32_MIN};
    AMPGainDSPApplyInt16(dsp, shortSamples, 4);
    AMPGainDSPApplyInt32(dsp, longSamples, 4);
    assert(shortSamples[0] == 1995 && shortSamples[1] == -1995);
    assert(labs((long)longSamples[0] - 1995262) <= 1 && longSamples[1] == -longSamples[0]);
    assert(shortSamples[2] > 0 && shortSamples[3] < 0 && longSamples[2] > 0 && longSamples[3] < 0);
    AMPGainDSPRetain(dsp);
    AMPGainDSPRelease(dsp);
    AMPGainDSPSetGain(dsp, 99);
    assert(AMPGainDSPGetGain(dsp) == 15);
    AMPGainDSPSetGain(dsp, -99);
    assert(AMPGainDSPGetGain(dsp) == 0);
    AMPGainDSPSetGain(dsp, NAN);
    assert(AMPGainDSPGetGain(dsp) == 0);
    pthread_t controls;
    assert(pthread_create(&controls, NULL, change_controls, dsp) == 0);
    for (int i = 0; i < 20000; i++) {
        float samples[] = {0.2f, -0.2f, 0.9f, -0.9f};
        AMPGainDSPApplyFloat32(dsp, samples, 4);
        for (int sample = 0; sample < 4; sample++) assert(isfinite(samples[sample]) && fabsf(samples[sample]) <= 1);
    }
    assert(pthread_join(controls, NULL) == 0);
    AMPGainDSPRelease(dsp);
    puts("Gain, bypass, limiter, integer range, lifetime, and concurrent-control checks passed.");
}
