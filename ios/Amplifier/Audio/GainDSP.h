#ifndef AMPLIFIER_GAIN_DSP_H
#define AMPLIFIER_GAIN_DSP_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AMPGainDSP AMPGainDSP;

AMPGainDSP *AMPGainDSPCreate(float gainDB, bool enabled);
void AMPGainDSPRetain(AMPGainDSP *dsp);
void AMPGainDSPRelease(AMPGainDSP *dsp);
void AMPGainDSPSetGain(AMPGainDSP *dsp, float gainDB);
float AMPGainDSPGetGain(const AMPGainDSP *dsp);
void AMPGainDSPSetEnabled(AMPGainDSP *dsp, bool enabled);
bool AMPGainDSPIsEnabled(const AMPGainDSP *dsp);

// No allocation, locks, or Objective-C/Swift calls on the render thread.
// Off and 0 dB are exact bypasses. Positive gain has a soft knee at 0.8 FS.
void AMPGainDSPApplyFloat32(const AMPGainDSP *dsp, float *samples, size_t count);
void AMPGainDSPApplyInt16(const AMPGainDSP *dsp, int16_t *samples, size_t count);
void AMPGainDSPApplyInt32(const AMPGainDSP *dsp, int32_t *samples, size_t count);

void AMPGainDSPNoteFrames(AMPGainDSP *dsp, uint64_t frames);
uint64_t AMPGainDSPProcessedFrames(const AMPGainDSP *dsp);
void AMPGainDSPMarkUnsupported(AMPGainDSP *dsp);
bool AMPGainDSPHasUnsupportedFormat(const AMPGainDSP *dsp);

#ifdef __cplusplus
}
#endif
#endif
