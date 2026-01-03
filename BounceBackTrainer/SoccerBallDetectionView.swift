import SwiftUI
import AVFoundation
import UIKit

struct SoccerBallDetectionView: View {
    @State private var showCamera = false
    @State private var cameraPermissionGranted = false
    @State private var isDetecting = false
    @State private var detectedBallPosition: CGPoint?
    @State private var ballConfidence: Double = 0.0
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Soccer Ball Detection")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)
            
            Text("Detect soccer balls in real-time using OpenCV")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                checkCameraPermission()
            }) {
                HStack {
                    Image(systemName: "soccer.ball.inverse")
                        .font(.title2)
                    Text("Start Ball Detection")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            
            if isDetecting {
                VStack(spacing: 10) {
                    Text("Detection Active")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    if let position = detectedBallPosition {
                        Text("Ball detected at: (\(Int(position.x)), \(Int(position.y)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Confidence: \(String(format: "%.2f", ballConfidence))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No ball detected")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .sheet(isPresented: $showCamera) {
            SoccerBallCameraView(
                isDetecting: $isDetecting,
                detectedBallPosition: $detectedBallPosition,
                ballConfidence: $ballConfidence
            )
        }
        .alert("Camera Permission Required", isPresented: .constant(!cameraPermissionGranted && showCamera)) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) {
                showCamera = false
            }
        } message: {
            Text("Camera access is required for ball detection. Please enable camera access in Settings.")
        }
    }
    
    private func checkCameraPermission() {
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
                    }
                }
            }
        case .denied, .restricted:
            cameraPermissionGranted = false
            showCamera = true
        @unknown default:
            cameraPermissionGranted = false
        }
    }
}

struct SoccerBallCameraView: UIViewControllerRepresentable {
    @Binding var isDetecting: Bool
    @Binding var detectedBallPosition: CGPoint?
    @Binding var ballConfidence: Double
    
    func makeUIViewController(context: Context) -> SoccerBallCameraViewController {
        let controller = SoccerBallCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: SoccerBallCameraViewController, context: Context) {
        // Updates handled by delegate
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, SoccerBallCameraViewControllerDelegate {
        let parent: SoccerBallCameraView
        
        init(_ parent: SoccerBallCameraView) {
            self.parent = parent
        }
        
        func didUpdateBallDetection(position: CGPoint?, confidence: Double) {
            let positionString = position != nil ? "(\(position!.x), \(position!.y))" : "nil"
            print("[DEBUG] Delegate called - position: \(positionString), confidence: \(confidence)")
            DispatchQueue.main.async {
                self.parent.detectedBallPosition = position
                self.parent.ballConfidence = confidence
                self.parent.isDetecting = true
                print("[DEBUG] UI updated - isDetecting: \(self.parent.isDetecting)")
            }
        }
    }
}

protocol SoccerBallCameraViewControllerDelegate: AnyObject {
    func didUpdateBallDetection(position: CGPoint?, confidence: Double)
}

class SoccerBallCameraViewController: UIViewController {
    weak var delegate: SoccerBallCameraViewControllerDelegate?
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var detectionTimer: Timer?
    private var closeButton: UIButton?
    private var frameCount = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupDetectionTimer()
        setupCloseButton()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Start capture session on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
            print("[DEBUG] Capture session started")
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
        detectionTimer?.invalidate()
    }
    
