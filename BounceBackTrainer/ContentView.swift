import SwiftUI
import AVFoundation
import UIKit
import AVKit
import UniformTypeIdentifiers
import PhotosUI

struct ContentView: View {
    @State private var showBallDetection = false
    @State private var showFFTBallDetection = false
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

                    // Blue Ball Detection button
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

                    // Purple FFT Ball Detection button
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

                    let output = FileManager.default.temporaryDirectory
                        .appendingPathComponent("analyzed_output.avi")

                    // Debug: Check if file exists
                    print("Input URL: \(input.path)")
                    print("File exists: \(FileManager.default.fileExists(atPath: input.path))")

                    // No need for securityScopedResource for temp file
                    if FileManager.default.fileExists(atPath: input.path) {
                        print("Analyzing: \(input.path)")
                        OpenCVWrapper.analyzeVideo(input.path, outputPath: output.path)
                        print("Output saved to: \(output.path)")
                        outputURL = output
                        isProcessing = false
                    } else {
                        errorMessage = "Failed to access input video"
                        showError = true
                        isProcessing = false
                    }
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
}

// Ball Detection View using FFT logic
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
                    
                    // FFT detection is commented out but implementation is preserved
                    // let fftResult = OpenCVWrapper.detectBallByFFT(frame) // FFT method kept but not used
                    
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
