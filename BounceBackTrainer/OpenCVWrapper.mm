#import "OpenCVWrapper.h"
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

// Workaround Apple 'NO' macro conflict with OpenCV stitching
#ifdef NO
    #undef NO
    #define __RESTORE_NO_MACRO__
#endif

#import <opencv2/opencv.hpp>

#ifdef __RESTORE_NO_MACRO__
    #define NO 0
    #undef __RESTORE_NO_MACRO__
#endif

// Color threshold constants
namespace ColorThresholds {
    // Base HSV ranges
    const cv::Scalar YELLOW_LOW(20, 100, 100);
    const cv::Scalar YELLOW_HIGH(35, 255, 255);
    
    // Red target HSV ranges (low and high)
    const cv::Scalar RED_LOW_1(0, 100, 100);
    const cv::Scalar RED_HIGH_1(10, 255, 255);
    const cv::Scalar RED_LOW_2(160, 100, 100);
    const cv::Scalar RED_HIGH_2(179, 255, 255);
    
    // Pink tape HSV range
    const cv::Scalar PINK_LOW(140, 100, 100);
    const cv::Scalar PINK_HIGH(170, 255, 255);
    
    // Ball detection color ranges
    const cv::Scalar WHITE_LOW(0, 0, 200);
    const cv::Scalar WHITE_HIGH(180, 30, 255);
    const cv::Scalar ORANGE_LOW(10, 100, 100);
    const cv::Scalar ORANGE_HIGH(20, 255, 255);
    
    // Adaptive HSV ranges for outdoor lighting
    struct AdaptiveRanges {
        cv::Scalar yellowLow, yellowHigh;
        cv::Scalar redLow1, redHigh1, redLow2, redHigh2;
        cv::Scalar pinkLow, pinkHigh;
    };
    
    // Get adaptive HSV ranges based on average brightness
    static AdaptiveRanges getAdaptiveRanges(float avgBrightness) {
        AdaptiveRanges ranges;
        
        // Adjust thresholds based on brightness
        if (avgBrightness > 150) { // Bright outdoor lighting
            ranges.yellowLow = cv::Scalar(10, 50, 80);    // Much more aggressive for outdoor
            ranges.yellowHigh = cv::Scalar(45, 255, 255);
            ranges.redLow1 = cv::Scalar(0, 70, 70);       // Much more aggressive for outdoor
            ranges.redHigh1 = cv::Scalar(15, 255, 255);
            ranges.redLow2 = cv::Scalar(150, 70, 70);     // Much more aggressive for outdoor
            ranges.redHigh2 = cv::Scalar(180, 255, 255);
            ranges.pinkLow = cv::Scalar(140, 60, 80);     // More aggressive for outdoor
            ranges.pinkHigh = cv::Scalar(170, 255, 255);
        } else if (avgBrightness > 100) { // Moderate lighting
            ranges.yellowLow = cv::Scalar(15, 70, 100);
            ranges.yellowHigh = cv::Scalar(40, 255, 255);
            ranges.redLow1 = cv::Scalar(0, 80, 80);
            ranges.redHigh1 = cv::Scalar(12, 255, 255);
            ranges.redLow2 = cv::Scalar(155, 80, 80);
            ranges.redHigh2 = cv::Scalar(179, 255, 255);
            ranges.pinkLow = cv::Scalar(140, 80, 100);
            ranges.pinkHigh = cv::Scalar(170, 255, 255);
        } else { // Low lighting (indoor)
            ranges.yellowLow = YELLOW_LOW;
            ranges.yellowHigh = YELLOW_HIGH;
            ranges.redLow1 = RED_LOW_1;
            ranges.redHigh1 = RED_HIGH_1;
            ranges.redLow2 = RED_LOW_2;
            ranges.redHigh2 = RED_HIGH_2;
            ranges.pinkLow = PINK_LOW;
            ranges.pinkHigh = PINK_HIGH;
        }
        
        return ranges;
    }
}

// Structure to hold target information
struct Target {
    cv::Rect boundingBox;
    bool isCircular;
    int targetNumber;
    cv::Point center;
    double radius;  // Only used for circular targets
    std::vector<cv::Vec3f> circles;  // For storing circular patterns
    int quadrant;
    double confidence;
    
    Target() : boundingBox(-1, -1, -1, -1), isCircular(false), targetNumber(0), 
               center(-1, -1), radius(0), quadrant(0), confidence(0.0) {}
};

// Ball tracking structure for real-time processing
struct BallTracker {
    cv::Point position;
    cv::Point2d velocity;
    double velocityMagnitude;
    bool isDetected;
    int framesDetected;
    int framesWithoutDetection;
    double confidence;
    
    BallTracker() : position(-1, -1), velocity(0, 0), velocityMagnitude(0), 
                   isDetected(false), framesDetected(0), framesWithoutDetection(0), confidence(0.0) {}
};

// Global tracking state for real-time processing
static BallTracker ballTracker;
static std::vector<Target> persistentTargets;
static int frameCounter = 0;

// Shared persistent state for real-time and video analysis
static std::vector<Target> lastDetectedTargets;
static cv::Rect lastGoalRegion;
static int lastFrameWidth = 0;
static int lastFrameHeight = 0;

// Ball detection filtering state
static int lastValidFrame = -20;
static int cooldownFrames = 15;                // Delay between allowed detections
static const double minVelocity = 3.5;         // Require more motion
static const double minConfidenceThreshold = 0.6; // Increased from 0.5 to 0.6
static cv::Point lastBallPosition(-1, -1);
static int lastFrameNumber = 0;
static double lastVelocity = 0.0;

// Additional filtering for false positive reduction
static const int MIN_BALL_AREA = 200;          // Reduced minimum area for smaller balls
static const int MAX_BALL_AREA = 50000;        // Increased maximum area for larger balls
static const double MIN_CIRCULARITY = 0.5;     // Reduced circularity requirement (was too strict)
static const double MIN_CONTRAST = 15.0;       // Reduced contrast requirement for low-light conditions
static const int MIN_CONSECUTIVE_DETECTIONS = 3; // Require multiple consecutive detections
static std::vector<cv::Point> recentBallPositions;
static const int MAX_POSITION_HISTORY = 5;

// Forward declarations for helper functions
static cv::Point detectBallByShape(const cv::Mat& frame);
static cv::Point detectBallByColor(const cv::Mat& frame);
static cv::Point detectBallByMotion(const cv::Mat& gray, cv::Ptr<cv::BackgroundSubtractorMOG2> pMOG2);
static bool detectSoccerBall(const cv::Mat& frame, cv::Point& ballCenter, float& ballRadius);
static std::vector<Target> detectTargets(const cv::Mat& frame, std::vector<cv::Rect>& tapeRects);
static std::vector<Target> detectCircularTargets(const cv::Mat& frame, 
                                                const ColorThresholds::AdaptiveRanges& adaptiveRanges);
static std::vector<Target> detectTargetsByContours(const cv::Mat& frame, 
                                                  const ColorThresholds::AdaptiveRanges& adaptiveRanges);
static bool isColorMatch(const cv::Mat& hsv, const cv::Point& center, int radius, 
                        const cv::Scalar& low, const cv::Scalar& high, double minPercentage);
static void drawDetectedTarget(cv::Mat& frame, const Target& target);
static cv::Rect getSafeROI(const cv::Mat& frame, const cv::Point& center, int radius);
static int getQuadrant(const cv::Point& pt, const cv::Rect& goalBoundary);
static cv::Mat enhanceContrast(const cv::Mat& frame);
static float calculateAverageBrightness(const cv::Mat& frame);

// New helper functions for real-time processing
static cv::Mat uiImageToMat(UIImage* image);
static NSDictionary* targetToDictionary(const Target& target);
static NSDictionary* ballToDictionary(const BallTracker& tracker);
static cv::Rect cgRectToCvRect(CGRect cgRect, const cv::Mat& frame);

