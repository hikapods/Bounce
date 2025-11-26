import SwiftUI

struct MLBallDetectionView: View {
    @StateObject private var cameraManager = CameraFeedManager()
    @State private var latestFrame: UIImage?
    @State private var detection: MLBallDetection?
    @State private var detectionStatus = "Waiting for camera..."
    @State private var isRunningInference = false
    @State private var modelReady = MLBallDetector.shared.isReady
    @State private var lastDetectionTime = Date.distantPast
    
    var body: some View {
        VStack(spacing: 16) {
            Text("ML Package Ball Detector")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top)
            
            statusRow
            
            previewSection
                .frame(height: 320)
                .background(Color.black.opacity(0.85))
                .cornerRadius(14)
                .padding(.horizontal)
            
            detectionDetails
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            
            Spacer()
            
            Button(action: rerunDetection) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Force Rerun")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(modelReady ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!modelReady || latestFrame == nil)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear(perform: configureCamera)
        .onDisappear {
            cameraManager.stopSession()
        }
    }
    
    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(modelReady ? (isRunningInference ? Color.orange : Color.green) : Color.red)
                .frame(width: 14, height: 14)
            Text(modelReady ? detectionStatus : "Model failed to load")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal)
    }
    
    private var previewSection: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = latestFrame {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .overlay {
                            if let detection = detection {
                                DetectionOverlay(detection: detection, imageSize: image.size)
                                    .stroke(Color.green, lineWidth: 3)
                                    .overlay(alignment: .topLeading) {
                                        Text(String(format: "%.0f%%", detection.confidence * 100))
                                            .font(.caption)
                                            .padding(6)
                                            .background(Color.green.opacity(0.85))
                                            .foregroundColor(.black)
                                            .cornerRadius(6)
                                            .padding([.leading, .top], 4)
                                    }
                            }
                        }
                } else {
                    Text("Camera feed starting…")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }
    
    private var detectionDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detection Details")
                .font(.headline)
            if let detection = detection {
                Text("Label: \(detection.label)")
                // DEBUG: Show class index if possible, or just rely on label
                // Text("Class Index: ...") // We don't have index in struct yet, but label should be "classN"

                Text(String(format: "Confidence: %.2f", detection.confidence))
                Text(String(format: "Bounding Box: x %.2f  y %.2f  w %.2f  h %.2f",
                            detection.boundingBox.origin.x,
                            detection.boundingBox.origin.y,
                            detection.boundingBox.size.width,
                            detection.boundingBox.size.height))
            } else {
                Text("No ball detected yet.")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func configureCamera() {
        cameraManager.onFrameProcessed = { image, _ in
            latestFrame = image
            
            let now = Date()
            guard !isRunningInference,
                  now.timeIntervalSince(lastDetectionTime) >= 0.1 else { return }
            
            lastDetectionTime = now
            runDetection(on: image)
        }
        cameraManager.startSession()
        
        if !modelReady {
            detectionStatus = "Model unavailable"
        } else {
            detectionStatus = "Ready"
        }
    }
    
    private func runDetection(on image: UIImage) {
        guard modelReady else { return }
        isRunningInference = true
        // detectionStatus = "Processing frame..." // Removed to prevent flickering
        
        MLBallDetector.shared.detectBall(in: image) { result in
            detection = result
            detectionStatus = result == nil ? "No ball detected" : "Ball detected"
            isRunningInference = false
        }
    }
    
    private func rerunDetection() {
        guard let frame = latestFrame, modelReady else { return }
        runDetection(on: frame)
    }
}

private struct DetectionOverlay: Shape {
    let detection: MLBallDetection
    let imageSize: CGSize
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let overlayRect = convertedRect(in: rect)
        path.addRect(overlayRect)
        return path
    }
    
    private func convertedRect(in rect: CGRect) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = rect.width / rect.height
        
        var drawSize: CGSize
        var origin: CGPoint
        
        if imageAspect > containerAspect {
            drawSize = CGSize(width: rect.width, height: rect.width / imageAspect)
            origin = CGPoint(x: 0, y: (rect.height - drawSize.height) / 2)
        } else {
            drawSize = CGSize(width: rect.height * imageAspect, height: rect.height)
            origin = CGPoint(x: (rect.width - drawSize.width) / 2, y: 0)
        }
        
        let normalizedRect = detection.boundingBox
        return CGRect(
            x: origin.x + normalizedRect.origin.x * drawSize.width,
            y: origin.y + normalizedRect.origin.y * drawSize.height,
            width: normalizedRect.width * drawSize.width,
            height: normalizedRect.height * drawSize.height
        )
    }
}

