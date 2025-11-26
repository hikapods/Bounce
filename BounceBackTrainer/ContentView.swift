import SwiftUI
import AVFoundation
import UIKit
import AVKit
import UniformTypeIdentifiers
import PhotosUI
import CoreVideo
import Darwin

struct ContentView: View {
    // @State private var showBallDetection = false  // Ball Detection feature commented out
    // @State private var showFFTBallDetection = false  // FFT feature commented out
    @State private var showMLPackageDetection = false
    @State private var inputURL: URL?
    @State private var outputURL: URL?
    @State private var showVideoPlayer = false
    @State private var showPicker = false
    @State private var showSaveDialog = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showVideoSheet = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var showCamera = false
    @State private var cameraPermissionGranted = false
    @State private var showLiveCamera = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Bounce Back Trainer")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top)

                VStack(spacing: 15) {
                    // Live Camera Button
                    Button(action: {
                        checkCameraPermission()
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Live Camera Mode")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .sheet(isPresented: $showLiveCamera) {
                        LiveCameraView()
                    }

                    Button(action: {
                        checkCameraPermission()
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Record Video")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .sheet(isPresented: $showCamera) {
                        CameraView { url in
                            if let url = url {
                                inputURL = url
                            }
                        }
                    }

                    PhotosPicker(selection: $selectedItem,
                               matching: .videos) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("Choose from Library")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                let tempURL = FileManager.default.temporaryDirectory
                                    .appendingPathComponent("input_video.mp4")
                                try? data.write(to: tempURL)
                                inputURL = tempURL
                            }
                        }
                    }

                    // Blue Ball Detection button - commented out
                    /*
                    Button(action: {
                        showBallDetection = true
                    }) {
                        HStack {
                            Image(systemName: "soccerball")
                            Text("Ball Detection")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .sheet(isPresented: $showBallDetection) {
                        BallDetectionView()
                    }
                    */

                    // Purple FFT Ball Detection button
                    /*
                    Button(action: {
                        showFFTBallDetection = true
                    }) {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                            Text("FFT Ball Detection")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .sheet(isPresented: $showFFTBallDetection) {
                        FFTBallDetectionView()
                    }
                    */