// Helper to run the same detection pipeline as analyzeVideo, but for a single frame
static void analyzeSingleFrame(const cv::Mat& frame, cv::Rect goalRegion, std::vector<Target>& outTargets, BallTracker& outBallTracker) {
    std::vector<cv::Rect> tapeRects;
    std::vector<Target> targets;
    cv::Rect goalBoundary = goalRegion;
    bool goalBoundaryLocked = (goalRegion.width > 0 && goalRegion.height > 0);

    // Detect targets and goal boundary
    targets = detectTargets(frame, tapeRects);
    if (!tapeRects.empty() && !goalBoundaryLocked) {
        goalBoundary = tapeRects[0];
        goalBoundaryLocked = true;
    }
    if (goalBoundaryLocked && !targets.empty()) {
        for (auto& target : targets) {
            if (target.quadrant == 0) {
                cv::Point center = target.isCircular ? target.center :
                    cv::Point(target.boundingBox.x + target.boundingBox.width / 2,
                              target.boundingBox.y + target.boundingBox.height / 2);
                target.quadrant = getQuadrant(center, goalBoundary);
            }
        }
    }
    outTargets = targets;

    // Ball detection (use shape, then motion, then color)
    cv::Point detectedPosition(-1, -1);
    std::string detectionMethod = "None";
    detectedPosition = detectBallByShape(frame);
    if (detectedPosition.x >= 0) {
        detectionMethod = "Shape";
    }
    if (detectedPosition.x < 0) {
        cv::Mat gray;
        cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
        cv::GaussianBlur(gray, gray, cv::Size(9, 9), 2);
        cv::Point motionBall = detectBallByMotion(gray, cv::createBackgroundSubtractorMOG2());
        if (motionBall.x >= 0) {
            detectedPosition = motionBall;
            detectionMethod = "Motion";
        }
    }
    if (detectedPosition.x < 0) {
        cv::Point colorBall = detectBallByColor(frame);
        if (colorBall.x >= 0) {
            detectedPosition = colorBall;
            detectionMethod = "Color";
        }
    }
    // Update ball tracker with stricter validation
    if (detectedPosition.x >= 0 && detectedPosition.y >= 0) {
        // Add to position history for consistency checking
        recentBallPositions.push_back(detectedPosition);
        if (recentBallPositions.size() > MAX_POSITION_HISTORY) {
            recentBallPositions.erase(recentBallPositions.begin());
        }
        
        // Check if we have enough consecutive detections
        if (recentBallPositions.size() >= MIN_CONSECUTIVE_DETECTIONS) {
            // Check if positions are consistent (not too far apart)
            bool isConsistent = true;
            for (size_t i = 1; i < recentBallPositions.size(); ++i) {
                double distance = cv::norm(recentBallPositions[i] - recentBallPositions[i-1]);
                if (distance > 100) { // If positions are too far apart, reject
                    isConsistent = false;
                    break;
                }
            }
            
            if (isConsistent) {
                outBallTracker.position = detectedPosition;
                outBallTracker.isDetected = true;
                outBallTracker.framesDetected++;
                outBallTracker.framesWithoutDetection = 0;
                NSLog(@"[OpenCV] Ball detection validated with %zu consecutive positions", recentBallPositions.size());
            } else {
                outBallTracker.framesWithoutDetection++;
                NSLog(@"[OpenCV] Ball detection rejected - inconsistent positions");
            }
        } else {
            // Not enough consecutive detections yet
            outBallTracker.framesWithoutDetection++;
            NSLog(@"[OpenCV] Ball detection pending - need %d consecutive detections, have %zu", 
                  MIN_CONSECUTIVE_DETECTIONS, recentBallPositions.size());
        }
    } else {
        outBallTracker.framesWithoutDetection++;
        if (outBallTracker.framesWithoutDetection > 10) {
            outBallTracker.isDetected = false;
            recentBallPositions.clear(); // Clear history when ball is lost
        }
    }

    int currentFrame = frameCounter;
    double velocity = 0.0;
    if (ballTracker.position.x >= 0 && ballTracker.position.y >= 0 && detectedPosition.x >= 0 && detectedPosition.y >= 0) {
        velocity = cv::norm(cv::Point2d(detectedPosition.x - ballTracker.position.x, detectedPosition.y - ballTracker.position.y));
    }
    if (outBallTracker.isDetected && (velocity < 2.0 || (currentFrame - lastValidFrame < cooldownFrames))) {
        outBallTracker.isDetected = false;
    } else if (outBallTracker.isDetected) {
        lastValidFrame = currentFrame;
        ballTracker.position = detectedPosition;
        ballTracker.velocity = cv::Point2d(detectedPosition.x - ballTracker.position.x, detectedPosition.y - ballTracker.position.y);
        ballTracker.velocityMagnitude = velocity;
    }
    NSLog(@"[OpenCV] Ball velocity: %f, Detected: %d", velocity, outBallTracker.isDetected);

    // Compute ball confidence
    double ballConfidence = 0.0;
    if (outBallTracker.isDetected) {
        ballConfidence = std::min(1.0, std::min(detectedPosition.x / static_cast<double>(frame.cols), detectedPosition.y / static_cast<double>(frame.rows)));
        ballConfidence = std::min(ballConfidence, velocity / 10.0);
    }
    outBallTracker.confidence = ballConfidence;
    // Reject weak detections
    if (outBallTracker.confidence < minConfidenceThreshold) {
        NSLog(@"[OpenCV] Rejected ball due to low confidence: %.2f", outBallTracker.confidence);
        outBallTracker.isDetected = false;
    }
}

@implementation OpenCVWrapper

+ (NSString *)openCVVersion {
    std::string version = CV_VERSION;
    return [NSString stringWithUTF8String:version.c_str()];
}

// Refactored real-time detection methods
// Now use the same detection pipeline as analyzeVideo
+ (NSDictionary *)detectTargetsInFrame:(UIImage *)frame goalRegion:(CGRect)goalRegion {
    if (!frame) return @{};
    cv::Mat cvFrame = uiImageToMat(frame);
    if (cvFrame.empty()) return @{};
    cv::Rect cvGoalRegion = cgRectToCvRect(goalRegion, cvFrame);
    if (cvGoalRegion.width <= 0 || cvGoalRegion.height <= 0) {
        cvGoalRegion = cv::Rect(0, 0, cvFrame.cols, cvFrame.rows);
    }
    lastFrameWidth = cvFrame.cols;
    lastFrameHeight = cvFrame.rows;
    lastGoalRegion = cvGoalRegion;
    std::vector<cv::Rect> tapeRects;
    std::vector<Target> targets = detectTargets(cvFrame, tapeRects);
    lastDetectedTargets = targets;
    NSMutableArray *targetArray = [NSMutableArray array];
    for (const auto& target : targets) {
        [targetArray addObject:targetToDictionary(target)];
    }
    CGRect tapeRegion = CGRectZero;
    if (!tapeRects.empty()) {
        cv::Rect t = tapeRects[0];
        tapeRegion = CGRectMake(t.x, t.y, t.width, t.height);
    }
    return @{ @"targets": targetArray, @"tapeRegion": [NSValue valueWithCGRect:tapeRegion] };
}

+ (NSDictionary * _Nullable)detectBallInFrame:(UIImage *)frame {
    if (!frame) return nil;
    cv::Mat cvFrame = uiImageToMat(frame);
    if (cvFrame.empty()) return nil;
    
    NSLog(@"[OpenCV] detectBallInFrame called with frame size: %dx%d", cvFrame.cols, cvFrame.rows);
    
    // Try simple soccer ball detection first
    cv::Point ballCenter;
    float ballRadius = 0.0f;
    bool found = detectSoccerBall(cvFrame, ballCenter, ballRadius);
    
    if (found) {
        NSLog(@"[OpenCV] Soccer ball found at (%d, %d) with radius %.1f", ballCenter.x, ballCenter.y, ballRadius);
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"x"] = @(ballCenter.x);
        result[@"y"] = @(ballCenter.y);
        result[@"radius"] = @(ballRadius);
        result[@"isDetected"] = @(YES);
        result[@"confidence"] = @(1.0);
        return result;
    }
    
    // Fallback to original method if soccer ball detection fails
    cv::Rect cvGoalRegion = lastGoalRegion;
    if (cvGoalRegion.width <= 0 || cvGoalRegion.height <= 0) {
        cvGoalRegion = cv::Rect(0, 0, cvFrame.cols, cvFrame.rows);
    }
    std::vector<Target> targets = lastDetectedTargets;
    BallTracker tracker;
    analyzeSingleFrame(cvFrame, cvGoalRegion, targets, tracker);
    if (tracker.position.x >= 0 && tracker.position.y >= 0) {
        NSLog(@"[OpenCV] Fallback: Ball detected at (%d, %d)", tracker.position.x, tracker.position.y);
        NSLog(@"[Ball Detection] Velocity: %.2f, Confidence: %.2f, Frames: %d", 
              tracker.velocityMagnitude, tracker.confidence, tracker.framesDetected);
    }
    return ballToDictionary(tracker);
}

+ (NSDictionary * _Nullable)detectSoccerBall:(UIImage *)frame {
    if (!frame) return nil;
    cv::Mat cvFrame = uiImageToMat(frame);
    if (cvFrame.empty()) return nil;
    
    NSLog(@"[OpenCV] detectSoccerBallInFrame called with frame size: %dx%d", cvFrame.cols, cvFrame.rows);
    
    cv::Point ballCenter;
    float ballRadius = 0.0f;
    bool found = detectSoccerBall(cvFrame, ballCenter, ballRadius);
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (found) {
        // Draw blue circle around detected ball
        cv::circle(cvFrame, ballCenter, (int)ballRadius, cv::Scalar(255, 0, 0), 3);
        result[@"x"] = @(ballCenter.x);
        result[@"y"] = @(ballCenter.y);
        result[@"radius"] = @(ballRadius);
        result[@"isDetected"] = @(YES);
        result[@"confidence"] = @(1.0);
        NSLog(@"[OpenCV] Soccer ball detected at (%d, %d) with radius %.1f", ballCenter.x, ballCenter.y, ballRadius);
    } else {
        NSLog(@"[OpenCV] No soccer ball detected");
        result[@"isDetected"] = @(NO);
        result[@"confidence"] = @(0.0);
        result[@"x"] = @(-1);
        result[@"y"] = @(-1);
        result[@"radius"] = @(0.0);
    }
    
    return result;
}

