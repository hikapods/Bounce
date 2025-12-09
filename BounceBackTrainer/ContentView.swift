import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import Photos

struct ContentView: View {
    @State private var showLiveCamera = false
    @State private var showCamera = false
    @State private var showMLBallDetection = false
    @State private var showFFTBallDetection = false
    @State private var showVideoSheet = false

    @State private var inputURL: URL?
    @State private var outputURL: URL?

    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var cameraPermissionGranted = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        trainingClipsCard
                        liveDetectionCard
                        if outputURL != nil {
                            resultsCard
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
        .sheet(isPresented: $showLiveCamera) {
            LiveCameraView()
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showCamera) {
            CameraView { url in
                if let url = url {
                    inputURL = url
                }
            }
        }
        .sheet(isPresented: $showMLBallDetection) {
            MLBallDetectionView()
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showFFTBallDetection) {
            FFTBallDetectionView()
                .preferredColorScheme(.dark)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .preferredColorScheme(.dark)
    }

    private var headerSection: some View {
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
    }

    private var trainingClipsCard: some View {
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
    }

    private var liveDetectionCard: some View {
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

                Button {
                    showMLBallDetection = true
                } label: {
                    PrimaryRow(
                        icon: "soccerball",
                        title: "ML ball detector",
                        subtitle: "Direct view of model predictions (beta)."
                    )
                }

                Button {
                    showFFTBallDetection = true
                } label: {
                    SecondaryRow(
                        icon: "waveform.path.ecg",
                        title: "FFT detection (experimental)"
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    private var resultsCard: some View {
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

            if let outputURL = outputURL {
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
        }
        .padding(.horizontal)
    }

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
                    if !success {
                        self.errorMessage = "Error saving video: \(error?.localizedDescription ?? "Unknown error")"
                        self.showError = true
                    }
                }
            }
        }
    }

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

struct FFTBallDetectionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("FFT Ball Detection")
                .font(.title2.weight(.semibold))
            Text("FFT-based detection UI is not wired yet.\nML live detection is available from the main tools screen.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
