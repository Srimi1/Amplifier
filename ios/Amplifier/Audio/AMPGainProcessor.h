#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Owns UI controls; each processing tap also retains its independent DSP state.
@interface AMPGainProcessor : NSObject
@property(nonatomic) float gainDB;
@property(nonatomic, getter=isEnabled) BOOL enabled;
@property(nonatomic, readonly) uint64_t processedFrames;
@property(nonatomic, readonly) BOOL unsupportedFormatEncountered;
@property(nonatomic, copy, readonly, nullable) NSString *lastError;
- (nullable AVAudioMix *)audioMixForTracks:(NSArray<AVAssetTrack *> *)tracks NS_SWIFT_NAME(audioMix(for:));
@end

NS_ASSUME_NONNULL_END
