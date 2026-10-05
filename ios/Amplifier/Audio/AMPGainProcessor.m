#import "AMPGainProcessor.h"
#import "GainDSP.h"
#import <MediaToolbox/MediaToolbox.h>
#include <stdlib.h>

typedef enum { AMPUnsupported, AMPFloat32, AMPInt16, AMPInt32 } AMPSampleKind;
typedef struct {
    AMPGainDSP *dsp;
    AMPSampleKind sampleKind;
} AMPTapContext;

static void tap_initialize(MTAudioProcessingTapRef tap, void *clientInfo, void **storageOut) {
    *storageOut = clientInfo;
}

static void tap_finalize(MTAudioProcessingTapRef tap) {
    AMPTapContext *context = MTAudioProcessingTapGetStorage(tap);
    AMPGainDSPRelease(context->dsp);
    free(context);
}

static void tap_prepare(MTAudioProcessingTapRef tap, CMItemCount maximumFrames,
                        const AudioStreamBasicDescription *format) {
    AMPTapContext *context = MTAudioProcessingTapGetStorage(tap);
    context->sampleKind = AMPUnsupported;
    if (format->mFormatID == kAudioFormatLinearPCM &&
        !(format->mFormatFlags & kAudioFormatFlagIsBigEndian) &&
        (format->mFormatFlags & kAudioFormatFlagIsPacked)) {
        if ((format->mFormatFlags & kAudioFormatFlagIsFloat) && format->mBitsPerChannel == 32) {
            context->sampleKind = AMPFloat32;
        } else if (format->mFormatFlags & kAudioFormatFlagIsSignedInteger) {
            if (format->mBitsPerChannel == 16) context->sampleKind = AMPInt16;
            if (format->mBitsPerChannel == 32) context->sampleKind = AMPInt32;
        }
    }
    if (context->sampleKind == AMPUnsupported) AMPGainDSPMarkUnsupported(context->dsp);
}

static void tap_unprepare(MTAudioProcessingTapRef tap) {}

static void tap_process(MTAudioProcessingTapRef tap, CMItemCount requestedFrames,
                        MTAudioProcessingTapFlags flags, AudioBufferList *buffers,
                        CMItemCount *framesOut, MTAudioProcessingTapFlags *flagsOut) {
    OSStatus result = MTAudioProcessingTapGetSourceAudio(tap, requestedFrames, buffers,
                                                       flagsOut, NULL, framesOut);
    if (result != noErr) {
        *framesOut = 0;
        return;
    }
    AMPTapContext *context = MTAudioProcessingTapGetStorage(tap);
    if (*framesOut <= 0 || context->sampleKind == AMPUnsupported) return;
    for (UInt32 index = 0; index < buffers->mNumberBuffers; index++) {
        AudioBuffer *buffer = &buffers->mBuffers[index];
        size_t bytesPerSample = context->sampleKind == AMPInt16 ? 2 : 4;
        size_t capacity = buffer->mDataByteSize / bytesPerSample;
        size_t samples = MIN(capacity, (size_t)*framesOut * buffer->mNumberChannels);
        switch (context->sampleKind) {
            case AMPFloat32: AMPGainDSPApplyFloat32(context->dsp, buffer->mData, samples); break;
            case AMPInt16: AMPGainDSPApplyInt16(context->dsp, buffer->mData, samples); break;
            case AMPInt32: AMPGainDSPApplyInt32(context->dsp, buffer->mData, samples); break;
            case AMPUnsupported: break;
        }
    }
    AMPGainDSPNoteFrames(context->dsp, (uint64_t)*framesOut);
}

@implementation AMPGainProcessor {
    AMPGainDSP *_dsp;
    NSString *_lastError;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _dsp = AMPGainDSPCreate(6.0f, true);
        if (!_dsp) return nil;
    }
    return self;
}

- (void)dealloc { AMPGainDSPRelease(_dsp); }
- (float)gainDB { return AMPGainDSPGetGain(_dsp); }
- (void)setGainDB:(float)gainDB { AMPGainDSPSetGain(_dsp, gainDB); }
- (BOOL)isEnabled { return AMPGainDSPIsEnabled(_dsp); }
- (void)setEnabled:(BOOL)enabled { AMPGainDSPSetEnabled(_dsp, enabled); }
- (uint64_t)processedFrames { return AMPGainDSPProcessedFrames(_dsp); }
- (BOOL)unsupportedFormatEncountered { return AMPGainDSPHasUnsupportedFormat(_dsp); }
- (NSString *)lastError { return _lastError; }

- (AVAudioMix *)audioMixForTracks:(NSArray<AVAssetTrack *> *)tracks {
    _lastError = nil;
    NSMutableArray<AVAudioMixInputParameters *> *parameters = [NSMutableArray array];
    for (AVAssetTrack *track in tracks) {
        AMPTapContext *context = calloc(1, sizeof(*context));
        if (!context) {
            _lastError = @"Not enough memory to prepare playback.";
            return nil;
        }
        context->dsp = _dsp;
        AMPGainDSPRetain(_dsp);
        MTAudioProcessingTapCallbacks callbacks = {
            .version = kMTAudioProcessingTapCallbacksVersion_0,
            .clientInfo = context,
            .init = tap_initialize,
            .finalize = tap_finalize,
            .prepare = tap_prepare,
            .unprepare = tap_unprepare,
            .process = tap_process,
        };
        MTAudioProcessingTapRef tap = NULL;
        OSStatus result = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                                    kMTAudioProcessingTapCreationFlag_PostEffects, &tap);
        if (result != noErr || !tap) {
            AMPGainDSPRelease(context->dsp);
            free(context);
            _lastError = @"Audio processing is unavailable for this file.";
            return nil;
        }
        AVMutableAudioMixInputParameters *input = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
        input.audioTapProcessor = tap;
        CFRelease(tap);
        [parameters addObject:input];
    }
    AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
    mix.inputParameters = parameters;
    return mix;
}
@end
