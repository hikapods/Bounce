import SwiftUI
import AVFoundation
import UIKit
import AVKit
import UniformTypeIdentifiers
import PhotosUI

struct ContentView: View {
    @State private var showBallDetection = false
    @State private var showFFTBallDetection = false
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
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tools")
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.white)
                            Text("Record, analyze, and test live detection modes.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        
                        // Training clips
                        glassCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Training clips")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Capture or load a drill to analyze.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                                Image(systemName: "film")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            VStack(spacing: 12) {
                                Button {
                                    checkCameraPermissionForRecording()
                                } label: {
                                    PrimaryRow(
                                        icon: "camera.circle.fill",
                                        title: "Record training clip",
                                        subtitle: "Use the rear camera to capture a drill."
                                    )
                                }
                                .sheet(isPresented: $showCamera) {
                                    CameraView { url in
                                        if let url = url {
                                            inputURL = url
                                        }
                                    }
                                }
                                
                                PhotosPicker(
                                    selection: $selectedItem,
                                    matching: .videos
                                ) {
                                    PrimaryRow(
                                        icon: "photo.on.rectangle.angled",
                                        title: "Choose from library",
                                        subtitle: "Use an existing training video."
                                    )
                                }
                                .onChange(of: selectedItem) { newItem in
                                    Task {
                                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                            let tempURL = FileManager.default.temporaryDirectory
                                                .appendingPathComponent("input_video.mp4")
                                            try? data.write(to: tempURL)
                                            inputURL = tempURL
                                        }
                                    }
                                }
                                
                                if let inputURL = inputURL {
                                    VideoPlayer(player: AVPlayer(url: inputURL))
                                        .frame(height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                        .padding(.top, 4)
                                }
                                
                                Button {
                                    runAnalysis()
                                } label: {
                                    HStack {
                                        if isProcessing {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                                .tint(.white)
                                                .padding(.trailing, 6)
                                        }
                                        Image(systemName: "wand.and.stars")
                                        Text(isProcessing ? "Analyzing…" : "Analyze training clip")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(inputURL == nil || isProcessing ? Color.gray : Color.green)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .disabled(inputURL == nil || isProcessing)
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Live detection
                        glassCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Live detection")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("Experimental live tracking modes.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            VStack(spacing: 12) {
                                Button {
                                    checkCameraPermissionForLive()
                                } label: {
                                    PrimaryRow(
                                        icon: "camera.viewfinder",
                                        title: "Live camera mode",
                                        subtitle: "Preview the target and kick setup."
                                    )
                                }
                                .sheet(isPresented: $showLiveCamera) {
                                    LiveCameraView()
                                }
                                
                                Button {
                                    showBallDetection = true
                                } label: {
                                    PrimaryRow(
                                        icon: "soccerball",
                                        title: "Live ball detection",
                                        subtitle: "FFT + fallback detector (beta)."
                                    )
                                }
                                .sheet(isPresented: $showBallDetection) {
                                    BallDetectionView()
                                        .preferredColorScheme(.dark)
                                }
                                
                                Button {
                                    showFFTBallDetection = true
                                } label: {
                                    SecondaryRow(
                                        icon: "waveform.path.ecg",
                                        title: "FFT detection (experimental)"
                                    )
                                }
                                .sheet(isPresented: $showFFTBallDetection) {
                                    FFTBallDetectionView()
                                        .preferredColorScheme(.dark)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Results
                        if let outputURL = outputURL {
                            glassCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Results")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Text("Review and export analyzed clips.")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.seal")
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                
                                VStack(spacing: 12) {
                                    Button {
                                        showVideoSheet = true
                                    } label: {
                                        PrimaryRow(
                                            icon: "play.circle.fill",
                                            title: "View analyzed clip",
                                            subtitle: "Watch the overlay with ball impact."
                                        )
                                    }
                                    
                                    Button {
                                        saveVideoToPhotos(url: outputURL)
                                    } label: {
                                        SecondaryRow(
                                            icon: "square.and.arrow.down.fill",
                                            title: "Save to Photos"
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        Spacer(minLength: 24)
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Bounce Back Trainer")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showVideoSheet) {
            if let url = outputURL {
                OutputVideoView(url: url)
                    .preferredColorScheme(.dark)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .preferredColorScheme(.dark)
    }
    
    // Actions
    private func runAnalysis() {
        guard let input = inputURL else { return }
        isProcessing = true
        
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("analyzed_output.avi")
        
        print("Input URL: \(input.path)")
        print("File exists: \(FileManager.default.fileExists(atPath: input.path))")
        
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
    }
    
    private func checkCameraPermissionForLive() {
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
                        errorMessage = "Camera access is required for live camera mode."
                        showError = true
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Please enable camera access in Settings."
            showError = true
        @unknown default:
            errorMessage = "Unknown camera permission status."
            showError = true
        }
    }
    
    private func checkCameraPermissionForRecording() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermissionGranted = granted
                    if granted {
                        showCamera = true
                    } else {
                        errorMessage = "Camera access is required to record clips."
                        showError = true
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Please enable camera access in Settings."
            showError = true
        @unknown default:
            errorMessage = "Unknown camera permission status."
            showError = true
        }
    }
    
    private func saveVideoToPhotos(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    errorMessage = "Please allow access to Photos in Settings."
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
    
    // UI helpers
    private func glassCard<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(16)
            .background(Color.white.opacity(0.08))
            .background(.ultraThinMaterial.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}
private struct PrimaryRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SecondaryRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
            Text(title)
                .font(.subheadline)
            Spacer()
        }
        .foregroundColor(.white.opacity(0.9))
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                
                // Perform FFT-based ball detection
                DispatchQueue.global(qos: .userInitiated).async {
                    let startTime = CFAbsoluteTimeGetCurrent()
                    
                    // Use FFT-based ball detection
                    let ballResult = OpenCVWrapper.detectBall(byFFT: frame)
                    
                    // If FFT detection fails, try traditional methods
                    var finalResult = ballResult
                    if let isDetected = ballResult?["isDetected"] as? Bool, !isDetected {
                        // Try traditional ball detection as fallback
                        let traditionalResult = OpenCVWrapper.detectBall(inFrame: frame)
                        if let traditionalDetected = traditionalResult?["isDetected"] as? Bool, traditionalDetected {
                            finalResult = traditionalResult
                            print("⚽ Fallback: Traditional ball detection succeeded")
                        }
                    }
                    
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

// FFT Ball Detection View
struct FFTBallDetectionView: View {
    var body: some View {
        VStack {
            Text("FFT Ball Detection")
                .font(.title)
                .fontWeight(.bold)
            
            Text("FFT-based ball detection view")
                .foregroundColor(.secondary)
            
            // Still gotta add FFT implementation
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
