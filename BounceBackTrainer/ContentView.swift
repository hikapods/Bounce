import SwiftUI
import AVFoundation
import UIKit
import AVKit
import UniformTypeIdentifiers
import PhotosUI
import CoreVideo

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
    
    // Process video with ML ball detection (similar to LiveCameraView)
    private func processVideoWithMLDetection(inputURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let timestamp = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let filename = "analyzed_ball_detection_\(formatter.string(from: timestamp)).mp4"
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let outputURL = documentsPath.appendingPathComponent(filename)
            
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            
            // Create video asset
            let asset = AVAsset(url: inputURL)
            
            // Use async loading for tracks (iOS 16+)
            Task {
                do {
                    let tracks = try await asset.loadTracks(withMediaType: .video)
                    guard let videoTrack = tracks.first else {
                        DispatchQueue.main.async {
                            errorMessage = "Failed to process video: No video track found"
                            showError = true
                            isProcessing = false
                        }
                        return
                    }
                    
                    let videoSize = try await videoTrack.load(.naturalSize)
                    let frameRate = videoTrack.nominalFrameRate
                    let duration = try await asset.load(.duration)
                    
                    // Setup video writer
                    guard let videoWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
                        DispatchQueue.main.async {
                            errorMessage = "Failed to create video writer"
                            showError = true
                            isProcessing = false
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
                            errorMessage = "Failed to add video input"
                            showError = true
                            isProcessing = false
                        }
                        return
                    }
                    
                    videoWriter.add(videoWriterInput)
                    
                    // Create pixel buffer adaptor BEFORE starting writing session
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
                            
                            // Detect ball using ML
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
                    
                    // Finish writing
                    videoWriterInput.markAsFinished()
                    videoWriter.finishWriting {
                        DispatchQueue.main.async {
                            self.isProcessing = false
                            
                            if videoWriter.status == .completed {
                                self.outputURL = outputURL
                                print("✅ Video processed successfully: \(outputURL.lastPathComponent)")
                            } else {
                                let errorMsg = videoWriter.error?.localizedDescription ?? "Unknown error"
                                print("❌ Video processing failed: \(errorMsg)")
                                self.errorMessage = "Failed to process video: \(errorMsg)"
                                self.showError = true
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to load video: \(error.localizedDescription)"
                        self.showError = true
                        self.isProcessing = false
                    }
                }
            }
        }
    }
    
    // Draw bounding box on image (same as LiveCameraView)
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