    private func setupCamera() {
        print("[DEBUG] Setting up camera...")
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high
        
        guard let camera = AVCaptureDevice.default(for: .video) else {
            print("[DEBUG] Camera not available")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
                print("[DEBUG] Camera input added successfully")
            }
            
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInteractive))
            videoOutput?.alwaysDiscardsLateVideoFrames = true
            
            if captureSession?.canAddOutput(videoOutput!) == true {
                captureSession?.addOutput(videoOutput!)
                print("[DEBUG] Video output added successfully")
            } else {
                print("[DEBUG] Failed to add video output")
            }
            
            setupPreviewLayer()
            print("[DEBUG] Camera setup completed")
            
        } catch {
            print("[DEBUG] Error setting up camera: \(error)")
        }
    }
    
    private func setupPreviewLayer() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.bounds
        
        if let previewLayer = previewLayer {
            view.layer.addSublayer(previewLayer)
            print("[DEBUG] Preview layer added")
        }
    }
    
    private func setupDetectionTimer() {
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            print("[DEBUG] Timer tick - frameCount: \(self.frameCount)")
            // Update detection status based on frame count
            DispatchQueue.main.async {
                if let detectionLabel = self.view.viewWithTag(202) as? UILabel {
                    if self.frameCount == 0 {
                        detectionLabel.text = "Detection: No Frames"
                        detectionLabel.backgroundColor = UIColor.red.withAlphaComponent(0.8)
                    } else {
                        detectionLabel.text = "Detection: \(self.frameCount) Frames"
                        detectionLabel.backgroundColor = UIColor.green.withAlphaComponent(0.8)
                    }
                }
            }
        }
    }
    
    private func setupCloseButton() {
        closeButton = UIButton(type: .system)
        closeButton?.setTitle("✕", for: .normal)
        closeButton?.setTitleColor(.white, for: .normal)
        closeButton?.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        closeButton?.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        closeButton?.layer.cornerRadius = 20
        closeButton?.frame = CGRect(x: 20, y: 50, width: 40, height: 40)
        closeButton?.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        
        if let closeButton = closeButton {
            view.addSubview(closeButton)
        }
        
        // Add a status label to show camera is working
        let statusLabel = UILabel()
        statusLabel.text = "Camera Active"
        statusLabel.textColor = .white
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.backgroundColor = UIColor.green.withAlphaComponent(0.8)
        statusLabel.textAlignment = .center
        statusLabel.layer.cornerRadius = 8
        statusLabel.layer.masksToBounds = true
        statusLabel.frame = CGRect(x: 20, y: 100, width: 100, height: 30)
        statusLabel.tag = 200 // Different tag from ball box
        view.addSubview(statusLabel)
        
        // Add frame counter label
        let frameCounterLabel = UILabel()
        frameCounterLabel.text = "Frames: 0"
        frameCounterLabel.textColor = .white
        frameCounterLabel.font = UIFont.systemFont(ofSize: 12)
        frameCounterLabel.backgroundColor = UIColor.blue.withAlphaComponent(0.8)
        frameCounterLabel.textAlignment = .center
        frameCounterLabel.layer.cornerRadius = 6
        frameCounterLabel.layer.masksToBounds = true
        frameCounterLabel.frame = CGRect(x: 20, y: 140, width: 80, height: 25)
        frameCounterLabel.tag = 201 // Different tag
        view.addSubview(frameCounterLabel)
        
        // Add detection status label
        let detectionLabel = UILabel()
        detectionLabel.text = "Detection: Waiting..."
        detectionLabel.textColor = .white
        detectionLabel.font = UIFont.systemFont(ofSize: 12)
        detectionLabel.backgroundColor = UIColor.orange.withAlphaComponent(0.8)
        detectionLabel.textAlignment = .center
        detectionLabel.layer.cornerRadius = 6
        detectionLabel.layer.masksToBounds = true
        detectionLabel.frame = CGRect(x: 20, y: 170, width: 120, height: 25)
        detectionLabel.tag = 202 // Different tag
        view.addSubview(detectionLabel)
    }
    
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}

