import AVFoundation
import UIKit
import CoreImage

class CameraFeedManager: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var error: String?
    
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "session.queue")
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let ciContext = CIContext() // Reusable context
    
    // Frame processing callback
    var onFrameProcessed: ((UIImage, CGRect) -> Void)?
    private var currentGoalRegion: CGRect = .zero
    
    override init() {
        super.init()
        setupSession()
    }
    
    func updateGoalRegion(_ region: CGRect) {
        currentGoalRegion = region
    }
    
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .high
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            error = "Could not access camera"
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                self.videoDeviceInput = videoInput
            } else {
                error = "Could not add video input"
                return
            }
        } catch {
            self.error = "Could not create video input: \(error.localizedDescription)"
            return
        }
        
        // Add video output
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        } else {
            error = "Could not add video output"
            return
        }
        
        session.commitConfiguration()
    }
    
    func startSession() {
        sessionQueue.async {
            print("Attempting to start camera session...")
            self.session.startRunning()
            DispatchQueue.main.async {
                print("Camera session running: \(self.session.isRunning)")
                self.isSessionRunning = self.session.isRunning
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
        }
    }
    
    // Helper to fix image orientation
    func imageWithFixedOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return normalizedImage
    }
}

extension CameraFeedManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return  // Removed print to reduce memory overhead
        }
        
        // Process on background queue to avoid blocking camera
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            // Use the reused context
            guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
            
            // Create UIImage with proper orientation
            let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
            let fixedImage = self.imageWithFixedOrientation(uiImage)
            
            // Release cgImage immediately after creating UIImage
            // UIImage retains what it needs
            
            // Callback on main thread
            DispatchQueue.main.async { [weak self] in
                self?.onFrameProcessed?(fixedImage, self?.currentGoalRegion ?? .zero)
            }
        }
    }
} 