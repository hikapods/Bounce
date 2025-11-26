import SwiftUI
import AVFoundation
import UIKit
import Photos
import Darwin

struct LiveCameraView: View {
    @StateObject private var cameraManager = CameraFeedManager()
    @StateObject private var dataLogger = DataLogger()
    @StateObject private var detectionManager = DetectionManager()
    @StateObject private var videoRecorder = VideoRecorder(videoSize: CGSize(width: 1920, height: 1080))
    // @StateObject private var ballDetectionManager = BallDetectionManager()  // OpenCV detection commented out - using ML detection only
    
    @State private var goalRegion = CGRect(x: 40, y: 100, width: 320, height: 240)
    @State private var detectedTargets: [[AnyHashable: Any]] = []
    @State private var detectedBall: [AnyHashable: Any]? = nil
    @State private var impactDetected = false
    @State private var impactMessage = ""
    @State private var showImpactFeedback = false
    @State private var frameSize = CGSize.zero
    @State private var frameCounter = 0
    @State private var showExportOptions = false
    @State private var exportSuccess = false
    @State private var exportMessage = ""
    @State private var showCameraPermissionAlert = false
    @State private var liveFrame: UIImage? = nil
    @State private var detectedTapeRegion: CGRect? = nil
    
    // Ball detection state
    @State private var ballDetectionActive = false
    @State private var ballDetectionStats = ""
    @State private var ballPositionHistory: [(x: Int, y: Int, confidence: Double)] = []
    @State private var consecutiveBallDetections = 0
    @State private var lastValidBall: [AnyHashable: Any]? = nil
    
    // Memory management: prevent concurrent processing
    @State private var isProcessingFrame = false
    @State private var lastProcessedFrameTime: Date = Date()
    private let minProcessingInterval: TimeInterval = 0.1 // Process max 10 frames per second
    private let processingQueue = DispatchQueue(label: "com.bouncebacktrainer.processing", qos: .userInitiated)
    
    // Video recording state
    @State private var originalVideoURL: URL?
    @State private var processedVideoURL: URL?
    @State private var isProcessingVideo = false
    @State private var showVideoSavedAlert = false
    @State private var videoSaveMessage = ""
    
    // Computed properties to avoid complex expressions
    private var statusText: Text {
        if detectionManager.goalLocked {
            return Text("Goal Locked")
        } else if detectionManager.validGoalRegionCounter > 0 {
            return Text("Goal Detected")
        } else {
            return Text("Finding Goal")
        }
    }
    
