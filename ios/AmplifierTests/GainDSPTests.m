#import <XCTest/XCTest.h>
#import "GainDSP.h"
#import <math.h>

@interface GainDSPTests : XCTestCase
@end

@implementation GainDSPTests
- (void)testSixDecibelsAmplifiesQuietSamples {
    AMPGainDSP *dsp = AMPGainDSPCreate(6, true);
    float samples[] = {0.1f, -0.1f, 0};
    AMPGainDSPApplyFloat32(dsp, samples, 3);
    XCTAssertEqualWithAccuracy(samples[0], 0.1 * pow(10, 6.0 / 20), 0.000001);
    XCTAssertEqualWithAccuracy(samples[1], -samples[0], 0.000001);
    XCTAssertEqual(samples[2], 0);
    AMPGainDSPRelease(dsp);
}
- (void)testZeroGainAndDisabledAreExactBypasses {
    AMPGainDSP *dsp = AMPGainDSPCreate(0, true);
    float samples[] = {0.95f, -0.95f};
    AMPGainDSPApplyFloat32(dsp, samples, 2);
    XCTAssertEqual(samples[0], 0.95f);
    XCTAssertEqual(samples[1], -0.95f);
    AMPGainDSPSetGain(dsp, 15);
    AMPGainDSPSetEnabled(dsp, false);
    AMPGainDSPApplyFloat32(dsp, samples, 2);
    XCTAssertEqual(samples[0], 0.95f);
    XCTAssertEqual(samples[1], -0.95f);
    AMPGainDSPRelease(dsp);
}
- (void)testLimiterBoundsLoudSamplesAndPreservesPolarity {
    AMPGainDSP *dsp = AMPGainDSPCreate(15, true);
    float samples[] = {1, -1, 0.5f, -0.5f, INFINITY, NAN};
    AMPGainDSPApplyFloat32(dsp, samples, 6);
    for (int i = 0; i < 6; i++) {
        XCTAssertTrue(isfinite(samples[i]));
        XCTAssertLessThanOrEqual(fabsf(samples[i]), 1);
    }
    XCTAssertGreaterThan(samples[0], 0);
    XCTAssertEqualWithAccuracy(samples[0], -samples[1], 0.000001);
    XCTAssertEqual(samples[4], 0);
    XCTAssertEqual(samples[5], 0);
    AMPGainDSPRelease(dsp);
}
- (void)testIntegerProcessingAmplifiesWithoutOverflow {
    AMPGainDSP *dsp = AMPGainDSPCreate(6, true);
    int16_t shortSamples[] = {1000, -1000, INT16_MAX, INT16_MIN};
    int32_t longSamples[] = {1000000, -1000000, INT32_MAX, INT32_MIN};
    AMPGainDSPApplyInt16(dsp, shortSamples, 4);
    AMPGainDSPApplyInt32(dsp, longSamples, 4);
    XCTAssertEqualWithAccuracy(shortSamples[0], 1995, 1);
    XCTAssertEqualWithAccuracy(shortSamples[1], -1995, 1);
    XCTAssertEqualWithAccuracy(longSamples[0], 1995262, 1);
    XCTAssertEqualWithAccuracy(longSamples[1], -1995262, 1);
    XCTAssertGreaterThan(shortSamples[2], 0);
    XCTAssertLessThan(shortSamples[3], 0);
    XCTAssertGreaterThan(longSamples[2], 0);
    XCTAssertLessThan(longSamples[3], 0);
    AMPGainDSPRelease(dsp);
}
- (void)testGainClampsAndTapRetainsStateAfterOwnerRelease {
    AMPGainDSP *dsp = AMPGainDSPCreate(99, true);
    XCTAssertEqual(AMPGainDSPGetGain(dsp), 15);
    AMPGainDSPRetain(dsp);
    AMPGainDSPRelease(dsp);
    AMPGainDSPSetGain(dsp, -5);
    XCTAssertEqual(AMPGainDSPGetGain(dsp), 0);
    AMPGainDSPSetGain(dsp, NAN);
    XCTAssertEqual(AMPGainDSPGetGain(dsp), 0);
    AMPGainDSPRelease(dsp);
}
@end