+ (BOOL)detectImpactWithBall:(NSDictionary *)ball targets:(NSArray<NSDictionary *> *)targets goalRegion:(CGRect)goalRegion {
    if (!ball || !targets) return NO;
    
    // Extract ball position
    NSNumber *ballX = ball[@"x"];
    NSNumber *ballY = ball[@"y"];
    if (!ballX || !ballY) return NO;
    
    cv::Point ballPosition([ballX intValue], [ballY intValue]);
    
    // Check if ball is in goal region
    if (goalRegion.size.width > 0 && goalRegion.size.height > 0) {
        if (ballPosition.x < goalRegion.origin.x || 
            ballPosition.x > goalRegion.origin.x + goalRegion.size.width ||
            ballPosition.y < goalRegion.origin.y || 
            ballPosition.y > goalRegion.origin.y + goalRegion.size.height) {
            return NO; // Ball not in goal region
        }
    }
    
    // Check for collision with any target
    for (NSDictionary *target in targets) {
        NSNumber *targetX = target[@"centerX"];
        NSNumber *targetY = target[@"centerY"];
        NSNumber *targetRadius = target[@"radius"];
        
        if (targetX && targetY && targetRadius) {
            cv::Point targetCenter([targetX intValue], [targetY intValue]);
            double radius = [targetRadius doubleValue];
            
            double distance = cv::norm(ballPosition - targetCenter);
            if (distance <= radius + 10) { // 10 pixel tolerance
                return YES; // Impact detected
            }
        }
    }
    
    return NO;
}

+ (void)resetTracking {
    ballTracker = BallTracker();
    persistentTargets.clear();
    frameCounter = 0;
    recentBallPositions.clear(); // Clear position history
    NSLog(@"[OpenCV] Tracking reset - cleared ball position history");
}

// Enhanced backend processing methods

// Global processing mode and statistics
static NSString *processingMode = @"balanced";
static NSMutableDictionary *trackingStats = [NSMutableDictionary dictionary];

+ (NSDictionary *)analyzeFramePerformance:(UIImage *)frame {
    if (!frame) return @{};
    
    cv::Mat cvFrame = uiImageToMat(frame);
    if (cvFrame.empty()) return @{};
    
    NSMutableDictionary *performance = [NSMutableDictionary dictionary];
    
    // Measure processing time
    auto start = std::chrono::high_resolution_clock::now();
    
    // Perform basic analysis
    float avgBrightness = calculateAverageBrightness(cvFrame);
    cv::Mat enhanced = enhanceContrast(cvFrame);
    
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
    
    performance[@"processingTime"] = @(duration.count());
    performance[@"averageBrightness"] = @(avgBrightness);
    performance[@"frameWidth"] = @(cvFrame.cols);
    performance[@"frameHeight"] = @(cvFrame.rows);
    performance[@"processingMode"] = processingMode;
    
    return performance;
}

+ (NSArray<NSDictionary *> *)detectMotionInFrame:(UIImage *)frame {
    if (!frame) return @[];
    
    cv::Mat cvFrame = uiImageToMat(frame);
    if (cvFrame.empty()) return @[];
    
    cv::Mat gray;
    cv::cvtColor(cvFrame, gray, cv::COLOR_BGR2GRAY);
    cv::GaussianBlur(gray, gray, cv::Size(9, 9), 2);
    
    // Use background subtraction for motion detection
    static cv::Ptr<cv::BackgroundSubtractorMOG2> pMOG2 = cv::createBackgroundSubtractorMOG2();
    cv::Mat fgMask;
    pMOG2->apply(gray, fgMask);
    
    // Morphological operations to reduce noise
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(7, 7));
    cv::morphologyEx(fgMask, fgMask, cv::MORPH_OPEN, kernel);
    cv::morphologyEx(fgMask, fgMask, cv::MORPH_CLOSE, kernel);
    
    // Find motion contours
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(fgMask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    
    NSMutableArray *motionRegions = [NSMutableArray array];
    
    for (const auto& contour : contours) {
        double area = cv::contourArea(contour);
        if (area > 100 && area < 10000) { // Filter by size
            cv::Rect rect = cv::boundingRect(contour);
            cv::Point center(rect.x + rect.width / 2, rect.y + rect.height / 2);
            
            NSDictionary *motionRegion = @{
                @"x": @(center.x),
                @"y": @(center.y),
                @"width": @(rect.width),
                @"height": @(rect.height),
                @"area": @(area),
                @"confidence": @(std::min(1.0, area / 1000.0))
            };
            [motionRegions addObject:motionRegion];
        }
    }
    
    return motionRegions;
}

+ (NSDictionary *)getTrackingStatistics {
    NSMutableDictionary *stats = [NSMutableDictionary dictionary];
    
    // Ball tracking stats
    stats[@"ballDetected"] = @(ballTracker.isDetected);
    stats[@"ballFramesDetected"] = @(ballTracker.framesDetected);
    stats[@"ballFramesWithoutDetection"] = @(ballTracker.framesWithoutDetection);
    stats[@"ballConfidence"] = @(ballTracker.confidence);
    stats[@"ballVelocityMagnitude"] = @(ballTracker.velocityMagnitude);
    
    // Target stats
    stats[@"targetsDetected"] = @(lastDetectedTargets.size());
    stats[@"frameCounter"] = @(frameCounter);
    stats[@"processingMode"] = processingMode;
    
    // Performance stats
    [stats addEntriesFromDictionary:trackingStats];
    
    return stats;
}

+ (void)setProcessingMode:(NSString *)mode {
    if ([mode isEqualToString:@"fast"] || 
        [mode isEqualToString:@"accurate"] || 
        [mode isEqualToString:@"balanced"]) {
        processingMode = [mode copy];
        NSLog(@"[OpenCV] Processing mode set to: %@", processingMode);
    }
}

+ (void)calibrateForLighting:(UIImage *)frame {
    if (!frame) return;
    
    cv::Mat cvFrame = uiImageToMat(frame);
    if (cvFrame.empty()) return;
    
    float avgBrightness = calculateAverageBrightness(cvFrame);
    
    // Update tracking stats with lighting info
    trackingStats[@"lastCalibrationBrightness"] = @(avgBrightness);
    trackingStats[@"lastCalibrationTime"] = @([[NSDate date] timeIntervalSince1970]);
    
    NSLog(@"[OpenCV] Lighting calibration: brightness = %.2f", avgBrightness);
    
    // Adjust processing parameters based on lighting
    if (avgBrightness > 150) {
        [self setProcessingMode:@"fast"]; // Bright outdoor lighting
    } else if (avgBrightness < 80) {
        [self setProcessingMode:@"accurate"]; // Low lighting, need more accuracy
    } else {
        [self setProcessingMode:@"balanced"]; // Moderate lighting
    }
}