extension SoccerBallCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { 
            print("[DEBUG] Failed to get image buffer")
            return 
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { 
            print("[DEBUG] Failed to create CGImage")
            return 
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        // Update frame counter on screen
        DispatchQueue.main.async {
            if let frameCounterLabel = self.view.viewWithTag(201) as? UILabel {
                frameCounterLabel.text = "Frames: \(self.frameCount)"
            }
        }
        
        if frameCount % 30 == 0 { // Log every 30 frames (about once per second)
            print("[DEBUG] Processing frame \(frameCount), image size: \(uiImage.size)")
            
            // Test OpenCV version to make sure it's working
            let openCVVersion = OpenCVWrapper.openCVVersion()
            print("[DEBUG] OpenCV version: \(openCVVersion)")
        }
        
        // Use OpenCV to detect ball
        print("[DEBUG] Attempting ball detection...")
        
        // Update detection status
        DispatchQueue.main.async {
            if let detectionLabel = self.view.viewWithTag(202) as? UILabel {
                detectionLabel.text = "Detection: Processing..."
                detectionLabel.backgroundColor = UIColor.yellow.withAlphaComponent(0.8)
            }
        }
        
        if let ballDetection = OpenCVWrapper.detectBall(inFrame: uiImage) {
            print("[DEBUG] Ball detection result: \(ballDetection)")
            
            let x = ballDetection["x"] as? Int ?? -1
            let y = ballDetection["y"] as? Int ?? -1
            let confidence = ballDetection["confidence"] as? Double ?? 0.0
            let isDetected = ballDetection["isDetected"] as? Bool ?? false
            
            print("[DEBUG] Parsed values - x: \(x), y: \(y), confidence: \(confidence), isDetected: \(isDetected)")
            
            if isDetected && x >= 0 && y >= 0 {
                let position = CGPoint(x: x, y: y)
                print("[DEBUG] Ball detected at position: \(position)")
                delegate?.didUpdateBallDetection(position: position, confidence: confidence)
                
                // Update detection status
                DispatchQueue.main.async {
                    if let detectionLabel = self.view.viewWithTag(202) as? UILabel {
                        detectionLabel.text = "Detection: Ball Found!"
                        detectionLabel.backgroundColor = UIColor.green.withAlphaComponent(0.8)
                    }
                }
                
                // Draw blue box on the preview layer
                DispatchQueue.main.async {
                    self.drawBallBox(at: position, confidence: confidence)
                }
            } else {
                print("[DEBUG] Ball not detected or invalid coordinates")
                delegate?.didUpdateBallDetection(position: nil, confidence: 0.0)
                
                // Update detection status
                DispatchQueue.main.async {
                    if let detectionLabel = self.view.viewWithTag(202) as? UILabel {
                        detectionLabel.text = "Detection: No Ball"
                        detectionLabel.backgroundColor = UIColor.red.withAlphaComponent(0.8)
                    }
                }
                
                DispatchQueue.main.async {
                    self.removeBallBox()
                }
            }
        } else {
            // No ball detected
            print("[DEBUG] OpenCV returned nil - no ball detection")
            delegate?.didUpdateBallDetection(position: nil, confidence: 0.0)
            
            // Update detection status
            DispatchQueue.main.async {
                if let detectionLabel = self.view.viewWithTag(202) as? UILabel {
                    detectionLabel.text = "Detection: OpenCV Error"
                    detectionLabel.backgroundColor = UIColor.red.withAlphaComponent(0.8)
                }
            }
            
            DispatchQueue.main.async {
                self.removeBallBox()
            }
        }
    }
    
    private func drawBallBox(at position: CGPoint, confidence: Double) {
        // Remove existing box
        removeBallBox()
        
        // Convert OpenCV coordinates to screen coordinates
        guard let previewLayer = previewLayer else { return }
        
        // OpenCV coordinates are in the original image space
        // We need to convert them to the preview layer coordinate space
        let imagePoint = CGPoint(x: position.x, y: position.y)
        let screenPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: imagePoint)
        
        // Create blue box
        let boxSize: CGFloat = 60
        let boxView = UIView(frame: CGRect(
            x: screenPoint.x - boxSize/2,
            y: screenPoint.y - boxSize/2,
            width: boxSize,
            height: boxSize
        ))
        
        boxView.layer.borderWidth = 3
        boxView.layer.borderColor = UIColor.blue.cgColor
        boxView.layer.cornerRadius = 8
        boxView.tag = 100 // Tag for removal
        
        // Add confidence label
        let confidenceLabel = UILabel()
        confidenceLabel.text = String(format: "%.1f", confidence * 100) + "%"
        confidenceLabel.textColor = .blue
        confidenceLabel.font = UIFont.boldSystemFont(ofSize: 12)
        confidenceLabel.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        confidenceLabel.textAlignment = .center
        confidenceLabel.layer.cornerRadius = 4
        confidenceLabel.layer.masksToBounds = true
        confidenceLabel.frame = CGRect(x: -10, y: -25, width: 50, height: 20)
        boxView.addSubview(confidenceLabel)
        
        view.addSubview(boxView)
    }
    
    private func removeBallBox() {
        if let existingBox = view.viewWithTag(100) {
            existingBox.removeFromSuperview()
        }
    }
}

#Preview {
    SoccerBallDetectionView()
} 