    private var statusBackgroundColor: Color {
        if detectionManager.goalLocked {
            return Color.green.opacity(0.8)
        } else if detectionManager.validGoalRegionCounter > 0 {
            return Color.orange.opacity(0.8)
        } else {
            return Color.red.opacity(0.8)
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size
            let scale = frameSize.width > 0 ? viewSize.width / frameSize.width : 1.0
            let yOffset: CGFloat = frameSize.height > 0 ? (viewSize.height - frameSize.height * scale) / 2 : 0
            
            ZStack {
                // Camera preview with goal detection overlay
                if let liveFrame = liveFrame {
                    GoalDetectionView(
                        liveFrame: liveFrame,
                        frameSize: frameSize,
                        detectedTapeRegion: detectedTapeRegion,
                        goalLocked: detectionManager.goalLocked
                    )
                } else {
                    Color.black.edgesIgnoringSafeArea(.all)
                }
                
                // Status overlay
                VStack {
                    HStack {
                        Spacer()
                        statusText
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(statusBackgroundColor)
                            .cornerRadius(10)
                        Spacer()
                    }
                    Spacer()
                }
                
                // Target detection overlay
                if detectionManager.goalLocked {
                    TargetDetectionView(
                        lockedTargets: detectionManager.lockedTargets,
                        frameSize: frameSize,
                        viewSize: viewSize,
                        yOffset: yOffset,
                        scale: scale
                    )
                    
                    // Current detected targets overlay with lock button
                    if detectionManager.showLockTargetsButton {
                        CurrentTargetsView(
                            currentTargets: detectionManager.currentDetectedTargets,
                            frameSize: frameSize,
                            viewSize: viewSize,
                            yOffset: yOffset,
                            scale: scale,
                            onLockTargets: {
                                detectionManager.lockCurrentTargets()
                            }
                        )
                    }
                    
                    // Reset button - always show when goal is locked
                    VStack {
                        Spacer()
                        HStack {
                            ResetButton(onReset: {
                                detectionManager.reset()
                                // ballDetectionManager.reset()  // OpenCV detection commented out
                                ballDetectionActive = false
                                detectedBall = nil
                                ballPositionHistory.removeAll()
                                consecutiveBallDetections = 0
                                lastValidBall = nil
                                ballDetectionStats = ""
                            })
                            Spacer()
                        }
                    }
                    
                    // Ball detection button - show after targets are locked
                    if !detectionManager.lockedTargets.isEmpty && !ballDetectionActive {
                        VStack {
                            Spacer()
                            Button(action: {
                                ballDetectionActive = true
                                print("🎯 Ball detection activated after targets locked")
                            }) {
                                HStack {
                                    Image(systemName: "soccerball")
                                        .foregroundColor(.white)
                                    Text("Start Ball Detection")
                                        .foregroundColor(.white)
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(10)
                            }
                            .padding(.bottom, 100)
                        }
                    }
                    
                    // Ball detection overlay
                    if ballDetectionActive {
                        BallDetectionOverlay(
                            detectedBall: detectedBall,
                            frameSize: frameSize,
                            viewSize: viewSize,
                            yOffset: yOffset,
                            scale: scale
                        )
                        
                        // Recording status and stop button
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                VStack(alignment: .trailing, spacing: 8) {
                                    // Recording indicator
                                    if videoRecorder.isRecording {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: 10, height: 10)
                                                .opacity(videoRecorder.isRecording ? 1.0 : 0.5)
                                            Text("Recording")
                                                .font(.caption)
                                                .foregroundColor(.white)
                                            Text(String(format: "%.1fs", videoRecorder.recordingDuration))
                                                .font(.caption2)
                                                .foregroundColor(.white)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.red.opacity(0.8))
                                        .cornerRadius(8)
                                        
                                        // Stop recording button
                                        Button(action: {
                                            stopRecording()
                                        }) {
                                            HStack {
                                                Image(systemName: "stop.fill")
                                                Text("Stop Recording")
                                            }
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                            .background(Color.red)
                                            .cornerRadius(10)
                                        }
                                    } else {
                                        // Ball detection status
                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text("Ball Detection Active")
                                                .font(.caption)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.green.opacity(0.8))
                                                .cornerRadius(6)
                                            
                                            if !ballDetectionStats.isEmpty {
                                                Text(ballDetectionStats)
                                                    .font(.caption2)
                                                    .foregroundColor(.cyan)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 2)
                                                    .background(Color.black.opacity(0.6))
                                                    .cornerRadius(4)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 150)
                        }
                    }
                }
                
                // HUD overlay
                HUDOverlay(
                    frameCounter: frameCounter,
                    lockedTargetsCount: detectionManager.lockedTargets.count,
                    currentTargetsCount: detectionManager.currentDetectedTargets.count,
                    goalLocked: detectionManager.goalLocked,
                    ballDetected: ballDetectionActive && (detectedBall?["isDetected"] as? Bool ?? false)
                )
            }
            .edgesIgnoringSafeArea(.all)
        }
        .onAppear {
            setupCamera()
            setupFrameProcessing()
        }
        .onChange(of: goalRegion) { newRegion in
            cameraManager.updateGoalRegion(newRegion)
        }
        .onChange(of: detectedTapeRegion) { newRegion in
            detectionManager.processGoalDetection(newRegion, frameSize: frameSize)
        }
        .actionSheet(isPresented: $showExportOptions) {
            ActionSheet(
                title: Text("Export Data"),
                message: Text("Choose export format"),
                buttons: [
                    .default(Text("Export JSON")) { exportData(format: "json") },
                    .default(Text("Export CSV")) { exportData(format: "csv") },
                    .cancel()
                ]
            )
        }
        .alert(exportSuccess ? "Success" : "Error", isPresented: $exportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportMessage)
        }
        .alert("Camera Permission Required", isPresented: $showCameraPermissionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enable camera access in Settings to use the live camera feature.")
        }
        .alert("Video Saved", isPresented: $showVideoSavedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(videoSaveMessage)
        }
    }
    
    private func setupCamera() {
        cameraManager.startSession()
    }
    
    private func setupFrameProcessing() {
        cameraManager.onFrameProcessed = { frame, region in
            
            // Update frame size and live frame immediately (lightweight)
            DispatchQueue.main.async {
                if self.frameSize != frame.size {
                    self.frameSize = frame.size
                    // Update video recorder with new frame size
                    self.videoRecorder.reset()
                }
                self.liveFrame = frame
                
                // Add frame to buffer if ball detection is active (for 1-second pre-capture)
                if self.ballDetectionActive {
                    self.videoRecorder.addFrameToBuffer(frame)
                }
            }
            
            // Throttle processing to prevent memory buildup
            let now = Date()
            guard now.timeIntervalSince(self.lastProcessedFrameTime) >= self.minProcessingInterval,
                  !self.isProcessingFrame else {
                return // Skip this frame if processing too frequently or already processing
            }
            
            self.isProcessingFrame = true
            self.lastProcessedFrameTime = now
            
            // Process on background queue without delay
            // Note: No need for [weak self] since LiveCameraView is a struct (value type)
            // Capture values before async closure (structs don't need [weak self])
            let currentFrameCounter = frameCounter
            let isBallDetectionActive = ballDetectionActive
            let currentFrame = frame // Capture frame for recording
            
            processingQueue.async {
                // Enhanced backend processing with performance monitoring
                let performance = OpenCVWrapper.analyzeFramePerformance(frame) as? [AnyHashable: Any] ?? [:]
                
                // Auto-calibrate for lighting conditions every 60 frames (reduced frequency)
                if currentFrameCounter % 60 == 0 {
                    OpenCVWrapper.calibrate(forLighting: frame)
                }
                
                // Main detection pipeline
                let result = OpenCVWrapper.detectTargets(inFrame: frame, goalRegion: region) as? [AnyHashable: Any] ?? [:]
                let targets = result["targets"] as? [[AnyHashable: Any]] ?? []
                
                // Update state on main thread (required for @State properties)
                DispatchQueue.main.async {
                    if let tapeValue = result["tapeRegion"] as? NSValue {
                        detectedTapeRegion = tapeValue.cgRectValue
                    } else {
                        detectedTapeRegion = nil
                    }
                }
                // OpenCV ball detection commented out - using ML detection only
                /*
                // Process ball detection through BallDetectionManager
                ballDetectionManager.processFrame(frame)
                let ballDict = ballDetectionManager.detectedBall
                let ball = ballDict ?? [:]
                
                // Enhanced ball detection using unified method when active
                var finalBallResult = ball
                if ballDetectionActive {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let startTime = CFAbsoluteTimeGetCurrent()
                        
                        // Use unified ball detection (tries multiple methods automatically)
                        let unifiedBallResult = OpenCVWrapper.detectBallUnified(frame)
                        
                        // FFT detection is commented out
                        // let fftBallResult = OpenCVWrapper.detectBallByFFT(frame) // FFT method commented out
                        
                        // Use unified result directly
                        var validatedResult = unifiedBallResult
                        
                        // Temporal consistency check
                        if let isDetected = validatedResult?["isDetected"] as? Bool, isDetected,
                           let x = validatedResult?["x"] as? Int, let y = validatedResult?["y"] as? Int,
                           let confidence = validatedResult?["confidence"] as? Double {
                            
                            // Add to position history
                            ballPositionHistory.append((x: x, y: y, confidence: confidence))
                            
                            // Keep only last 5 positions
                            if ballPositionHistory.count > 5 {
                                ballPositionHistory.removeFirst()
                            }
                            
                            // Check temporal consistency
                            if ballPositionHistory.count >= 2 {
                                let recentPositions = Array(ballPositionHistory.suffix(2))
                                let avgX = Double(recentPositions.map { $0.x }.reduce(0, +)) / Double(recentPositions.count)
                                let avgY = Double(recentPositions.map { $0.y }.reduce(0, +)) / Double(recentPositions.count)
                                
                                // Check if positions are reasonably close (within 80 pixels)
                                let maxDistance = 80.0
                                let isConsistent = recentPositions.allSatisfy { pos in
                                    let distance = sqrt(pow(Double(pos.x) - avgX, 2) + pow(Double(pos.y) - avgY, 2))
                                    return distance <= maxDistance
                                }
                                
                                if isConsistent {
                                    consecutiveBallDetections += 1
                                    lastValidBall = validatedResult
                                } else {
                                    consecutiveBallDetections = 0
                                    validatedResult = lastValidBall ?? validatedResult // Use last valid detection
                                }
                            } else {
                                consecutiveBallDetections = 1
                                lastValidBall = validatedResult
                            }
                            
                            // Only accept detection if we have consistent detections
                            if consecutiveBallDetections >= 1 {
                                finalBallResult = validatedResult ?? [:]
                            } else {
                                finalBallResult = lastValidBall ?? [:]
                            }
                        } else {
                            consecutiveBallDetections = 0
                            ballPositionHistory.removeAll()
                        }
                        
                        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
                        
                        DispatchQueue.main.async {
                            detectedBall = finalBallResult
                            
                            // Update ball detection stats
                            if let isDetected = finalBallResult["isDetected"] as? Bool {
                                ballDetectionStats = "Frame: \(frameCounter), Processing: \(String(format: "%.3f", processingTime))s, Detected: \(isDetected), Consecutive: \(consecutiveBallDetections)"
                            }
                            
                            // Log detection results for debugging
                            if let isDetected = finalBallResult["isDetected"] as? Bool, isDetected {
                                print("⚽ LiveCamera Ball Detection: Ball found at frame \(frameCounter)")
                                if let x = finalBallResult["x"] as? Int, let y = finalBallResult["y"] as? Int {
                                    print("   Position: (\(x), \(y))")
                                }
                            }
                        }
                    }
                }
                */
                
                // ML Ball Detection - using MLBallDetector (best performing method)
                // Only process if ball detection is active and we're not already processing
                if isBallDetectionActive {
                    let startTime = CFAbsoluteTimeGetCurrent()
                    
                    // Use ML detection (async completion handler)
                    // Capture frame and frame size before async to avoid retaining full frame
                    let frameForDetection = currentFrame
                    let frameWidth = frameForDetection.size.width
                    let frameHeight = frameForDetection.size.height
                    
                    MLBallDetector.shared.detectBall(in: frameForDetection) { mlDetection in
                        
                        // Release frame reference immediately after detection starts
                        // Frame is no longer needed after ML detection begins
                        
                        guard let mlDetection = mlDetection else {
                            DispatchQueue.main.async {
                                self.detectedBall = ["isDetected": false]
                                self.ballDetectionStats = "Frame: \(currentFrameCounter), ML: No ball detected"
                                self.isProcessingFrame = false
                            }
                            return
                        }
                        
                        // Convert ML detection (normalized 0-1) to pixel coordinates
                        let bbox = mlDetection.boundingBox
                        
                        // Convert normalized bounding box to pixel coordinates
                        let centerX = Int((bbox.origin.x + bbox.width / 2) * frameWidth)
                        let centerY = Int((bbox.origin.y + bbox.height / 2) * frameHeight)
                        let radius = Int(max(bbox.width * frameWidth, bbox.height * frameHeight) / 2)
                        
                        // Create result dictionary in format expected by UI
                        let mlResult: [AnyHashable: Any] = [
                            "isDetected": true,
                            "x": centerX,
                            "y": centerY,
                            "radius": Double(radius),
                            "confidence": Double(mlDetection.confidence),
                            "method": "ML",
                            "label": mlDetection.label
                        ]
                        
                        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
                        
                        DispatchQueue.main.async {
                            let wasBallDetected = self.detectedBall?["isDetected"] as? Bool ?? false
                            self.detectedBall = mlResult
                            
                            // Start recording if ball is detected and not already recording
                            // mlDetection is already unwrapped (non-optional) at this point
                            if !wasBallDetected && !self.videoRecorder.isRecording {
                                self.startRecording()
                            }
                            
                            // Note: Frame appending happens in main processing loop, not here
                            // to avoid async timing issues
                            
                            // Update ball detection stats
                            self.ballDetectionStats = "Frame: \(currentFrameCounter), ML: \(String(format: "%.3f", processingTime))s, Conf: \(String(format: "%.2f", mlDetection.confidence))"
                            
                            // Mark processing as complete
                            self.isProcessingFrame = false
                            
                            // Log detection results (reduced frequency)
                            if currentFrameCounter % 10 == 0 {
                                print("⚽ ML Ball Detection: Ball found at frame \(currentFrameCounter)")
                                print("   Position: (\(centerX), \(centerY)), Confidence: \(mlDetection.confidence), Label: \(mlDetection.label)")
                            }
                        }
                    }
                } else {
                    // Not processing ball detection, mark as complete immediately
                    DispatchQueue.main.async {
                        self.isProcessingFrame = false
                    }
                }
                
                // Convert ball detection to target format for locking
                var allTargets = targets
                
                // Check detectedBall synchronously (may be from previous frame, that's OK)
                var currentBall: [AnyHashable: Any]? = nil
                DispatchQueue.main.sync {
                    currentBall = self.detectedBall
                }
                
                if let ball = currentBall,
                   let isDetected = ball["isDetected"] as? Bool,
                   isDetected,
                   let x = ball["x"] as? Int,
                   let y = ball["y"] as? Int,
                   let radius = ball["radius"] as? Double {
                    
                    // Create a target from the ball detection
                    let ballTarget: [AnyHashable: Any] = [
                        "centerX": x,
                        "centerY": y,
                        "radius": radius,
                        "targetNumber": targets.count + 1, // Give it a unique number
                        "type": "ball",
                        "confidence": ball["confidence"] as? Double ?? 1.0
                    ]
                    allTargets.append(ballTarget)
                    // Removed print to reduce memory overhead
                }
                
                // Impact detection - using current ball state
                let ballForImpact = currentBall ?? [:]
                let impact = OpenCVWrapper.detectImpact(withBall: (ballForImpact as NSDictionary) as! [AnyHashable : Any], targets: allTargets, goalRegion: region)
                
                // Motion detection commented out to save memory
                // let motionRegions = OpenCVWrapper.detectMotion(inFrame: frame) as? [[AnyHashable: Any]] ?? []
                
                // Get tracking statistics commented out to save memory
                // let stats = OpenCVWrapper.getTrackingStatistics() as? [AnyHashable: Any] ?? [:]
                
                DispatchQueue.main.async {
                    
                    self.detectedTargets = allTargets
                    self.frameCounter += 1
                    
                    // Append frame to recording if active
                    if self.videoRecorder.isRecording {
                        self.videoRecorder.appendFrame(currentFrame)
                    }
                    
                    // Process targets through detection manager
                    self.detectionManager.processTargetDetection(allTargets)
                    
                    // Log frame (reduced frequency to save memory)
                    if self.frameCounter % 30 == 0 {
                        print("Frame \(self.frameCounter): Detected \(allTargets.count) targets")
                    }
                    
                    // Log to data logger (reduced frequency - every 5th frame)
                    if self.frameCounter % 5 == 0 {
                        self.dataLogger.logFrame(
                            frameNumber: self.frameCounter,
                            ball: currentBall as? NSDictionary,
                            targets: allTargets.map { $0 as NSDictionary },
                            impactDetected: impact
                        )
                    }
                    
                    // Impact feedback
                    if impact && !self.impactDetected {
                        self.impactDetected = true
                        self.impactMessage = "HIT!"
                        self.showImpactFeedback = true
                        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                        impactFeedback.impactOccurred()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.showImpactFeedback = false
                            self.impactDetected = false
                        }
                    }
                }
            }
        }
    }
    
    private func exportData(format: String) {
        var url: URL?
        if format == "json" {
            url = dataLogger.exportData()
        } else if format == "csv" {
            url = dataLogger.exportCSV()
        }
        if let url = url {
            exportSuccess = true
            exportMessage = "Data exported successfully to: \(url.lastPathComponent)"
        } else {
            exportSuccess = false
            exportMessage = "Failed to export data"
        }
    }
    
    // Start recording when ball is detected
    private func startRecording() {
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "ball_detection_\(formatter.string(from: timestamp)).mp4"
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = documentsPath.appendingPathComponent(filename)
        
        // Set up completion handler for auto-stop
        // Note: No [weak self] needed since LiveCameraView is a struct (value type)
        videoRecorder.onRecordingComplete = { url in
            guard let originalURL = url else {
                DispatchQueue.main.async {
                    self.videoSaveMessage = "Failed to save video"
                    self.showVideoSavedAlert = true
                }
                return
            }
            
            print("🎥 Auto-stopped recording: \(originalURL.lastPathComponent)")
            self.originalVideoURL = originalURL
            
            // Save video to Photos immediately (bypass processing)
            self.saveVideoToPhotos(url: originalURL, isOriginal: true)
            
            // Process video with ML detection in background (later)
            DispatchQueue.global(qos: .utility).async {
                self.processVideoWithMLDetection(inputURL: originalURL)
            }
        }
        
        videoRecorder.startRecording(outputURL: outputURL) { success, error in
            DispatchQueue.main.async {
                if success {
                    print("🎥 Recording started (will auto-stop after 1.8s): \(outputURL.lastPathComponent)")
                } else {
                    print("❌ Failed to start recording: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    // Stop recording manually (if user taps stop button)
    private func stopRecording() {
        videoRecorder.onRecordingComplete = nil // Clear auto-completion
        videoRecorder.stopRecording { url in
            guard let originalURL = url else {
                DispatchQueue.main.async {
                    self.videoSaveMessage = "Failed to save video"
                    self.showVideoSavedAlert = true
                }
                return
            }
            
            self.originalVideoURL = originalURL
            print("🎥 Manual stop - Original video saved: \(originalURL.lastPathComponent)")
            
            // Save video to Photos immediately (bypass processing)
            self.saveVideoToPhotos(url: originalURL, isOriginal: true)
            
            // Process video with ML detection in background (later)
            DispatchQueue.global(qos: .utility).async {
                self.processVideoWithMLDetection(inputURL: originalURL)
            }
        }
    }
    
    // Process video frame by frame with ML detection and mark balls
    private func processVideoWithMLDetection(inputURL: URL) {
        // Log memory usage before processing
        logMemoryUsage(phase: "Before video processing")
        
        isProcessingVideo = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let timestamp = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let filename = "processed_ball_detection_\(formatter.string(from: timestamp)).mp4"
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let outputURL = documentsPath.appendingPathComponent(filename)
            
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            
            // Create video asset
            let asset = AVAsset(url: inputURL)
            guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                DispatchQueue.main.async {
                    self.isProcessingVideo = false
                    self.videoSaveMessage = "Failed to process video: No video track found"
                    self.showVideoSavedAlert = true
                }
                return
            }
            
            let videoSize = videoTrack.naturalSize
            let frameRate = videoTrack.nominalFrameRate
            let duration = asset.duration
            
            // Setup video writer
            guard let videoWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
                DispatchQueue.main.async {
                    self.isProcessingVideo = false
                    self.videoSaveMessage = "Failed to create video writer"
                    self.showVideoSavedAlert = true
                }
                return
            }
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(videoSize.width),
                AVVideoHeightKey: Int(videoSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6000000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            
            let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoWriterInput.expectsMediaDataInRealTime = false
            
            guard videoWriter.canAdd(videoWriterInput) else {
                DispatchQueue.main.async {
                    self.isProcessingVideo = false
                    self.videoSaveMessage = "Failed to add video input"
                    self.showVideoSavedAlert = true
                }
                return
            }
            
            videoWriter.add(videoWriterInput)
            
            // Create pixel buffer adaptor BEFORE starting writing session
            // Must provide proper attributes for the pixel buffer
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoWriterInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: Int(videoSize.width),
                    kCVPixelBufferHeightKey as String: Int(videoSize.height),
                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
                ]
            )
            
            // Now start writing
            videoWriter.startWriting()
            videoWriter.startSession(atSourceTime: .zero)
            
            // Create image generator
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.requestedTimeToleranceBefore = .zero
            imageGenerator.requestedTimeToleranceAfter = .zero
            
            let timescale = Int32(600)
            let frameDuration = CMTime(value: 1, timescale: timescale)
            var currentTime = CMTime.zero
            var frameCount = 0
            
            // Process each frame
            while currentTime < duration {
                autoreleasepool {
                    // Generate frame image
                    guard let cgImage = try? imageGenerator.copyCGImage(at: currentTime, actualTime: nil) else {
                        currentTime = CMTimeAdd(currentTime, frameDuration)
                        return
                    }
                    
                    let uiImage = UIImage(cgImage: cgImage)
                    
                    // Detect ball using ML (with timeout to prevent hanging)
                    var processedImage = uiImage
                    let semaphore = DispatchSemaphore(value: 0)
                    var detectionCompleted = false
                    
                    MLBallDetector.shared.detectBall(in: uiImage) { mlDetection in
                        if let detection = mlDetection {
                            // Draw bounding box on image
                            processedImage = self.drawBoundingBox(on: uiImage, detection: detection)
                        }
                        detectionCompleted = true
                        semaphore.signal()
                    }
                    
                    // Wait for detection with timeout (0.5 seconds max per frame)
                    let timeoutResult = semaphore.wait(timeout: .now() + 0.5)
                    if timeoutResult == .timedOut {
                        print("⚠️ ML detection timeout for frame \(frameCount), using original image")
                    }
                    
                    // Convert to pixel buffer and append
                    if let pixelBuffer = self.imageToPixelBuffer(processedImage, size: videoSize) {
                        // Wait for writer to be ready
                        while !videoWriterInput.isReadyForMoreMediaData && videoWriter.status == .writing {
                            Thread.sleep(forTimeInterval: 0.01)
                        }
                        
                        // Only append if writer is still writing
                        if videoWriter.status == .writing {
                            adaptor.append(pixelBuffer, withPresentationTime: currentTime)
                        }
                    }
                    
                    currentTime = CMTimeAdd(currentTime, frameDuration)
                    frameCount += 1
                    
                    // Update progress every 30 frames
                    if frameCount % 30 == 0 {
                        let progress = currentTime.seconds / duration.seconds
                        print("Processing video: \(Int(progress * 100))%")
                    }
                }
            }
            
            // Log memory usage during processing
            logMemoryUsage(phase: "During video processing")
            
            // Finish writing
            videoWriterInput.markAsFinished()
            videoWriter.finishWriting {
                // Log memory usage after processing
                self.logMemoryUsage(phase: "After video processing")
                
                DispatchQueue.main.async {
                    self.isProcessingVideo = false
                    
                    if videoWriter.status == .completed {
                        self.processedVideoURL = outputURL
                        self.videoSaveMessage = "Video saved! Processing completed in background."
                        self.showVideoSavedAlert = true
                        
                        // Save processed video to Photos
                        self.saveVideoToPhotos(url: outputURL, isOriginal: false)
                    } else {
                        let errorMsg = videoWriter.error?.localizedDescription ?? "Unknown error"
                        print("❌ Video processing failed: \(errorMsg)")
                        // Don't show error alert for background processing - just log it
                        print("⚠️ Background processing failed, but original video was saved")
                    }
                }
            }
        }
    }
    
    // Draw bounding box on image
    private func drawBoundingBox(on image: UIImage, detection: MLBallDetection) -> UIImage {
        let size = image.size
        let scale = image.scale
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        
        // Draw original image
        image.draw(in: CGRect(origin: .zero, size: size))
        
        // Convert normalized bounding box to pixel coordinates
        let bbox = detection.boundingBox
        let rect = CGRect(
            x: bbox.origin.x * size.width,
            y: bbox.origin.y * size.height,
            width: bbox.width * size.width,
            height: bbox.height * size.height
        )
        
        // Draw bounding box
        context.setStrokeColor(UIColor.blue.cgColor)
        context.setLineWidth(4.0)
        context.stroke(rect)
        
        // Draw confidence label
        let confidenceText = String(format: "%.0f%%", detection.confidence * 100)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20),
            .foregroundColor: UIColor.blue,
            .backgroundColor: UIColor.white.withAlphaComponent(0.8)
        ]
        
        let textRect = CGRect(x: rect.origin.x, y: rect.origin.y - 30, width: 100, height: 30)
        confidenceText.draw(in: textRect, withAttributes: attributes)
        
        guard let newImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return image
        }
        
        UIGraphicsEndImageContext()
        return newImage
    }
    
    // Convert UIImage to CVPixelBuffer
    private func imageToPixelBuffer(_ image: UIImage, size: CGSize) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32ARGB
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        guard let ctx = context, let cgImage = image.cgImage else {
            return nil
        }
        
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        return buffer
    }
    
    // Save video to Photos
    private func saveVideoToPhotos(url: URL, isOriginal: Bool) {
        // Log memory before saving
        logMemoryUsage(phase: "Before saving to Photos")
        
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                print("Photo library access denied")
                DispatchQueue.main.async {
                    self.videoSaveMessage = "Please allow Photos access in Settings"
                    self.showVideoSavedAlert = true
                }
                return
            }
            
            // Check if file exists before saving
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("❌ Video file does not exist at: \(url.path)")
                DispatchQueue.main.async {
                    self.videoSaveMessage = "Video file not found"
                    self.showVideoSavedAlert = true
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                // Log memory after saving
                self.logMemoryUsage(phase: "After saving to Photos")
                
                DispatchQueue.main.async {
                    if success {
                        print("✅ \(isOriginal ? "Original" : "Processed") video saved to Photos: \(url.lastPathComponent)")
                        if isOriginal {
                            self.videoSaveMessage = "Video saved to Photos successfully!"
                            self.showVideoSavedAlert = true
                        }
                    } else {
                        let errorMsg = error?.localizedDescription ?? "Unknown error"
                        print("❌ Failed to save \(isOriginal ? "original" : "processed") video: \(errorMsg)")
                        if isOriginal {
                            self.videoSaveMessage = "Failed to save video: \(errorMsg)"
                            self.showVideoSavedAlert = true
                        }
                    }
                }
            }
        }
    }
    
    // Memory profiling function
    private func logMemoryUsage(phase: String) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMemory = Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
            print("📊 Memory [\(phase)]: \(String(format: "%.2f", usedMemory)) MB")
        } else {
            print("⚠️ Failed to get memory info: \(kerr)")
        }
    }
    
    func isGoalAligned() -> Bool {
        guard let tape = detectedTapeRegion, tape != .zero else { return false }
        let intersection = goalRegion.intersection(tape)
        let overlap = (intersection.width * intersection.height) / (goalRegion.width * goalRegion.height)
        return overlap > 0.7 // adjust threshold as needed
    }
}