// Existing video analysis method
+ (void)analyzeVideo:(NSString *)inputPath outputPath:(NSString *)outputPath {
    if (!inputPath || !outputPath) {
        NSLog(@"[OpenCV] Nil input or output path received");
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            std::string input = [inputPath UTF8String];
            std::string output = [outputPath UTF8String];
            
            cv::VideoCapture cap(input);
            if (!cap.isOpened()) {
                NSLog(@"Error: Could not open input video.");
                return;
            }
            
            int width = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_WIDTH));
            int height = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_HEIGHT));
            double fps = cap.get(cv::CAP_PROP_FPS);
            
            NSLog(@"[OpenCV] Video properties - Width: %d, Height: %d, FPS: %f", width, height, fps);
            
            // Target and goal boundary detection variables
            std::vector<Target> targets;
            std::vector<cv::Rect> tapeRects;
            cv::Rect goalBoundary(0, 0, width, height); // Default to full frame
            bool goalBoundaryLocked = false;
            bool targetsDetected = false;
            int targetDetectionAttempts = 0;
            const int MAX_DETECTION_ATTEMPTS = 30;
            
            // Try 'MJPG' codec for .avi compatibility
            cv::VideoWriter writer(output, cv::VideoWriter::fourcc('M','J','P','G'), fps, cv::Size(width, height));
            if (!writer.isOpened()) {
                NSLog(@"Error: Could not create output video writer. Path: %s, Size: %dx%d, FPS: %f", output.c_str(), width, height, fps);
                return;
            }
            NSLog(@"[OpenCV] Output writer created. Path: %s, Size: %dx%d, FPS: %f", output.c_str(), width, height, fps);
            
            // Background Subtractor for motion detection
            cv::Ptr<cv::BackgroundSubtractorMOG2> pMOG2 = cv::createBackgroundSubtractorMOG2();
            
            // Ball tracking variables
            cv::Point lastBallPosition(-1, -1);
            bool ballDetected = false;
            int framesWithoutBall = 0;
            const int MAX_FRAMES_WITHOUT_BALL = 30;
            
            cv::Mat frame, outputFrame;
            cv::Mat prevGray;
            int frameCount = 0;
            
            NSLog(@"[OpenCV] Input path: %s", input.c_str());
            
            while (cap.read(frame)) {
                frameCount++;
                outputFrame = frame.clone();
                
                // Detect targets and goal boundary in first few frames
                if (!targetsDetected && targetDetectionAttempts < MAX_DETECTION_ATTEMPTS) {
                    std::vector<Target> detectedTargets = detectTargets(frame, tapeRects);
                    
                    // Lock goal boundary if found
                    if (!tapeRects.empty() && !goalBoundaryLocked) {
                        goalBoundary = tapeRects[0];
                        goalBoundaryLocked = true;
                        NSLog(@"[OpenCV] Goal boundary locked.");
                    }

                    // Populate targets list if not already done
                    if (targets.empty() && !detectedTargets.empty()) {
                        targets = detectedTargets;
                        NSLog(@"[OpenCV] %zu targets found.", targets.size());
                    }
                    
                    // If we have BOTH the boundary AND the targets, we can finalize scene setup
                    if (goalBoundaryLocked && !targets.empty()) {
                        // Assign quadrants to targets using the goal boundary
                        for (auto& target : targets) {
                            if (target.quadrant == 0) { // Assign only once
                                cv::Point center = target.isCircular ? target.center :
                                    cv::Point(target.boundingBox.x + target.boundingBox.width / 2,
                                              target.boundingBox.y + target.boundingBox.height / 2);
                                target.quadrant = getQuadrant(center, goalBoundary);
                                NSLog(@"[OpenCV] Target %d assigned to quadrant %d", target.targetNumber, target.quadrant);
                            }
                        }
                        targetsDetected = true; // Stop further scene detection
                        NSLog(@"[OpenCV] Scene setup complete.");
                    }
                    targetDetectionAttempts++;
                }
                
                // Convert to grayscale for motion detection
                cv::Mat gray;
                cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
                cv::GaussianBlur(gray, gray, cv::Size(9, 9), 2);
                
                cv::Point currentBallPosition(-1, -1);
                std::string detectionMethod = "None";
                
                // Try multiple detection methods in order of preference
                // 1. Shape detection (most accurate)
                currentBallPosition = detectBallByShape(frame);
                if (currentBallPosition.x >= 0) {
                    detectionMethod = "Shape";
                }

                // 2. Motion detection (if shape fails)
                if (currentBallPosition.x < 0) {
                    cv::Point motionBall = detectBallByMotion(gray, pMOG2);
                    if (motionBall.x >= 0) {
                        currentBallPosition = motionBall;
                        detectionMethod = "Motion";
                    }
                }
                
                // 3. Color detection (last resort)
                if (currentBallPosition.x < 0) {
                    cv::Point colorBall = detectBallByColor(frame);
                    if (colorBall.x >= 0) {
                        currentBallPosition = colorBall;
                        detectionMethod = "Color";
                    }
                }
                
                // Update ball tracking
                if (currentBallPosition.x >= 0 && currentBallPosition.y >= 0) {
                    ballDetected = true;
                    framesWithoutBall = 0;
                    lastBallPosition = currentBallPosition;
                } else {
                    framesWithoutBall++;
                    if (framesWithoutBall > MAX_FRAMES_WITHOUT_BALL) {
                        ballDetected = false;
                    }
                }
                
                // Draw tape frame and targets
                if (goalBoundaryLocked) {
                    cv::rectangle(outputFrame, goalBoundary, cv::Scalar(0, 255, 0), 2);
                }
                
                for (const auto& target : targets) {
                    drawDetectedTarget(outputFrame, target);
                }
                
                // Draw ball and check hits
                if (currentBallPosition.x >= 0 && currentBallPosition.y >= 0) {
                    cv::circle(outputFrame, currentBallPosition, 8, cv::Scalar(0, 0, 255), -1);
                    cv::putText(outputFrame, "BALL (" + detectionMethod + ")",
                              cv::Point(currentBallPosition.x + 10, currentBallPosition.y - 10),
                              cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(0, 0, 255), 2);
                    
                    // Find closest target hit
                    double minDistance = 1e9;
                    int bestTargetIndex = -1;

                    for (size_t i = 0; i < targets.size(); ++i) {
                        const auto& target = targets[i];
                        bool isHit = false;
                        double distance;

                        if (target.isCircular) {
                            distance = cv::norm(currentBallPosition - target.center);
                            isHit = distance <= target.radius;
                        } else {
                            isHit = target.boundingBox.contains(currentBallPosition);
                            cv::Point center(target.boundingBox.x + target.boundingBox.width / 2,
                                             target.boundingBox.y + target.boundingBox.height / 2);
                            distance = cv::norm(currentBallPosition - center);
                        }

                        if (isHit && distance < minDistance) {
                            minDistance = distance;
                            bestTargetIndex = i;
                        }
                    }
                    
                    // Annotate best-matching target
                    if (bestTargetIndex >= 0) {
                        const auto& bestTarget = targets[bestTargetIndex];
                        cv::putText(outputFrame, "HIT TARGET " + std::to_string(bestTarget.targetNumber) + "!",
                            cv::Point(30, 30 + bestTarget.targetNumber * 40),
                            cv::FONT_HERSHEY_SIMPLEX, 1.0, cv::Scalar(0, 255, 255), 3);
                    }
                }
                
                // Update status display
                cv::putText(outputFrame, "Targets Detected: " + std::to_string(targets.size()),
                           cv::Point(10, height - 80), cv::FONT_HERSHEY_SIMPLEX, 0.5,
                           cv::Scalar(255, 255, 255), 1);
                
                // Draw frame info
                cv::putText(outputFrame, "Frame: " + std::to_string(frameCount), 
                            cv::Point(10, height - 60), cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(255, 255, 255), 1);
                cv::putText(outputFrame, "Ball Detected: " + std::string(ballDetected ? "YES" : "NO"), 
                            cv::Point(10, height - 40), cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(255, 255, 255), 1);
                cv::putText(outputFrame, "Detection: " + detectionMethod, 
                            cv::Point(10, height - 20), cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(255, 255, 255), 1);
                
                // Display lighting and adaptive threshold info
                if (targetsDetected) {
                    float avgBrightness = calculateAverageBrightness(frame);
                    std::string lightingCondition = (avgBrightness > 150) ? "Bright Outdoor" : 
                                                   (avgBrightness > 100) ? "Moderate" : "Indoor";
                    cv::putText(outputFrame, "Lighting: " + lightingCondition + " (" + std::to_string((int)avgBrightness) + ")",
                                cv::Point(width - 300, height - 20), cv::FONT_HERSHEY_SIMPLEX, 0.4, cv::Scalar(255, 255, 255), 1);
                }
                
                // Draw quadrant lines for debugging if goal is locked
                if (goalBoundaryLocked) {
                    int midX = goalBoundary.x + goalBoundary.width / 2;
                    int midY = goalBoundary.y + goalBoundary.height / 2;
                    cv::line(outputFrame, cv::Point(midX, goalBoundary.y), 
                            cv::Point(midX, goalBoundary.y + goalBoundary.height), cv::Scalar(255, 255, 255), 1);
                    cv::line(outputFrame, cv::Point(goalBoundary.x, midY), 
                            cv::Point(goalBoundary.x + goalBoundary.width, midY), cv::Scalar(255, 255, 255), 1);
                }
                
                prevGray = gray.clone();
                writer.write(outputFrame);
                
                // Log progress every 100 frames
                if (frameCount % 100 == 0) {
                    NSLog(@"[OpenCV] Processed %d frames", frameCount);
                }
            }
            
            cap.release();
            writer.release();
            NSLog(@"[OpenCV] Video processing completed. Total frames: %d", frameCount);
        }
    });
}