                    // ML Package testing button
                    Button(action: {
                        showMLPackageDetection = true
                    }) {
                        HStack {
                            Image(systemName: "target")
                            Text("ML Package Ball Test")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .sheet(isPresented: $showMLPackageDetection) {
                        MLBallDetectionView()
                    }
                }
                .padding(.horizontal)

                if let inputURL = inputURL {
                    VideoPlayer(player: AVPlayer(url: inputURL))
                        .frame(height: 200)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }

                Button(action: {
                    guard let input = inputURL else { return }
                    isProcessing = true
                    
                    // Process video with ML ball detection
                    processVideoWithMLDetection(inputURL: input)
                }) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.trailing, 5)
                        }
                        Image(systemName: "wand.and.stars")
                        Text(isProcessing ? "Processing..." : "Analyze Video")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(inputURL == nil || isProcessing ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(inputURL == nil || isProcessing)
                .padding(.horizontal)

                if let outputURL = outputURL {
                    VStack(spacing: 15) {
                        Button(action: {
                            showVideoSheet = true
                        }) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("View Output Video")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        Button(action: {
                            saveVideoToPhotos(url: outputURL)
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text("Save to Photos")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            .navigationTitle("Bounce Back Trainer")
        }
        .sheet(isPresented: $showVideoSheet) {
            if let url = outputURL {
                OutputVideoView(url: url)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true
            showLiveCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermissionGranted = granted
                    if granted {
                        showLiveCamera = true
                    } else {
                        errorMessage = "Camera access is required to record videos"
                        showError = true
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Please enable camera access in Settings"
            showError = true
        @unknown default:
            errorMessage = "Unknown camera permission status"
            showError = true
        }
    }
    
    private func saveVideoToPhotos(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    errorMessage = "Please allow access to Photos in Settings"
                    showError = true
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("Video saved to Photos successfully")
                    } else {
                        errorMessage = "Error saving video: \(error?.localizedDescription ?? "Unknown error")"
                        showError = true
                    }
                }
            }
        }
    }
    
    // Process video with ML ball detection (Optimized with AVAssetReader)
    private func processVideoWithMLDetection(inputURL: URL) {
        logMemoryUsage(phase: "Before video processing")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let timestamp = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let filename = "analyzed_ball_detection_\(formatter.string(from: timestamp)).mp4"
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let outputURL = documentsPath.appendingPathComponent(filename)
            
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            
            let asset = AVAsset(url: inputURL)
            
            Task {
                do {
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    guard let videoTrack = tracks.first else {
                        DispatchQueue.main.async {
                            self.errorMessage = "No video track found"
                            self.showError = true
                            self.isProcessing = false
                        }
                        return
                    }
                    
                    let videoSize = try await videoTrack.load(.naturalSize)
                    let duration = try await asset.load(.duration)
                    
                    // Setup Reader
                    let reader = try AVAssetReader(asset: asset)
                    let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ])
                    readerOutput.alwaysCopiesSampleData = false
                    reader.add(readerOutput)
                    
                    // Setup Writer
                    guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
                        throw NSError(domain: "App", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create writer"])
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
                    
                    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                    writerInput.expectsMediaDataInRealTime = false
                    
                    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                        assetWriterInput: writerInput,
                        sourcePixelBufferAttributes: [
                            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                            kCVPixelBufferWidthKey as String: Int(videoSize.width),
                            kCVPixelBufferHeightKey as String: Int(videoSize.height),
                            kCVPixelBufferCGImageCompatibilityKey as String: true,
                            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
                        ]
                    )
                    
                    if writer.canAdd(writerInput) {
                        writer.add(writerInput)
                    }
                    
                    reader.startReading()
                    writer.startWriting()
                    writer.startSession(atSourceTime: .zero)
                    
                    // Processing Loop
                    var ballPath: [CGPoint] = []
                    let maxPathPoints = 100
                    var lastValidDetection: MLBallDetection? = nil
                    var lastValidCenter: CGPoint? = nil
                    var framesWithoutDetection = 0
                    let maxFramesWithoutDetection = 5
                    var velocity: CGPoint = .zero
                    
                    let semaphore = DispatchSemaphore(value: 0)
                    var frameCount = 0
                    
                    
                    while reader.status == .reading {
                        guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                            break
                        }
                        
                        guard let readBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
                        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        
                        // Detect
                        var mlDetection: MLBallDetection? = nil
                        MLBallDetector.shared.detectBall(in: readBuffer) { result in
                            mlDetection = result
                            semaphore.signal()
                        }
                        _ = semaphore.wait(timeout: .now() + 0.2)
                        
                        // Logic for path/prediction (same as before)
                        var detectionToUse: MLBallDetection? = nil
                        var centerPoint: CGPoint? = nil
                        
                        if let detection = mlDetection {
                            let bbox = detection.boundingBox
                            let centerX = (bbox.origin.x + bbox.width / 2) * videoSize.width
                            let centerY = (bbox.origin.y + bbox.height / 2) * videoSize.height
                            let currentCenter = CGPoint(x: centerX, y: centerY)
                            
                            if let lastCenter = lastValidCenter {
                                let frameVelocity = CGPoint(x: currentCenter.x - lastCenter.x, y: currentCenter.y - lastCenter.y)
                                velocity = CGPoint(x: velocity.x * 0.7 + frameVelocity.x * 0.3, y: velocity.y * 0.7 + frameVelocity.y * 0.3)
                            }
                            
                            centerPoint = currentCenter
                            detectionToUse = detection
                            lastValidDetection = detection
                            lastValidCenter = currentCenter
                            framesWithoutDetection = 0
                            
                            if detection.confidence >= 0.3 {
                                ballPath.append(currentCenter)
                                if ballPath.count > maxPathPoints { ballPath.removeFirst() }
                            }
                        } else {
                            framesWithoutDetection += 1
                            if framesWithoutDetection <= maxFramesWithoutDetection,
                               let lastDetection = lastValidDetection,
                               let lastCenter = lastValidCenter {
                                
                                let predictedCenter = CGPoint(x: lastCenter.x + velocity.x, y: lastCenter.y + velocity.y)
                                let bbox = lastDetection.boundingBox
                                let predictedX = (predictedCenter.x / videoSize.width) - (bbox.width / 2)
                                let predictedY = (predictedCenter.y / videoSize.height) - (bbox.height / 2)
                                
                                let predictedBbox = CGRect(x: max(0, min(1, predictedX)), y: max(0, min(1, predictedY)), width: bbox.width, height: bbox.height)
                                let decayFactor = Float(1.0 - (Double(framesWithoutDetection) / Double(maxFramesWithoutDetection)) * 0.3)
                                let predictedConfidence = lastDetection.confidence * decayFactor
                                
                                detectionToUse = MLBallDetection(boundingBox: predictedBbox, confidence: predictedConfidence, label: lastDetection.label)
                                centerPoint = predictedCenter
                                lastValidCenter = predictedCenter
                                
                                if predictedConfidence >= 0.2 {
                                    ballPath.append(predictedCenter)
                                    if ballPath.count > maxPathPoints { ballPath.removeFirst() }
                                }
                            }
                        }
                        
                        // Write to output
                        while !writerInput.isReadyForMoreMediaData && writer.status == .writing {
                            Thread.sleep(forTimeInterval: 0.001)
                        }
                        
                        if writer.status == .writing {
                            if let writeBuffer = self.createPixelBuffer(from: adaptor) {
                                // Copy readBuffer to writeBuffer and Draw Overlay
                                self.drawOverlay(source: readBuffer, dest: writeBuffer, detection: detectionToUse, path: ballPath, videoSize: videoSize)
                                adaptor.append(writeBuffer, withPresentationTime: timestamp)
                            }
                        }
                        
                        frameCount += 1
                        if frameCount % 10 == 0 {
                            let progress = min(timestamp.seconds / duration.seconds, 1.0)
                            DispatchQueue.main.async {
                                print("📊 Processing: \(Int(progress * 100))% (\(frameCount) frames)")
                            }
                        }
                    }
                    
                    writerInput.markAsFinished()
                    writer.finishWriting {
                        self.logMemoryUsage(phase: "After video processing")
                        DispatchQueue.main.async {
                            self.isProcessing = false
                            if writer.status == .completed {
                                self.outputURL = outputURL
                                print("✅ Video processed successfully")
                            } else {
                                self.errorMessage = "Processing failed: \(writer.error?.localizedDescription ?? "Unknown")"
                                self.showError = true
                            }
                        }
                    }
                    
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "Error: \(error.localizedDescription)"
                        self.showError = true
                        self.isProcessing = false
                    }
                }
            }
        }
    }
    
    private func createPixelBuffer(from adaptor: AVAssetWriterInputPixelBufferAdaptor) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, adaptor.pixelBufferPool!, &pixelBuffer)
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }
    
    private func drawOverlay(source: CVPixelBuffer, dest: CVPixelBuffer, detection: MLBallDetection?, path: [CGPoint], videoSize: CGSize) {
        // Lock buffers
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(dest, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(dest, [])
        }
        
        let width = CVPixelBufferGetWidth(dest)
        let height = CVPixelBufferGetHeight(dest)
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(dest),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(dest),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return }
        
        // Draw source image into dest context
        if let sourceBase = CVPixelBufferGetBaseAddress(source) {
            let sourceContext = CGContext(
                data: sourceBase,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(source),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )
            
            if let sourceImage = sourceContext?.makeImage() {
                context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        
        // Draw Path
        if path.count > 1 {
            context.setStrokeColor(UIColor.green.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(3.0)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            
            context.beginPath()
            context.move(to: path[0])
            for i in 1..<path.count {
                context.addLine(to: path[i])
            }
            context.strokePath()
            
            context.setFillColor(UIColor.green.withAlphaComponent(0.8).cgColor)
            for point in path {
                let circleRect = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
                context.fillEllipse(in: circleRect)
            }
        }
        
        // Draw Detection
        if let detection = detection {
            let bbox = detection.boundingBox
            let rect = CGRect(
                x: bbox.origin.x * CGFloat(width),
                y: bbox.origin.y * CGFloat(height),
                width: bbox.width * CGFloat(width),
                height: bbox.height * CGFloat(height)
            )
            
            context.setStrokeColor(UIColor.blue.cgColor)
            context.setLineWidth(4.0)
            context.stroke(rect)
            
            UIGraphicsPushContext(context)
            let confidenceText = String(format: "%.0f%%", detection.confidence * 100)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 20),
                .foregroundColor: UIColor.blue,
                .backgroundColor: UIColor.white.withAlphaComponent(0.8)
            ]
            (confidenceText as NSString).draw(at: CGPoint(x: rect.origin.x, y: rect.origin.y - 30), withAttributes: attributes)
            UIGraphicsPopContext()
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
}

// Ball Detection View (using unified detection logic)
struct BallDetectionView: View {
    @State private var detectedBall: [AnyHashable: Any]? = nil
    @State private var lastFrame: UIImage? = nil
    @State private var isProcessing = false
    @State private var frameCount = 0
    @State private var detectionStats = ""
    @State private var debugMode = false
    
    // Temporal consistency tracking
    @State private var ballPositionHistory: [(x: Int, y: Int, confidence: Double)] = []
    @State private var consecutiveDetections = 0
    @State private var lastValidBall: [AnyHashable: Any]? = nil

    var body: some View {
        VStack(spacing: 20) {
            Text("Ball Detection")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)
            
            // Debug mode toggle
            Toggle("Debug Mode", isOn: $debugMode)
                .padding(.horizontal)
                .foregroundColor(.white)
            
            // Status indicator
            HStack {
                Circle()
                    .fill(isProcessing ? Color.orange : Color.green)
                    .frame(width: 12, height: 12)
                Text(isProcessing ? "Processing..." : "Ready")
                    .foregroundColor(.white)
            }
            
            // Detection statistics
            Text(detectionStats)
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal)
            
            // Debug information
            if debugMode {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Debug Info:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)
                    
                    if let ball = detectedBall {
                        Text("Raw Detection: \(String(describing: ball))")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                    
                    Text("Consecutive Detections: \(consecutiveDetections)")
                        .font(.caption2)
                        .foregroundColor(.cyan)
                    
                    Text("Position History: \(ballPositionHistory.count) points")
                        .font(.caption2)
                        .foregroundColor(.cyan)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
            }
            
            // Ball detection results
            if let ball = detectedBall, let isDetected = ball["isDetected"] as? Bool, isDetected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("⚽ Ball Detected!")
                            .font(.headline)
                            .foregroundColor(.green)
                        Spacer()
                        if let confidence = ball["confidence"] as? Double {
                            Text("Conf: \(String(format: "%.2f", confidence))")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    if let x = ball["x"] as? Int, let y = ball["y"] as? Int {
                        Text("Position: (\(x), \(y))")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    
                    if let radius = ball["radius"] as? Int {
                        Text("Radius: \(radius) pixels")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    
                    // Temporal consistency info
                    Text("Consecutive: \(consecutiveDetections)")
                        .font(.caption)
                        .foregroundColor(.cyan)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
            } else {
                Text("No ball detected")
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
            }
            
            Spacer()
            
            // Live camera feed
            // FFT camera feed implementation commented out
            // Original code used CameraFeedForFFTDetection which is now commented out
            // TODO: Replace with CameraFeedManager-based implementation if needed
            /*
            CameraFeedForFFTDetection(onFrame: { frame in
                lastFrame = frame
                frameCount += 1
                isProcessing = true
                detectionStats = "Frame: \(frameCount), Size: \(Int(frame.size.width))x\(Int(frame.size.height))"
                
                // Add 2-second delay for better processing performance
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
                    let startTime = CFAbsoluteTimeGetCurrent()
                    
                    // Use unified ball detection (tries multiple methods automatically)
                    let ballResult = OpenCVWrapper.detectBallUnified(frame)
                    
                    // FFT detection is commented out
                    // let fftResult = OpenCVWrapper.detectBallByFFT(frame) // FFT method commented out
                    
                    // Use unified result directly
                    let finalResult = ballResult
                    
                    // Temporal consistency check
                    var validatedResult = finalResult ?? [:]
                    if let isDetected = validatedResult["isDetected"] as? Bool, isDetected,
                       let x = validatedResult["x"] as? Int, let y = validatedResult["y"] as? Int,
                       let confidence = validatedResult["confidence"] as? Double {
                        
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
                                consecutiveDetections += 1
                                lastValidBall = validatedResult
                            } else {
                                consecutiveDetections = 0
                                validatedResult = lastValidBall ?? validatedResult // Use last valid detection
                            }
                        } else {
                            consecutiveDetections = 1
                            lastValidBall = validatedResult
                        }
                        
                        // Only accept detection if we have consistent detections (reduced requirement)
                        if consecutiveDetections >= 1 {
                            validatedResult = validatedResult
                        } else {
                            validatedResult = lastValidBall ?? validatedResult
                        }
                    } else {
                        consecutiveDetections = 0
                        ballPositionHistory.removeAll()
                    }
                    
                    let processingTime = CFAbsoluteTimeGetCurrent() - startTime
                    
                    DispatchQueue.main.async {
                        detectedBall = validatedResult
                        isProcessing = false
                        
                        // Update stats with processing time
                        if let isDetected = validatedResult["isDetected"] as? Bool {
                            detectionStats = "Frame: \(frameCount), Processing: \(String(format: "%.3f", processingTime))s, Detected: \(isDetected)"
                        }
                        
                        // Log detection results for debugging
                        if let isDetected = validatedResult["isDetected"] as? Bool, isDetected {
                            print("⚽ Ball Detection: Ball found at frame \(frameCount)")
                            if let x = validatedResult["x"] as? Int, let y = validatedResult["y"] as? Int {
                                print("   Position: (\(x), \(y))")
                            }
                        }
                    }
                }
            })
            .frame(height: 300)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.blue, lineWidth: 2)
            )
            */
            
            // Placeholder view - FFT camera feed disabled
            VStack {
                Text("Camera feed disabled")
                    .foregroundColor(.secondary)
                    .padding()
                Text("FFT implementation has been commented out")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(height: 300)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
        }
        .onAppear {
            startCamera()
        }
        .sheet(isPresented: .constant(true)) {
            // Camera feed is embedded in the view
        }
    }
    
    private func startCamera() {
        print("Ball Detection: Camera started automatically")
    }
}

// FFT Ball Detection View (placeholder - you may need to implement this)
/*
struct FFTBallDetectionView: View {
    var body: some View {
        VStack {
            Text("FFT Ball Detection")
                .font(.title)
                .fontWeight(.bold)
            
            Text("FFT-based ball detection view")
                .foregroundColor(.secondary)
            
            // Add your FFT ball detection implementation here
        }
        .padding()
    }
}
*/

struct VideoDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.movie] }
    
    var url: URL?
    
    init(url: URL?) {
        self.url = url
    }
    
    init(configuration: ReadConfiguration) throws {
        url = nil
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = url else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try FileWrapper(url: url, options: .immediate)
    }
} 
