#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

+ (NSString *)openCVVersion;

// Existing video analysis method
+ (void)analyzeVideo:(NSString *)inputPath outputPath:(NSString *)outputPath;

// Real-time processing methods
+ (NSDictionary *)detectTargetsInFrame:(id)frame goalRegion:(CGRect)goalRegion;
+ (NSDictionary * _Nullable)detectBallInFrame:(id)frame;
+ (NSDictionary * _Nullable)detectSoccerBall:(id)frame; // Simple soccer ball detection
+ (BOOL)detectImpactWithBall:(NSDictionary *)ball targets:(NSArray<NSDictionary *> *)targets goalRegion:(CGRect)goalRegion;
+ (void)resetTracking;

// Enhanced backend processing methods
+ (NSDictionary *)analyzeFramePerformance:(id)frame;
+ (NSArray<NSDictionary *> *)detectMotionInFrame:(id)frame;
+ (NSDictionary *)getTrackingStatistics;
+ (void)setProcessingMode:(NSString *)mode; // "fast", "accurate", "balanced"
+ (void)calibrateForLighting:(id)frame;

// Ball detection methods
// FFT-based detection method commented out:
// + (NSDictionary * _Nullable)detectBallByFFT:(id)frame; // FFT-based detection (commented out)
+ (NSDictionary * _Nullable)detectBallUnified:(id)frame; // New unified detection method

@end

NS_ASSUME_NONNULL_END