+ (NSDictionary * _Nullable)detectBallByFFT:(UIImage *)frame {
    if (!frame) return nil;
    cv::Mat cvFrame = uiImageToMat(frame);
    if (cvFrame.empty()) return nil;

    // Convert to grayscale
    cv::Mat gray;
    cv::cvtColor(cvFrame, gray, cv::COLOR_BGR2GRAY);

    // Apply Gaussian blur to reduce noise
    cv::GaussianBlur(gray, gray, cv::Size(5, 5), 0);

    // Expand to optimal size for DFT
    int m = cv::getOptimalDFTSize(gray.rows);
    int n = cv::getOptimalDFTSize(gray.cols);
    cv::Mat padded;
    cv::copyMakeBorder(gray, padded, 0, m - gray.rows, 0, n - gray.cols, cv::BORDER_CONSTANT, cv::Scalar::all(0));

    // Make planes to hold the complex image
    cv::Mat planes[] = {cv::Mat_<float>(padded), cv::Mat::zeros(padded.size(), CV_32F)};
    cv::Mat complexI;
    cv::merge(planes, 2, complexI);

    // DFT
    cv::dft(complexI, complexI);

    // Compute magnitude and switch to logarithmic scale
    cv::split(complexI, planes);
    cv::magnitude(planes[0], planes[1], planes[0]);
    cv::Mat magI = planes[0];
    magI += cv::Scalar::all(1);
    cv::log(magI, magI);

    // Crop and rearrange quadrants
    magI = magI(cv::Rect(0, 0, magI.cols & -2, magI.rows & -2));
    int cx = magI.cols / 2;
    int cy = magI.rows / 2;
    cv::Mat q0(magI, cv::Rect(0, 0, cx, cy));
    cv::Mat q1(magI, cv::Rect(cx, 0, cx, cy));
    cv::Mat q2(magI, cv::Rect(0, cy, cx, cy));
    cv::Mat q3(magI, cv::Rect(cx, cy, cx, cy));
    cv::Mat tmp;
    q0.copyTo(tmp); q3.copyTo(q0); tmp.copyTo(q3);
    q1.copyTo(tmp); q2.copyTo(q1); tmp.copyTo(q2);

    // Normalize
    cv::normalize(magI, magI, 0, 1, cv::NORM_MINMAX);

    // Apply adaptive frequency domain filtering
    cv::Mat filter = cv::Mat::zeros(magI.size(), CV_32F);
    int filterRadius = std::min(cx, cy) / 6; // Smaller filter for more precision
    cv::circle(filter, cv::Point(cx, cy), filterRadius, cv::Scalar(1.0), -1);
    cv::multiply(magI, filter, magI);

    // Detect circular symmetry in frequency domain with adaptive parameters
    cv::Mat mag8U;
    magI.convertTo(mag8U, CV_8U, 255);

    std::vector<cv::Vec3f> circles;
    // Adaptive parameters based on image size
    int minRadius = std::max(5, (int)(std::min(cvFrame.rows, cvFrame.cols) * 0.02));
    int maxRadius = std::min(150, (int)(std::min(cvFrame.rows, cvFrame.cols) * 0.3));
    
    cv::HoughCircles(mag8U, circles, cv::HOUGH_GRADIENT, 1, mag8U.rows/8, 120, 25, minRadius, maxRadius);

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    // Multi-layer validation for ball detection
    bool validBallDetected = false;
    double bestConfidence = 0.0;
    cv::Vec3f bestCircle;
    
    if (!circles.empty()) {
        // Check multiple circles and find the best candidate
        for (const auto& circle : circles) {
            int x = (int)circle[0];
            int y = (int)circle[1];
            int radius = (int)circle[2];
            
            // Layer 1: Basic position and size validation
            if (x >= 0 && x < cvFrame.cols && y >= 0 && y < cvFrame.rows && 
                radius >= minRadius && radius <= maxRadius) {
                
                // Layer 2: ROI validation
                cv::Rect roi = cv::Rect(std::max(0, x - radius), std::max(0, y - radius),
                                      std::min(2 * radius, cvFrame.cols - std::max(0, x - radius)),
                                      std::min(2 * radius, cvFrame.rows - std::max(0, y - radius)));
                
                if (roi.width > 0 && roi.height > 0) {
                    cv::Mat roiMat = gray(roi);
                    
                    // Layer 3: Contrast and texture analysis
                    cv::Scalar meanVal, stdDevVal;
                    cv::meanStdDev(roiMat, meanVal, stdDevVal);
                    double stdDev = stdDevVal[0];
                    
                    // Layer 4: Circularity check using contour analysis
                    cv::Mat roiBinary;
                    cv::threshold(roiMat, roiBinary, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);
                    
                    std::vector<std::vector<cv::Point>> contours;
                    cv::findContours(roiBinary, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
                    
                    double circularity = 0.0;
                    if (!contours.empty()) {
                        // Find the largest contour
                        auto largestContour = std::max_element(contours.begin(), contours.end(),
                            [](const std::vector<cv::Point>& a, const std::vector<cv::Point>& b) {
                                return cv::contourArea(a) < cv::contourArea(b);
                            });
                        
                        if (largestContour != contours.end()) {
                            double area = cv::contourArea(*largestContour);
                            double perimeter = cv::arcLength(*largestContour, true);
                            if (perimeter > 0) {
                                circularity = 4 * M_PI * area / (perimeter * perimeter);
                            }
                        }
                    }
                    
                    // Layer 5: Multi-criteria scoring
                    double contrastScore = std::min(1.0, stdDev / 50.0); // Normalize contrast
                    double sizeScore = 1.0 - std::abs(radius - (minRadius + maxRadius) / 2.0) / ((maxRadius - minRadius) / 2.0);
                    double circularityScore = circularity;
                    
                    // Combined confidence score
                    double confidence = (contrastScore * 0.4 + sizeScore * 0.3 + circularityScore * 0.3);
                    
                    // Debug logging
                    NSLog(@"[OpenCV][FFT] Circle candidate: pos(%d,%d) radius=%d, stdDev=%.2f, circularity=%.3f, confidence=%.3f", 
                          x, y, radius, stdDev, circularity, confidence);
                    
                    // Final validation: stricter thresholds to reduce false positives
                    if (stdDev > MIN_CONTRAST && circularity > MIN_CIRCULARITY && confidence > 0.5) {
                        // Additional validation: check if this position is consistent with recent detections
                        bool isConsistent = true;
                        if (!recentBallPositions.empty()) {
                            double avgDistance = 0.0;
                            int validPositions = 0;
                            for (const auto& pos : recentBallPositions) {
                                double distance = cv::norm(cv::Point2d(x, y) - cv::Point2d(pos.x, pos.y));
                                if (distance < 100) { // Within 100 pixels
                                    avgDistance += distance;
                                    validPositions++;
                                }
                            }
                            if (validPositions > 0) {
                                avgDistance /= validPositions;
                                isConsistent = (avgDistance < 50); // Must be close to recent positions
                            }
                        }
                        
                        if (isConsistent) {
                            NSLog(@"[OpenCV][FFT] Valid ball candidate found!");
                            if (confidence > bestConfidence) {
                                bestConfidence = confidence;
                                bestCircle = circle;
                                validBallDetected = true;
                            }
                        } else {
                            NSLog(@"[OpenCV][FFT] Rejected: position inconsistent with recent detections");
                        }
                    } else {
                        NSLog(@"[OpenCV][FFT] Rejected: stdDev=%.2f (need>%.1f), circularity=%.3f (need>%.3f), confidence=%.3f (need>0.5)", 
                              stdDev, MIN_CONTRAST, circularity, MIN_CIRCULARITY, confidence);
                    }
                }
            }
        }
        
        // Use the best detected circle
        if (validBallDetected) {
            int x = (int)bestCircle[0];
            int y = (int)bestCircle[1];
            int radius = (int)bestCircle[2];
            
            // Add to position history for consistency checking
            recentBallPositions.push_back(cv::Point(x, y));
            if (recentBallPositions.size() > MAX_POSITION_HISTORY) {
                recentBallPositions.erase(recentBallPositions.begin());
            }
            
            result[@"x"] = @(x);
            result[@"y"] = @(y);
            result[@"radius"] = @(radius);
            result[@"isDetected"] = @(YES);
            result[@"confidence"] = @(bestConfidence);
            NSLog(@"[OpenCV][FFT] Ball detected at (%d, %d) with radius %d, confidence %.3f, history size: %zu", 
                  x, y, radius, bestConfidence, recentBallPositions.size());
        }
    }
    
    if (!validBallDetected) {
        result[@"isDetected"] = @(NO);
        result[@"confidence"] = @(0.0);
        result[@"x"] = @(-1);
        result[@"y"] = @(-1);
        result[@"radius"] = @(0);
        NSLog(@"[OpenCV][FFT] No valid ball detected in frequency domain");
    }
    
    return result;
}

// New unified ball detection method that tries multiple approaches
+ (NSDictionary * _Nullable)detectBallUnified:(UIImage *)frame {
    if (!frame) {
        NSLog(@"[OpenCV] ERROR: detectBallUnified called with nil frame");
        return nil;
    }
    
    cv::Mat cvFrame = uiImageToMat(frame);
    if (cvFrame.empty()) {
        NSLog(@"[OpenCV] ERROR: Failed to convert UIImage to cv::Mat");
        return nil;
    }
    
    NSLog(@"[OpenCV] detectBallUnified called with frame size: %dx%d", cvFrame.cols, cvFrame.rows);
    
    NSMutableDictionary *bestResult = [NSMutableDictionary dictionary];
    double bestConfidence = 0.0;
    NSString *bestMethod = @"none";
    
    // Method 1: Try soccer ball detection first (most reliable for soccer balls)
    @try {
        cv::Point ballCenter;
        float ballRadius = 0.0f;
        bool soccerBallFound = detectSoccerBall(cvFrame, ballCenter, ballRadius);
        
        if (soccerBallFound && ballCenter.x >= 0 && ballCenter.y >= 0) {
            double confidence = 0.9; // High confidence for soccer ball detection
            NSLog(@"[OpenCV] Soccer ball detection succeeded at (%d, %d) with radius %.1f", 
                  ballCenter.x, ballCenter.y, ballRadius);
            
            if (confidence > bestConfidence) {
                bestConfidence = confidence;
                bestMethod = @"soccer";
                bestResult[@"x"] = @(ballCenter.x);
                bestResult[@"y"] = @(ballCenter.y);
                bestResult[@"radius"] = @(ballRadius);
                bestResult[@"isDetected"] = @(YES);
                bestResult[@"confidence"] = @(confidence);
                bestResult[@"method"] = @"soccer";
            }
        } else {
            NSLog(@"[OpenCV] Soccer ball detection failed or invalid coordinates");
        }
    } @catch (NSException *exception) {
        NSLog(@"[OpenCV] ERROR: Soccer ball detection failed with exception: %@", exception.reason);
    }
    
    // Method 2: Try shape detection (HoughCircles) if soccer ball detection failed
    if (bestConfidence < 0.7) {
        @try {
            cv::Point shapeBall = detectBallByShape(cvFrame);
            if (shapeBall.x >= 0) {
                double confidence = 0.6; // Medium confidence for shape detection
                NSLog(@"[OpenCV] Shape detection succeeded at (%d, %d)", shapeBall.x, shapeBall.y);
                
                if (confidence > bestConfidence) {
                    bestConfidence = confidence;
                    bestMethod = @"shape";
                    bestResult[@"x"] = @(shapeBall.x);
                    bestResult[@"y"] = @(shapeBall.y);
                    bestResult[@"radius"] = @(20.0); // Default radius for shape detection
                    bestResult[@"isDetected"] = @(YES);
                    bestResult[@"confidence"] = @(confidence);
                    bestResult[@"method"] = @"shape";
                }
            } else {
                NSLog(@"[OpenCV] Shape detection failed or invalid coordinates");
            }
        } @catch (NSException *exception) {
            NSLog(@"[OpenCV] ERROR: Shape detection failed with exception: %@", exception.reason);
        }
    }
    
    // Method 3: Try color detection if other methods failed
    if (bestConfidence < 0.5) {
        @try {
            cv::Point colorBall = detectBallByColor(cvFrame);
            if (colorBall.x >= 0) {
                double confidence = 0.4; // Lower confidence for color detection
                NSLog(@"[OpenCV] Color detection succeeded at (%d, %d)", colorBall.x, colorBall.y);
                
                if (confidence > bestConfidence) {
                    bestConfidence = confidence;
                    bestMethod = @"color";
                    bestResult[@"x"] = @(colorBall.x);
                    bestResult[@"y"] = @(colorBall.y);
                    bestResult[@"radius"] = @(15.0); // Default radius for color detection
                    bestResult[@"isDetected"] = @(YES);
                    bestResult[@"confidence"] = @(confidence);
                    bestResult[@"method"] = @"color";
                }
            } else {
                NSLog(@"[OpenCV] Color detection failed or invalid coordinates");
            }
        } @catch (NSException *exception) {
            NSLog(@"[OpenCV] ERROR: Color detection failed with exception: %@", exception.reason);
        }
    }
    
    // Method 4: Try motion detection as last resort
    if (bestConfidence < 0.3) {
        @try {
            cv::Mat gray;
            cv::cvtColor(cvFrame, gray, cv::COLOR_BGR2GRAY);
            // Initialize background subtractor for motion detection
            static cv::Ptr<cv::BackgroundSubtractorMOG2> pMOG2 = cv::createBackgroundSubtractorMOG2();
            cv::Point motionBall = detectBallByMotion(gray, pMOG2);
            if (motionBall.x >= 0) {
                double confidence = 0.3; // Lowest confidence for motion detection
                NSLog(@"[OpenCV] Motion detection succeeded at (%d, %d)", motionBall.x, motionBall.y);
                
                if (confidence > bestConfidence) {
                    bestConfidence = confidence;
                    bestMethod = @"motion";
                    bestResult[@"x"] = @(motionBall.x);
                    bestResult[@"y"] = @(motionBall.y);
                    bestResult[@"radius"] = @(10.0); // Default radius for motion detection
                    bestResult[@"isDetected"] = @(YES);
                    bestResult[@"confidence"] = @(confidence);
                    bestResult[@"method"] = @"motion";
                }
            } else {
                NSLog(@"[OpenCV] Motion detection failed or invalid coordinates");
            }
        } @catch (NSException *exception) {
            NSLog(@"[OpenCV] ERROR: Motion detection failed with exception: %@", exception.reason);
        }
    }
    
    // Return result
    if (bestConfidence > 0.0) {
        NSLog(@"[OpenCV] Unified detection succeeded using %@ method with confidence %.3f", 
              bestMethod, bestConfidence);
        return bestResult;
    } else {
        NSLog(@"[OpenCV] Unified detection failed - no ball found with any method");
        NSMutableDictionary *noResult = [NSMutableDictionary dictionary];
        noResult[@"isDetected"] = @(NO);
        noResult[@"confidence"] = @(0.0);
        noResult[@"x"] = @(-1);
        noResult[@"y"] = @(-1);
        noResult[@"radius"] = @(0);
        noResult[@"method"] = @"none";
        return noResult;
    }
}

@end

// Helper function to convert UIImage to cv::Mat
static cv::Mat uiImageToMat(UIImage* image) {
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;
    
    cv::Mat mat(rows, cols, CV_8UC4);
    
    CGContextRef contextRef = CGBitmapContextCreate(mat.data, cols, rows, 8, mat.step[0], colorSpace, kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault);
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    
    // Convert from RGBA to BGR (OpenCV format)
    cv::cvtColor(mat, mat, cv::COLOR_RGBA2BGR);
    
    return mat;
}

// Helper function to convert Target struct to NSDictionary
static NSDictionary* targetToDictionary(const Target& target) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"centerX"] = @(target.center.x);
    dict[@"centerY"] = @(target.center.y);
    dict[@"radius"] = @(target.radius);
    dict[@"targetNumber"] = @(target.targetNumber);
    dict[@"isCircular"] = @(target.isCircular);
    dict[@"quadrant"] = @(target.quadrant);
    dict[@"confidence"] = @(target.confidence);
    return dict;
}