struct TargetIndicator: View {
    let target: [AnyHashable: Any]
    var body: some View {
        let centerX = target["centerX"] as? NSNumber ?? 0
        let centerY = target["centerY"] as? NSNumber ?? 0
        let radius = target["radius"] as? NSNumber ?? 0
        let targetNumber = target["targetNumber"] as? NSNumber ?? 0
        ZStack {
            Circle()
                .stroke(Color.green, lineWidth: 3)
                .frame(width: CGFloat(radius.intValue * 2), height: CGFloat(radius.intValue * 2))
                .position(x: CGFloat(centerX.intValue), y: CGFloat(centerY.intValue))
            Text("\(targetNumber.intValue)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .background(Color.green)
                .clipShape(Circle())
                .frame(width: 20, height: 20)
                .position(x: CGFloat(centerX.intValue), y: CGFloat(centerY.intValue) - CGFloat(radius.intValue) - 15)
        }
    }
}

struct BallIndicator: View {
    let x: CGFloat
    let y: CGFloat
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 16, height: 16)
            .position(x: x, y: y)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 16, height: 16)
            )
    }
}

struct ImpactFeedbackView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.largeTitle)
            .fontWeight(.bold)
            .foregroundColor(.red)
            .background(Color.white.opacity(0.8))
            .padding()
            .cornerRadius(10)
            .scaleEffect(1.5)
            .animation(.easeInOut(duration: 0.3), value: message)
    }
}

