import SwiftUI
import AVFoundation
import UIKit

class BallDetectionManager: ObservableObject {
    @Published var isActive = false
    @Published var detectedBall: [AnyHashable: Any]? = nil
    @Published var ballPosition: CGPoint? = nil
    @Published var ballConfidence: Double = 0.0
    @Published var ballRadius: Double = 0.0
    @Published var detectionStatus = "Inactive"
    
    // Ball detection settings
    private let minConfidence: Double = 0.3
    private let maxBallRadius: Double = 100.0
    private let minBallRadius: Double = 10.0
    
    // Frame saving for debugging
    private var frameCounter = 0
    private let saveFrameInterval = 50 // Save every 50 frames (reduced frequency)
    private var isSavingFrame = false // Prevent multiple simultaneous saves
    private let enableFrameSaving = false // Set to false to disable frame saving if causing crashes
    
    func activate() {
        isActive = true
        detectionStatus = "Active"
        print("[BallDetection] Ball detection activated")
        print("[BallDetection] isActive: \(isActive)")
    }
    
    func deactivate() {
        isActive = false
        detectedBall = nil
        ballPosition = nil
        ballConfidence = 0.0
        ballRadius = 0.0
        detectionStatus = "Inactive"
        print("[BallDetection] Ball detection deactivated")
    }
    
    func processFrame(_ frame: UIImage) {
        guard isActive else { 
            print("[BallDetection] Ball detection not active")
            return 
        }
        
        print("[BallDetection] Processing frame for ball detection - isActive: \(isActive)")
        
        // Safety check to prevent excessive processing
        guard frameCounter < 1000 else {
            print("[BallDetection] Frame counter limit reached, resetting")
            frameCounter = 0
            return
        }
        
        frameCounter += 1
        
        // Save frame for debugging every 50 frames (reduced frequency)
        if enableFrameSaving && frameCounter % saveFrameInterval == 0 && !isSavingFrame {
            isSavingFrame = true
            saveFrameForDebugging(frame, frameNumber: frameCounter)
        }
        
        // Only print every 10th frame to reduce console spam
        if frameCounter % 10 == 0 {
            print("[BallDetection] Processing frame \(frameCounter) for ball detection...")
        }
        
        // Call OpenCV soccer ball detection
        print("[BallDetection] Calling OpenCV detectBallUnified...")
        if let ballDetection = OpenCVWrapper.detectBallUnified(frame) {
            print("[BallDetection] OpenCV returned: \(ballDetection)")
            let ball = ballDetection as? [AnyHashable: Any] ?? [:]
            
            if let isDetected = ball["isDetected"] as? Bool,
               isDetected,
               let x = ball["x"] as? Int,
               let y = ball["y"] as? Int,
               let confidence = ball["confidence"] as? Double {
                
                // Use a default radius if not provided
                let radius = ball["radius"] as? Double ?? 20.0
                
                print("[BallDetection] Parsed values - x: \(x), y: \(y), radius: \(radius), confidence: \(confidence)")
                
                // Validate ball detection
                if confidence >= minConfidence && 
                   radius >= minBallRadius && 
                   radius <= maxBallRadius {
                    
                    detectedBall = ball
                    ballPosition = CGPoint(x: x, y: y)
                    ballConfidence = confidence
                    ballRadius = radius
                    detectionStatus = "Ball Found"
                    
                    print("[BallDetection] Ball detected at (\(x), \(y)) with confidence \(confidence)")
                } else {
                    print("[BallDetection] Ball detection failed validation - confidence: \(confidence), radius: \(radius)")
                    clearDetection()
                }
            } else {
                print("[BallDetection] Ball detection parsing failed - isDetected: \(ball["isDetected"]), x: \(ball["x"]), y: \(ball["y"]), radius: \(ball["radius"]), confidence: \(ball["confidence"])")
                clearDetection()
            }
        } else {
            print("[BallDetection] OpenCV returned nil")
            clearDetection()
        }
    }
    
    private func clearDetection() {
        detectedBall = nil
        ballPosition = nil
        ballConfidence = 0.0
        ballRadius = 0.0
        detectionStatus = "No Ball"
    }
    
    func reset() {
        deactivate()
    }
    
    // Frame saving for debugging
    private func saveFrameForDebugging(_ frame: UIImage, frameNumber: Int) {
        // Save to Photos app
        UIImageWriteToSavedPhotosAlbum(frame, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), UnsafeMutableRawPointer(Unmanaged.passUnretained(frameNumber as AnyObject).toOpaque()))
    }
    
    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        let frameNumber = Unmanaged<AnyObject>.fromOpaque(contextInfo).takeUnretainedValue() as! Int
        
        if let error = error {
            print("[BallDetection] Failed to save debug frame \(frameNumber) to Photos: \(error)")
        } else {
            print("[BallDetection] Successfully saved debug frame \(frameNumber) to Photos")
        }
        
        // Reset the saving flag
        isSavingFrame = false
    }
    
    // List saved debug frames
    func listSavedDebugFrames() {
        print("[BallDetection] Debug frames are saved to Photos app")
        print("[BallDetection] Check your Photos app for images with timestamps")
        print("[BallDetection] Look for images saved around the time ball detection was active")
    }
}

// Ball Detection Button Component
struct BallDetectionButton: View {
    let onActivate: () -> Void
    let isEnabled: Bool
    
    var body: some View {
        Button(action: onActivate) {
            HStack {
                Image(systemName: "soccer.ball.inverse")
                    .font(.title2)
                Text("Start Ball Detection")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding()
            .background(isEnabled ? Color.blue : Color.gray)
            .cornerRadius(12)
        }
        .disabled(!isEnabled)
        .padding(.bottom, 100) // Above HUD
    }
}

// Ball Detection Status View
struct BallDetectionStatusView: View {
    let isActive: Bool
    let status: String
    let confidence: Double
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: isActive ? "soccer.ball.inverse" : "soccer.ball")
                    .foregroundColor(isActive ? .blue : .gray)
                Text(status)
                    .font(.caption)
                    .foregroundColor(isActive ? .blue : .gray)
            }
            
            if isActive && confidence > 0 {
                Text("\(Int(confidence * 100))%")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
    }
} 