// Helper function to convert BallTracker struct to NSDictionary
static NSDictionary* ballToDictionary(const BallTracker& tracker) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"x"] = @(tracker.position.x);
    dict[@"y"] = @(tracker.position.y);
    dict[@"velocityX"] = @(tracker.velocity.x);
    dict[@"velocityY"] = @(tracker.velocity.y);
    dict[@"velocityMagnitude"] = @(tracker.velocityMagnitude);
    dict[@"isDetected"] = @(tracker.isDetected);
    dict[@"confidence"] = @(tracker.confidence);
    return dict;
}

// Helper function to convert CGRect to cv::Rect
static cv::Rect cgRectToCvRect(CGRect cgRect, const cv::Mat& frame) {
    if (cgRect.size.width <= 0 || cgRect.size.height <= 0) {
        return cv::Rect(0, 0, frame.cols, frame.rows);
    }
    
    // Convert from UIKit coordinates to OpenCV coordinates
    int x = static_cast<int>(cgRect.origin.x);
    int y = static_cast<int>(cgRect.origin.y);
    int width = static_cast<int>(cgRect.size.width);
    int height = static_cast<int>(cgRect.size.height);
    
    // Ensure bounds
    x = std::max(0, std::min(x, frame.cols - 1));
    y = std::max(0, std::min(y, frame.rows - 1));
    width = std::min(width, frame.cols - x);
    height = std::min(height, frame.rows - y);
    
    return cv::Rect(x, y, width, height);
}

// Helper function to detect all targets
static std::vector<Target> detectTargets(const cv::Mat& frame, std::vector<cv::Rect>& tapeRects) {
    std::vector<Target> targets;
    
    // Enhance contrast for better detection in varying lighting
    cv::Mat enhancedFrame = enhanceContrast(frame);
    
    // Calculate average brightness for adaptive thresholds
    float avgBrightness = calculateAverageBrightness(frame);
    auto adaptiveRanges = ColorThresholds::getAdaptiveRanges(avgBrightness);
    
    // Detect circular targets (yellow and red) with adaptive ranges
    std::vector<Target> circularTargets = detectCircularTargets(enhancedFrame, adaptiveRanges);
    targets.insert(targets.end(), circularTargets.begin(), circularTargets.end());
    
    // Detect fluorescent pink tape if not already found
    if (tapeRects.empty()) {
        cv::Mat hsv;
        cv::cvtColor(enhancedFrame, hsv, cv::COLOR_BGR2HSV);
        
        cv::Mat pinkMask;
        cv::inRange(hsv, adaptiveRanges.pinkLow, adaptiveRanges.pinkHigh, pinkMask);

        // Clean up mask to remove noise and connect tape segments
        cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(7, 7));
        cv::morphologyEx(pinkMask, pinkMask, cv::MORPH_CLOSE, kernel);
        cv::morphologyEx(pinkMask, pinkMask, cv::MORPH_OPEN, kernel);

        std::vector<std::vector<cv::Point>> pinkContours;
        cv::findContours(pinkMask, pinkContours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

        std::vector<cv::Point> allPinkPoints;
        for (const auto& contour : pinkContours) {
            double area = cv::contourArea(contour);
            if (area > 300) { // Filter out small noise
                allPinkPoints.insert(allPinkPoints.end(), contour.begin(), contour.end());
            }
        }
        
        if (allPinkPoints.size() > 1) {
            std::vector<cv::Point> hull;
            cv::convexHull(allPinkPoints, hull);
            double hullArea = cv::contourArea(hull);

            if (hullArea > 5000) { // Ensure the detected frame is large enough
                cv::Rect rect = cv::boundingRect(hull);
                tapeRects.push_back(rect);
            }
        }
    }

    return targets;
}

// Helper function to detect circular targets (yellow and red)
static std::vector<Target> detectCircularTargets(const cv::Mat& frame, 
                                                const ColorThresholds::AdaptiveRanges& adaptiveRanges) {
    std::vector<Target> targets;
    cv::Mat gray, hsv;
    cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
    cv::cvtColor(frame, hsv, cv::COLOR_BGR2HSV);
    
    // Pre-process the image with more aggressive blur for outdoor conditions
    cv::GaussianBlur(gray, gray, cv::Size(11, 11), 3);
    
    // More aggressive circle detection parameters for outdoor conditions
    std::vector<cv::Vec3f> circles;
    cv::HoughCircles(gray, circles, cv::HOUGH_GRADIENT, 1,
                     gray.rows/6,  // Reduced minimum distance between centers
                     120, 35,      // Lower Canny edge detection parameters for outdoor
                     30, 120       // Expanded radius range
    );
    
    if (!circles.empty()) {
        int targetNumber = 1;
        
        for (const auto& circle : circles) {
            cv::Point center(cvRound(circle[0]), cvRound(circle[1]));
            int radius = cvRound(circle[2]);
            
            // Check circle validity
            if (center.x >= 0 && center.x < frame.cols &&
                center.y >= 0 && center.y < frame.rows &&
                radius > 0) {
                
                // More aggressive color matching with lower thresholds for outdoor
                bool isYellowTarget = isColorMatch(hsv, center, radius, adaptiveRanges.yellowLow, adaptiveRanges.yellowHigh, 15);
                bool isRedTarget1 = isColorMatch(hsv, center, radius, adaptiveRanges.redLow1, adaptiveRanges.redHigh1, 15);
                bool isRedTarget2 = isColorMatch(hsv, center, radius, adaptiveRanges.redLow2, adaptiveRanges.redHigh2, 15);
                
                // Check for yellow target with adaptive ranges
                if (isYellowTarget) {
                    Target target;
                    target.isCircular = true;
                    target.center = center;
                    target.radius = radius;
                    target.boundingBox = cv::Rect(center.x - radius, center.y - radius, 2 * radius, 2 * radius);
                    target.targetNumber = targetNumber++;
                    target.circles.push_back(circle);
                    targets.push_back(target);
                    continue;
                }
                
                // Check for red target (both ranges) with adaptive ranges
                if (isRedTarget1 || isRedTarget2) {
                    Target target;
                    target.isCircular = true;
                    target.center = center;
                    target.radius = radius;
                    target.boundingBox = cv::Rect(center.x - radius, center.y - radius, 2 * radius, 2 * radius);
                    target.targetNumber = targetNumber++;
                    target.circles.push_back(circle);
                    targets.push_back(target);
                }
            }
        }
    }
    
    // If no targets found with circles, try contour-based detection as fallback
    if (targets.empty()) {
        targets = detectTargetsByContours(frame, adaptiveRanges);
    }
    
    return targets;
}