struct LiveCameraView_Previews: PreviewProvider {
    static var previews: some View {
        LiveCameraView()
    }
}

// Ball Detection Overlay Component
struct BallDetectionOverlay: View {
    let detectedBall: [AnyHashable: Any]?
    let frameSize: CGSize
    let viewSize: CGSize
    let yOffset: CGFloat
    let scale: CGFloat
    
    var body: some View {
        if let ball = detectedBall,
           let isDetected = ball["isDetected"] as? Bool,
           isDetected,
           let x = ball["x"] as? Int,
           let y = ball["y"] as? Int,
           let radius = ball["radius"] as? Double {
            
            let ballX = CGFloat(x) * scale
            let ballY = CGFloat(y) * scale + yOffset
            let ballRadius = CGFloat(radius) * scale
            
            // Blue circle around detected ball
            Circle()
                .stroke(Color.blue, lineWidth: 3)
                .frame(width: ballRadius * 2, height: ballRadius * 2)
                .position(x: ballX, y: ballY)
                .overlay(
                    // Confidence indicator
                    Group {
                        if let confidence = ball["confidence"] as? Double {
                            Text("\(Int(confidence * 100))%")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                                .background(Color.white.opacity(0.8))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .cornerRadius(4)
                                .position(x: ballX, y: ballY - ballRadius - 20)
                        }
                    }
                )
        }
    }
} 
