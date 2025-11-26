import AVFoundation
import UIKit
import CoreVideo

class VideoRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionAtSourceTime: CMTime?
    private var frameBuffer: [(image: UIImage, timestamp: Date)] = []
    private let maxBufferDuration: TimeInterval = 0.06 // 60ms buffer before detection
    private let maxRecordingDuration: TimeInterval = 1.8 // 1.8 seconds (1800ms) recording duration
    private let bufferQueue = DispatchQueue(label: "com.bouncebacktrainer.videobuffer")
    private let recordingQueue = DispatchQueue(label: "com.bouncebacktrainer.recording", qos: .userInitiated)
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var autoStopTimer: Timer?
    var onRecordingComplete: ((URL?) -> Void)?
    
    private let frameRate: Int32 = 30
    private let videoSize: CGSize
    
    init(videoSize: CGSize = CGSize(width: 1920, height: 1080)) {
        self.videoSize = videoSize
        super.init()
    }
    
    // Add frame to buffer (always running when ball detection is active)
    func addFrameToBuffer(_ image: UIImage) {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            
            // Add frame to buffer
            self.frameBuffer.append((image: image, timestamp: now))
            
            // Keep only last 60ms of frames (for pre-capture buffer)
            let cutoffTime = now.addingTimeInterval(-self.maxBufferDuration)
            self.frameBuffer.removeAll { $0.timestamp < cutoffTime }
        }
    }
    
    // Start recording (called when ball is detected)
    func startRecording(outputURL: URL, completion: @escaping (Bool, Error?) -> Void) {
        guard !isRecording else {
            completion(false, NSError(domain: "VideoRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Already recording"]))
            return
        }
        
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        do {
            // Create video writer
            videoWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            
            // Video input settings
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(videoSize.width),
                AVVideoHeightKey: Int(videoSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6000000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            
            videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoWriterInput?.expectsMediaDataInRealTime = true
            
            guard let videoWriterInput = videoWriterInput,
                  let writer = videoWriter,
                  writer.canAdd(videoWriterInput) else {
                completion(false, NSError(domain: "VideoRecorder", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"]))
                return
            }
            
            writer.add(videoWriterInput)
            
            // Create pixel buffer adaptor once (must be created after adding input to writer)
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoWriterInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: Int(videoSize.width),
                    kCVPixelBufferHeightKey as String: Int(videoSize.height)
                ]
            )
            
            // Start writing session
            writer.startWriting()
            sessionAtSourceTime = nil
            recordingStartTime = Date()
            isRecording = true
            
            // Write buffered frames first (1 second before detection)
            writeBufferedFrames()
            
            // Start timer for duration tracking (must be on main thread)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self = self, let startTime = self.recordingStartTime else { return }
                    self.recordingDuration = Date().timeIntervalSince(startTime)
                }
                RunLoop.current.add(self.timer!, forMode: .common)
                
                // Auto-stop timer - stop recording after maxRecordingDuration (1.8 seconds)
                self.autoStopTimer = Timer.scheduledTimer(withTimeInterval: self.maxRecordingDuration, repeats: false) { [weak self] _ in
                    self?.autoStopRecording()
                }
                RunLoop.current.add(self.autoStopTimer!, forMode: .common)
            }
            
            completion(true, nil)
        } catch {
            completion(false, error)
        }
    }
    
    // Write buffered frames (1 second before detection)
    private func writeBufferedFrames() {
        recordingQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.videoWriter,
                  let input = self.videoWriterInput,
                  let adaptor = self.pixelBufferAdaptor,
                  writer.status == .writing else { return }
            
            let bufferFrames = self.frameBuffer
            let bufferStartTime = bufferFrames.first?.timestamp ?? Date()
            
            for (_, frameData) in bufferFrames.enumerated() {
                let timeSinceBufferStart = frameData.timestamp.timeIntervalSince(bufferStartTime)
                let presentationTime = CMTime(seconds: timeSinceBufferStart, preferredTimescale: self.frameRate)
                
                if let pixelBuffer = self.imageToPixelBuffer(frameData.image) {
                    if self.sessionAtSourceTime == nil {
                        writer.startSession(atSourceTime: presentationTime)
                        self.sessionAtSourceTime = presentationTime
                    }
                    
                    if input.isReadyForMoreMediaData {
                        adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                    }
                }
            }
        }
    }
    
    // Append frame during recording (thread-safe, uses serial queue)
    func appendFrame(_ image: UIImage) {
        guard isRecording else { return }
        
        // Use serial queue to ensure frames are appended in order
        recordingQueue.async { [weak self] in
            guard let self = self,
                  self.isRecording,
                  let writer = self.videoWriter,
                  let input = self.videoWriterInput,
                  let adaptor = self.pixelBufferAdaptor,
                  writer.status == .writing,
                  let startTime = self.recordingStartTime else { return }
            
            let currentTime = Date()
            let timeSinceStart = currentTime.timeIntervalSince(startTime)
            let presentationTime = CMTime(seconds: timeSinceStart, preferredTimescale: self.frameRate)
            
            if self.sessionAtSourceTime == nil {
                writer.startSession(atSourceTime: presentationTime)
                self.sessionAtSourceTime = presentationTime
            }
            
            guard let pixelBuffer = self.imageToPixelBuffer(image) else { return }
            
            // Append using the pre-created adaptor
            if input.isReadyForMoreMediaData {
                adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            }
        }
    }
    
    // Auto-stop recording after duration
    private func autoStopRecording() {
        stopRecording { [weak self] url in
            self?.onRecordingComplete?(url)
        }
    }
    
    // Stop recording
    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording else {
            completion(nil)
            return
        }
        
        // Invalidate timers on main thread
        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
            self?.autoStopTimer?.invalidate()
            self?.autoStopTimer = nil
        }
        
        guard let writer = videoWriter,
              let input = videoWriterInput else {
            DispatchQueue.main.async {
                self.isRecording = false
            }
            completion(nil)
            return
        }
        
        input.markAsFinished()
        
        writer.finishWriting { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            
            DispatchQueue.main.async {
                self.isRecording = false
                self.recordingDuration = 0
                self.recordingStartTime = nil
                self.sessionAtSourceTime = nil
                self.pixelBufferAdaptor = nil
                
                if writer.status == .completed {
                    completion(writer.outputURL)
                } else {
                    print("Video recording error: \(writer.error?.localizedDescription ?? "Unknown")")
                    completion(nil)
                }
            }
        }
    }
    
    // Convert UIImage to CVPixelBuffer
    private func imageToPixelBuffer(_ image: UIImage) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferWidthKey: Int(videoSize.width),
            kCVPixelBufferHeightKey: Int(videoSize.height),
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32ARGB
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(videoSize.width),
            Int(videoSize.height),
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
            width: Int(videoSize.width),
            height: Int(videoSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        guard let ctx = context, let cgImage = image.cgImage else {
            return nil
        }
        
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: videoSize))
        
        return buffer
    }
    
    func reset() {
        stopRecording { _ in }
        bufferQueue.async { [weak self] in
            self?.frameBuffer.removeAll()
        }
        pixelBufferAdaptor = nil
        onRecordingComplete = nil
    }
}