// Helper function to detect targets by contours (fallback for outdoor conditions)
static std::vector<Target> detectTargetsByContours(const cv::Mat& frame, 
                                                  const ColorThresholds::AdaptiveRanges& adaptiveRanges) {
    std::vector<Target> targets;
    cv::Mat hsv;
    cv::cvtColor(frame, hsv, cv::COLOR_BGR2HSV);
    
    // Try yellow targets first
    cv::Mat yellowMask;
    cv::inRange(hsv, adaptiveRanges.yellowLow, adaptiveRanges.yellowHigh, yellowMask);
    
    // Morphological operations to clean up the mask
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(5, 5));
    cv::morphologyEx(yellowMask, yellowMask, cv::MORPH_CLOSE, kernel);
    cv::morphologyEx(yellowMask, yellowMask, cv::MORPH_OPEN, kernel);
    
    std::vector<std::vector<cv::Point>> yellowContours;
    cv::findContours(yellowMask, yellowContours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    
    int targetNumber = 1;
    
    // Process yellow contours
    for (const auto& contour : yellowContours) {
        double area = cv::contourArea(contour);
        if (area > 2000 && area < 50000) { // Stricter area
            cv::Rect rect = cv::boundingRect(contour);
            double aspectRatio = static_cast<double>(rect.width) / rect.height;
            if (aspectRatio > 0.9 && aspectRatio < 1.1) {
                // Require color match for target
                cv::Point center(rect.x + rect.width/2, rect.y + rect.height/2);
                int radius = std::max(rect.width, rect.height) / 2;
                if (isColorMatch(hsv, center, radius, adaptiveRanges.yellowLow, adaptiveRanges.yellowHigh, 30)) {
                    Target target;
                    target.isCircular = true;
                    target.center = center;
                    target.radius = radius;
                    target.boundingBox = rect;
                    target.targetNumber = targetNumber++;
                    targets.push_back(target);
                }
            }
        }
    }
    
    // Try red targets (both ranges)
    cv::Mat redMask1, redMask2, redMask;
    cv::inRange(hsv, adaptiveRanges.redLow1, adaptiveRanges.redHigh1, redMask1);
    cv::inRange(hsv, adaptiveRanges.redLow2, adaptiveRanges.redHigh2, redMask2);
    cv::bitwise_or(redMask1, redMask2, redMask);
    
    // Morphological operations
    cv::morphologyEx(redMask, redMask, cv::MORPH_CLOSE, kernel);
    cv::morphologyEx(redMask, redMask, cv::MORPH_OPEN, kernel);
    
    std::vector<std::vector<cv::Point>> redContours;
    cv::findContours(redMask, redContours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    
    // Process red contours
    for (const auto& contour : redContours) {
        double area = cv::contourArea(contour);
        if (area > 2000 && area < 50000) { // Stricter area
            cv::Rect rect = cv::boundingRect(contour);
            double aspectRatio = static_cast<double>(rect.width) / rect.height;
            if (aspectRatio > 0.9 && aspectRatio < 1.1) {
                cv::Point center(rect.x + rect.width/2, rect.y + rect.height/2);
                int radius = std::max(rect.width, rect.height) / 2;
                if (isColorMatch(hsv, center, radius, adaptiveRanges.redLow1, adaptiveRanges.redHigh1, 30) ||
                    isColorMatch(hsv, center, radius, adaptiveRanges.redLow2, adaptiveRanges.redHigh2, 30)) {
                    Target target;
                    target.isCircular = true;
                    target.center = center;
                    target.radius = radius;
                    target.boundingBox = rect;
                    target.targetNumber = targetNumber++;
                    targets.push_back(target);
                }
            }
        }
    }
    
    return targets;
}

// Helper function to check if a circular region matches a color range
static bool isColorMatch(const cv::Mat& hsv, const cv::Point& center, int radius, 
                        const cv::Scalar& low, const cv::Scalar& high, double minPercentage) {
    cv::Rect roi = getSafeROI(hsv, center, radius);
    if (roi.width <= 0 || roi.height <= 0) return false;
    cv::Mat roiMat = hsv(roi);
    cv::Mat mask;
    cv::inRange(roiMat, low, high, mask);
    double percentage = (cv::countNonZero(mask) * 100.0) / (roiMat.rows * roiMat.cols);
    float avgBrightness = calculateAverageBrightness(hsv);
    double adjustedThreshold = (avgBrightness > 150) ? 30 * 0.85 : 40;
    return percentage > adjustedThreshold;
}

// Helper function to get safe ROI bounds
static cv::Rect getSafeROI(const cv::Mat& frame, const cv::Point& center, int radius) {
    int x1 = std::max(0, center.x - radius);
    int y1 = std::max(0, center.y - radius);
    int x2 = std::min(frame.cols, center.x + radius);
    int y2 = std::min(frame.rows, center.y + radius);
    
    return cv::Rect(x1, y1, x2 - x1, y2 - y1);
}

// Helper function to draw detected target
static void drawDetectedTarget(cv::Mat& frame, const Target& target) {
    if (target.isCircular) {
        // Draw circular target
        cv::circle(frame, target.center, target.radius, cv::Scalar(0, 255, 0), 2);
        cv::putText(frame, "TARGET " + std::to_string(target.targetNumber),
                  cv::Point(target.center.x - 40, target.center.y - target.radius - 10),
                  cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(0, 255, 0), 2);
        
        // Draw target center
        cv::circle(frame, target.center, 5, cv::Scalar(0, 255, 255), -1);
    } else {
        // Draw rectangular target
        cv::rectangle(frame, target.boundingBox, cv::Scalar(0, 255, 0), 2);
        cv::Point center(target.boundingBox.x + target.boundingBox.width/2,
                        target.boundingBox.y + target.boundingBox.height/2);
        cv::putText(frame, "TARGET " + std::to_string(target.targetNumber),
                  cv::Point(center.x - 40, center.y - 10),
                  cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(0, 255, 0), 2);
        cv::circle(frame, center, 5, cv::Scalar(0, 255, 255), -1);
    }
}

// Helper function to get quadrant relative to goal boundary
static int getQuadrant(const cv::Point& pt, const cv::Rect& goalBoundary) {
    int midX = goalBoundary.x + goalBoundary.width / 2;
    int midY = goalBoundary.y + goalBoundary.height / 2;
    
    if (pt.x < midX && pt.y < midY) return 1; // Top-Left
    if (pt.x >= midX && pt.y < midY) return 2; // Top-Right
    if (pt.x < midX && pt.y >= midY) return 3; // Bottom-Left
    return 4; // Bottom-Right
}

// Helper function to enhance image contrast using CLAHE
static cv::Mat enhanceContrast(const cv::Mat& frame) {
    cv::Mat enhanced;
    
    // Convert to LAB color space for better contrast enhancement
    cv::Mat lab;
    cv::cvtColor(frame, lab, cv::COLOR_BGR2Lab);
    
    // Split channels
    std::vector<cv::Mat> labChannels(3);
    cv::split(lab, labChannels);
    
    // Apply CLAHE to L channel (lightness)
    cv::Ptr<cv::CLAHE> clahe = cv::createCLAHE(2.0, cv::Size(8, 8));
    clahe->apply(labChannels[0], labChannels[0]);
    
    // Merge channels back
    cv::merge(labChannels, lab);
    
    // Convert back to BGR
    cv::cvtColor(lab, enhanced, cv::COLOR_Lab2BGR);
    
    return enhanced;
}

// Helper function to calculate average brightness of an image
static float calculateAverageBrightness(const cv::Mat& frame) {
    cv::Mat gray;
    cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
    cv::Scalar mean = cv::mean(gray);
    return mean[0];
}

// Helper function for ball detection using shape (HoughCircles)
static cv::Point detectBallByShape(const cv::Mat& frame) {
    cv::Mat gray;
    cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
    cv::GaussianBlur(gray, gray, cv::Size(9, 9), 2);
    std::vector<cv::Vec3f> circles;
    cv::HoughCircles(gray, circles, cv::HOUGH_GRADIENT, 1,
                     gray.rows/6,   // min distance between centers (reduced for closer detection)
                     100, 30,      // relaxed Canny thresholds for better detection
                     5, 50);       // expanded radius range for various ball sizes
    
    if (!circles.empty()) {
        // Validate each circle more strictly
        for (const auto& circle : circles) {
            int x = cvRound(circle[0]);
            int y = cvRound(circle[1]);
            int radius = cvRound(circle[2]);
            
            // Check if position is valid
            if (x < 0 || x >= frame.cols || y < 0 || y >= frame.rows) {
                continue;
            }
            
            // Check radius constraints (expanded range for various ball sizes)
            if (radius < 5 || radius > 50) {
                continue;
            }
            
            // Calculate area and check size constraints
            double area = M_PI * radius * radius;
            if (area < MIN_BALL_AREA || area > MAX_BALL_AREA) {
                continue;
            }
            
            // Check circularity by analyzing the region around the circle
            cv::Rect roi = cv::Rect(std::max(0, x - radius), std::max(0, y - radius),
                                  std::min(2 * radius, frame.cols - std::max(0, x - radius)),
                                  std::min(2 * radius, frame.rows - std::max(0, y - radius)));
            
            if (roi.width > 0 && roi.height > 0) {
                cv::Mat roiMat = gray(roi);
                cv::Mat roiBinary;
                cv::threshold(roiMat, roiBinary, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);
                
                std::vector<std::vector<cv::Point>> contours;
                cv::findContours(roiBinary, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
                
                if (!contours.empty()) {
                    // Find the largest contour
                    auto largestContour = std::max_element(contours.begin(), contours.end(),
                        [](const std::vector<cv::Point>& a, const std::vector<cv::Point>& b) {
                            return cv::contourArea(a) < cv::contourArea(b);
                        });
                    
                    if (largestContour != contours.end()) {
                        double area = cv::contourArea(*largestContour);
                        double perimeter = cv::arcLength(*largestContour, true);
                        if (perimeter > 0) {
                            double circularity = 4 * M_PI * area / (perimeter * perimeter);
                            
                            // Only accept if circularity is high enough
                            if (circularity > MIN_CIRCULARITY) {
                                NSLog(@"[OpenCV] Shape detection: Valid ball at (%d, %d) with radius %d, circularity %.3f", 
                                      x, y, radius, circularity);
                                return cv::Point(x, y);
                            }
                        }
                    }
                }
            }
        }
    }
    return cv::Point(-1, -1);
}

// Helper function to detect ball by color with adaptive thresholds
static cv::Point detectBallByColor(const cv::Mat& frame) {
    cv::Mat enhancedFrame = enhanceContrast(frame);
    cv::Mat hsv;
    cv::cvtColor(enhancedFrame, hsv, cv::COLOR_BGR2HSV);
    float avgBrightness = calculateAverageBrightness(frame);
    auto adaptiveRanges = ColorThresholds::getAdaptiveRanges(avgBrightness);
    std::vector<std::pair<cv::Scalar, cv::Scalar>> colorRanges = {
        {ColorThresholds::WHITE_LOW, ColorThresholds::WHITE_HIGH},
        {adaptiveRanges.yellowLow, adaptiveRanges.yellowHigh},
        {ColorThresholds::ORANGE_LOW, ColorThresholds::ORANGE_HIGH},
        {adaptiveRanges.redLow1, adaptiveRanges.redHigh1},
        {adaptiveRanges.redLow2, adaptiveRanges.redHigh2}
    };
    cv::Point bestCenter(-1, -1);
    double maxArea = 0;
    for (const auto& range : colorRanges) {
        cv::Mat mask;
        cv::inRange(hsv, range.first, range.second, mask);
        cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(5, 5));
        cv::morphologyEx(mask, mask, cv::MORPH_OPEN, kernel);
        cv::morphologyEx(mask, mask, cv::MORPH_CLOSE, kernel);
        std::vector<std::vector<cv::Point>> contours;
        cv::findContours(mask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
        for (const auto& contour : contours) {
            double area = cv::contourArea(contour);
            if (area > MIN_BALL_AREA && area < MAX_BALL_AREA) {
                cv::Rect rect = cv::boundingRect(contour);
                double aspectRatio = static_cast<double>(rect.width) / rect.height;
                if (aspectRatio > 0.9 && aspectRatio < 1.1) {
                    cv::Point center(rect.x + rect.width / 2, rect.y + rect.height / 2);
                    
                    // Additional validation: check if this is not a target
                    bool isTarget = false;
                    for (const auto& target : lastDetectedTargets) {
                        cv::Point targetCenter = target.isCircular ? target.center :
                            cv::Point(target.boundingBox.x + target.boundingBox.width / 2,
                                      target.boundingBox.y + target.boundingBox.height / 2);
                        double distance = cv::norm(center - targetCenter);
                        if (distance < 50) { // If too close to a target, reject
                            isTarget = true;
                            break;
                        }
                    }
                    
                    if (!isTarget) {
                        // Require strong color match for ball
                        if (isColorMatch(hsv, center, std::max(rect.width, rect.height) / 2, range.first, range.second, 30)) {
                            if (center.x > 0 && center.x < frame.cols && center.y > 0 && center.y < frame.rows) {
                                // Calculate circularity
                                double perimeter = cv::arcLength(contour, true);
                                double circularity = 4 * M_PI * area / (perimeter * perimeter + 1e-6);
                                
                                // Only accept if circularity is high enough
                                if (circularity > MIN_CIRCULARITY) {
                                    if (area > maxArea) {
                                        maxArea = area;
                                        bestCenter = center;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    // Only return if a valid center was found
    if (maxArea > 0) {
        return bestCenter;
    } else {
        return cv::Point(-1, -1);
    }
}

// Enhanced soccer ball detection function
static bool detectSoccerBall(const cv::Mat& frame, cv::Point& ballCenter, float& ballRadius) {
    NSLog(@"[OpenCV] detectSoccerBall called with frame size: %dx%d", frame.cols, frame.rows);
    
    // Convert to HSV for better color detection
    cv::Mat hsv, blurred;
    cv::cvtColor(frame, hsv, cv::COLOR_BGR2HSV);
    cv::GaussianBlur(hsv, blurred, cv::Size(7, 7), 2);
    
    // Create masks for white and black parts of soccer ball
    cv::Mat maskWhite, maskBlack;
    cv::inRange(blurred, cv::Scalar(0, 0, 180), cv::Scalar(180, 50, 255), maskWhite); // white
    cv::inRange(blurred, cv::Scalar(0, 0, 0), cv::Scalar(180, 255, 60), maskBlack);   // black
    
    // Combine masks
    cv::Mat mask;
    cv::bitwise_or(maskWhite, maskBlack, mask);
    
    // Morphological operations to clean up the mask
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(5, 5));
    cv::morphologyEx(mask, mask, cv::MORPH_OPEN, kernel);
    cv::morphologyEx(mask, mask, cv::MORPH_CLOSE, kernel);
    
    // Find contours
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(mask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    
    NSLog(@"[OpenCV] Found %zu contours", contours.size());
    
    double bestScore = 0.0;
    cv::Point bestCenter(-1, -1);
    float bestRadius = 0.0f;
    
    for (const auto& contour : contours) {
        double area = cv::contourArea(contour);
        
        // Filter by size (soccer ball should be reasonably sized)
        if (area < 500 || area > 20000) {
            NSLog(@"[OpenCV] Contour rejected - area: %.1f (not in range 500-20000)", area);
            continue;
        }
        
        // Get minimum enclosing circle
        float radius;
        cv::Point2f center;
        cv::minEnclosingCircle(contour, center, radius);
        
        // Calculate circularity
        double perimeter = cv::arcLength(contour, true);
        double circularity = 4 * CV_PI * area / (perimeter * perimeter + 1e-6);
        
        // Soccer balls should be quite circular
        if (circularity < 0.7) {
            NSLog(@"[OpenCV] Contour rejected - circularity: %.3f (below 0.7)", circularity);
            continue;
        }
        
        // Calculate score based on area and circularity
        double score = area * circularity;
        
        NSLog(@"[OpenCV] Contour candidate - area: %.1f, circularity: %.3f, score: %.1f, center: (%d, %d), radius: %.1f", 
              area, circularity, score, (int)center.x, (int)center.y, radius);
        
        if (score > bestScore) {
            bestScore = score;
            bestCenter = center;
            bestRadius = radius;
        }
    }
    
    if (bestScore > 0) {
        ballCenter = bestCenter;
        ballRadius = bestRadius;
        NSLog(@"[OpenCV] Soccer ball found - center: (%d, %d), radius: %.1f, score: %.1f", 
              (int)ballCenter.x, (int)ballCenter.y, ballRadius, bestScore);
        return true;
    }
    
    NSLog(@"[OpenCV] No soccer ball found - best score: %.1f", bestScore);
    return false;
}

// Helper function to detect ball by motion (using Background Subtraction)
static cv::Point detectBallByMotion(const cv::Mat& gray, cv::Ptr<cv::BackgroundSubtractorMOG2> pMOG2) {
    cv::Mat fgMask;
    pMOG2->apply(gray, fgMask);

    // Morphological operations to reduce noise
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_ELLIPSE, cv::Size(7, 7));
    cv::morphologyEx(fgMask, fgMask, cv::MORPH_OPEN, kernel);
    cv::morphologyEx(fgMask, fgMask, cv::MORPH_CLOSE, kernel);
    
    // Find contours
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(fgMask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    
    // Find the largest motion contour (likely the ball)
    double maxArea = 0;
    cv::Point bestCenter(-1, -1);
    
    for (const auto& contour : contours) {
        double area = cv::contourArea(contour);
        if (area > 150 && area < 5000) { // Filter by size
            cv::Rect rect = cv::boundingRect(contour);
            cv::Point center(rect.x + rect.width / 2, rect.y + rect.height / 2);
            
            // Check if this is a reasonable ball position
            if (center.x > 0 && center.x < gray.cols && center.y > 0 && center.y < gray.rows) {
                if (area > maxArea) {
                    maxArea = area;
                    bestCenter = center;
                }
            }
        }
    }
    
    return bestCenter;
}