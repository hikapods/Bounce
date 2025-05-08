#import "OpenCVWrapper.h"

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

@implementation OpenCVWrapper

+ (NSString *)openCVVersion {
    std::string version = CV_VERSION;
    return [NSString stringWithUTF8String:version.c_str()];
}
+ (void)analyzeVideo:(NSString *)inputPath outputPath:(NSString *)outputPath {
    if (!inputPath || !outputPath) {
        NSLog(@"[OpenCV] Nil input or output path received");
        return;
    }
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
        
        cv::VideoWriter writer(output, cv::VideoWriter::fourcc('m','p','4','v'), fps, cv::Size(width, height));
        
        cv::Mat frame, hsv, mask, outputFrame;
        cv::Scalar lower_orange(5, 100, 100);   // H=5-25 works well for orange in sunlight
        cv::Scalar upper_orange(25, 255, 255);
        std::cout << "mask size: " << mask.cols << "x" << mask.rows << std::endl;
        
        cv::Mat prevGray;
        NSLog(@"[OpenCV] Input path: %s", input.c_str());
        
        while (cap.read(frame)) {
            outputFrame = frame.clone();
            cv::cvtColor(frame, hsv, cv::COLOR_BGR2HSV);
            cv::inRange(hsv, lower_orange, upper_orange, mask);
            
            std::vector<std::vector<cv::Point>> contours;
            cv::findContours(mask, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
            std::cout << "Contours found: " << contours.size() << std::endl;
            
            // Combine yellow contours to draw the green target rectangle
            std::vector<cv::Point> allPoints;
            
            // Accumulate orange tape points BEFORE checking if the list is empty
            for (const auto& contour : contours) {
                double area = cv::contourArea(contour);
                if (area < 200) continue;
                allPoints.insert(allPoints.end(), contour.begin(), contour.end());
            }
            
            // Now draw rectangle
            if (!allPoints.empty()) {
                cv::Rect fullTarget = cv::boundingRect(allPoints);
                cv::rectangle(outputFrame, fullTarget, cv::Scalar(0, 255, 0), 2);
            }
            
            
            cv::Mat gray, diff;
            cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
            
            if (!prevGray.empty()) {
                cv::absdiff(gray, prevGray, diff);
                cv::threshold(diff, diff, 25, 255, cv::THRESH_BINARY);
                std::vector<std::vector<cv::Point>> motionContours;
                cv::findContours(diff, motionContours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
                
                // ------------------- RED BULLSEYE CIRCLE DETECTION --------------------
                cv::Mat redMask1, redMask2, redMask;
                cv::inRange(hsv, cv::Scalar(0, 100, 100), cv::Scalar(10, 255, 255), redMask1);     // low red
                cv::inRange(hsv, cv::Scalar(160, 100, 100), cv::Scalar(179, 255, 255), redMask2);   // high red
                cv::bitwise_or(redMask1, redMask2, redMask);
                
                // Use redMask to focus HoughCircles detection
                cv::Mat redMaskGray;
                cv::GaussianBlur(redMask, redMaskGray, cv::Size(9, 9), 2, 2); // blur improves detection
                
                std::vector<cv::Vec3f> circles;
                cv::HoughCircles(redMaskGray, circles, cv::HOUGH_GRADIENT, 1,
                                 redMask.rows / 8,   // min dist between circles
                                 100, 20,            // param1 (edge), param2 (center strength)
                                 10, 60);            // min and max radius of circle (tweak if needed)
                
                cv::Point targetCenter(-1, -1);
                
                if (!circles.empty()) {
                    cv::Vec3f best = circles[0]; // pick first/best detected circle
                    targetCenter = cv::Point(cvRound(best[0]), cvRound(best[1]));
                    int radius = cvRound(best[2]);
                    
                    // Draw detected bullseye circle outline
                    cv::circle(outputFrame, targetCenter, radius, cv::Scalar(0, 255, 255), 2);
                    
                    // Draw "X" and label
                    cv::drawMarker(outputFrame, targetCenter, cv::Scalar(0, 255, 255),
                                   cv::MARKER_TILTED_CROSS, 20, 2);
                    cv::putText(outputFrame, "TARGET", targetCenter + cv::Point(10, -10),
                                cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(0, 255, 255), 2);
                }
                
                for (const auto& mc : motionContours) {
                    if (cv::contourArea(mc) < 500) continue;
                    cv::Rect motionRect = cv::boundingRect(mc);
                    cv::Point center(motionRect.x + motionRect.width / 2, motionRect.y + motionRect.height / 2);
                    // Draw line and compute distance to target
                    if (targetCenter.x > 0 && targetCenter.y > 0) {
                        // 1. Draw line
                        cv::line(outputFrame, targetCenter, center, cv::Scalar(255, 255, 0), 2);
                        
                        // 2. Compute distance
                        double distance = cv::norm(targetCenter - center);
                        
                        // 3. Show distance on screen
                        cv::putText(outputFrame, "Distance: " + std::to_string((int)distance) + " px",
                                    targetCenter + cv::Point(20, 40),
                                    cv::FONT_HERSHEY_SIMPLEX, 0.6, cv::Scalar(255, 255, 0), 2);
                    }
                    
                    cv::circle(outputFrame, center, 6, cv::Scalar(0, 0, 255), -1);
                    cv::putText(outputFrame, "Impact Detected", cv::Point(30, 30), cv::FONT_HERSHEY_SIMPLEX, 0.8, cv::Scalar(255, 255, 255), 2);
                }
            }
            
            prevGray = gray;
            writer.write(outputFrame);
        }
        
        cap.release();
        writer.release();
    }
}

@end

