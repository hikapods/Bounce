import Foundation
import CoreML
import UIKit
import CoreVideo
import CoreImage

struct MLBallDetection {
    let boundingBox: CGRect   // Normalized (0...1)
    let confidence: Float
    let label: String
}

final class MLBallDetector {
    static let shared = MLBallDetector()
    
    private let model: MLModel?
    private let processingQueue = DispatchQueue(label: "com.bouncebacktrainer.mlball", qos: .userInitiated)
    private let targetLabels: Set<String> = ["ball", "soccer", "class0"]
    private let minimumConfidence: Float = 0.6  // Lowered to improve consistency
    
    private init() {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        
        do {
            if let compiledURL = Bundle.main.url(forResource: "best", withExtension: "mlmodelc") {
                model = try MLModel(contentsOf: compiledURL, configuration: configuration)
            } else if let packageURL = Bundle.main.url(forResource: "best", withExtension: "mlpackage") {
                let compiledURL = try MLModel.compileModel(at: packageURL)
                model = try MLModel(contentsOf: compiledURL, configuration: configuration)
            } else {
                print("⚠️ Missing best.mlmodelc / best.mlpackage in bundle.")
                model = nil
            }
        } catch {
            print("⚠️ Failed to load best model: \(error.localizedDescription)")
            model = nil
        }
    }
    
    var isReady: Bool {
        model != nil
    }
    
    private let ciContext = CIContext() // Reusable context for efficiency

    func detectBall(in image: UIImage, completion: @escaping (MLBallDetection?) -> Void) {
        guard let model = model else {
            completion(nil)
            return
        }
        
        processingQueue.async { [weak self] in
            // Ensure image is upright for consistent processing
            let fixedImage = image.fixedOrientation()
            let fullSize = fixedImage.size
            
            var bestDetection: MLBallDetection? = nil
            
            // Strategy 1: Center cropped (original approach)
            // We must adjust coordinates back to full image space if we crop
            let shortSide = min(fullSize.width, fullSize.height)
            let cropX = (fullSize.width - shortSide) / 2.0
            let cropY = (fullSize.height - shortSide) / 2.0
            let cropRect = CGRect(x: cropX, y: cropY, width: shortSide, height: shortSide)
            
            if let buffer1 = fixedImage
                .centerCroppedToSquare()?
                .resized(to: CGSize(width: 960, height: 960))?
                .pixelBuffer(width: 960, height: 960) {
                
                if let detection = self?.runDetection(model: model, buffer: buffer1) {
                    // Convert crop-relative coordinates to full-image coordinates
                    let normRect = detection.boundingBox
                    let absX = cropRect.origin.x + normRect.origin.x * cropRect.width
                    let absY = cropRect.origin.y + normRect.origin.y * cropRect.height
                    let absW = normRect.width * cropRect.width
                    let absH = normRect.height * cropRect.height
                    
                    let finalRect = CGRect(
                        x: absX / fullSize.width,
                        y: absY / fullSize.height,
                        width: absW / fullSize.width,
                        height: absH / fullSize.height
                    )
                    
                    bestDetection = MLBallDetection(
                        boundingBox: finalRect,
                        confidence: detection.confidence,
                        label: detection.label
                    )
                }
            }
            
            // Strategy 2: Full image (no cropping) - in case ball is at edges
            // Only run if Strategy 1 failed or had low confidence
            if bestDetection == nil || bestDetection!.confidence < 0.5 {
                if let buffer2 = fixedImage
                    .resized(to: CGSize(width: 960, height: 960))?
                    .pixelBuffer(width: 960, height: 960) {
                    
                    if let detection = self?.runDetection(model: model, buffer: buffer2) {
                        // Strategy 2 uses the full image (stretched), so normalized coordinates 
                        // map correctly to the full image without adjustment.
                        if bestDetection == nil || detection.confidence > bestDetection!.confidence {
                            bestDetection = detection
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                completion(bestDetection)
            }
        }
    }

    func detectBall(in pixelBuffer: CVPixelBuffer, completion: @escaping (MLBallDetection?) -> Void) {
        guard let model = model else {
            completion(nil)
            return
        }
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            let fullSize = CGSize(width: width, height: height)
            
            var bestDetection: MLBallDetection? = nil
            
            // Strategy 1: Center cropped
            let shortSide = min(width, height)
            let cropX = (width - shortSide) / 2.0
            let cropY = (height - shortSide) / 2.0
            let cropRect = CGRect(x: cropX, y: cropY, width: shortSide, height: shortSide)
            
            if let buffer1 = self.resizePixelBuffer(pixelBuffer, crop: cropRect, to: CGSize(width: 960, height: 960)) {
                 if let detection = self.runDetection(model: model, buffer: buffer1) {
                    // Convert crop-relative coordinates to full-image coordinates
                    let normRect = detection.boundingBox
                    let absX = cropRect.origin.x + normRect.origin.x * cropRect.width
                    let absY = cropRect.origin.y + normRect.origin.y * cropRect.height
                    let absW = normRect.width * cropRect.width
                    let absH = normRect.height * cropRect.height
                    
                    let finalRect = CGRect(
                        x: absX / fullSize.width,
                        y: absY / fullSize.height,
                        width: absW / fullSize.width,
                        height: absH / fullSize.height
                    )
                    
                    bestDetection = MLBallDetection(
                        boundingBox: finalRect,
                        confidence: detection.confidence,
                        label: detection.label
                    )
                 }
            }
            
            // Strategy 2: Full image
             if bestDetection == nil || bestDetection!.confidence < 0.5 {
                if let buffer2 = self.resizePixelBuffer(pixelBuffer, crop: nil, to: CGSize(width: 960, height: 960)) {
                     if let detection = self.runDetection(model: model, buffer: buffer2) {
                        if bestDetection == nil || detection.confidence > bestDetection!.confidence {
                            bestDetection = detection
                        }
                     }
                }
             }
             
             DispatchQueue.main.async {
                 completion(bestDetection)
             }
        }
    }
    
    private func resizePixelBuffer(_ buffer: CVPixelBuffer, crop: CGRect?, to size: CGSize) -> CVPixelBuffer? {
        var ciImage = CIImage(cvPixelBuffer: buffer)
        
        if let crop = crop {
            // CIImage coordinates have origin at bottom-left, but CVPixelBuffer is usually top-left.
            // However, CIImage(cvPixelBuffer:) usually preserves the buffer's orientation.
            // Let's assume standard top-left for now, but CIImage cropping uses a rect.
            // We need to be careful about coordinate systems.
            // For simple center crop, it should be fine if we just crop the rect.
            // But wait, CIImage origin is bottom-left.
            // If we want top-left crop (x, y, w, h), in CI coords it is (x, height - y - h, w, h).
            
            let height = CGFloat(CVPixelBufferGetHeight(buffer))
            let ciCropRect = CGRect(
                x: crop.origin.x,
                y: height - crop.origin.y - crop.height,
                width: crop.width,
                height: crop.height
            )
            
            ciImage = ciImage.cropped(to: ciCropRect)
            // Translate to origin 0,0
            ciImage = ciImage.transformed(by: CGAffineTransform(translationX: -ciCropRect.origin.x, y: -ciCropRect.origin.y))
        }
        
        let scaleX = size.width / ciImage.extent.width
        let scaleY = size.height / ciImage.extent.height
        ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Create output buffer
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let outputBuffer = pixelBuffer else {
            return nil
        }
        
        ciContext.render(ciImage, to: outputBuffer)
        return outputBuffer
    }
    
    private func runDetection(model: MLModel, buffer: CVPixelBuffer) -> MLBallDetection? {
        do {
            // Lower confidence threshold to catch more detections - model is well trained
            let inputProvider = try MLDictionaryFeatureProvider(dictionary: [
                "image": buffer,
                "iouThreshold": 0.5,  // Lowered from 0.7 to allow more overlapping detections
                "confidenceThreshold": 0.15  // Lowered from 0.25 to catch lower confidence detections
            ])
                
            let output = try model.prediction(from: inputProvider)
            
            guard
                let confidenceArray = output.featureValue(for: "confidence")?.multiArrayValue,
                let coordinatesArray = output.featureValue(for: "coordinates")?.multiArrayValue
            else {
                return nil
            }
            
            return parseDetections(
                confidenceArray: confidenceArray,
                coordinatesArray: coordinatesArray
            )
        } catch {
            print("⚠️ best.mlpackage prediction failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func parseDetections(confidenceArray: MLMultiArray, coordinatesArray: MLMultiArray) -> MLBallDetection? {
        let coordinateCount = coordinatesArray.count
        guard coordinateCount > 0 else { return nil }
        
        let boxes = coordinateCount / 4
        guard boxes > 0 else { return nil }
        
        let classCount = confidenceArray.count / max(boxes, 1)
        guard classCount > 0 else { return nil }
        
        let confidencePointer = confidenceArray.dataPointer.bindMemory(to: Float32.self, capacity: confidenceArray.count)
        let coordinatesPointer = coordinatesArray.dataPointer.bindMemory(to: Float32.self, capacity: coordinateCount)
        
        var bestDetection: MLBallDetection?
        for boxIndex in 0..<boxes {
            var bestClassIndex = 0
            var bestConfidence: Float32 = 0.0
            
            for classIndex in 0..<classCount {
                let idx = boxIndex * classCount + classIndex
                let confidence = confidencePointer[idx]
                
                if confidence > bestConfidence {
                    bestConfidence = confidence
                    bestClassIndex = classIndex
                }
            }
            
            guard bestConfidence >= minimumConfidence else { continue }
            
            let label = labelName(for: bestClassIndex)
            guard isBallClass(label: label, classIndex: bestClassIndex) else { continue }
            
            let baseIndex = boxIndex * 4
            let x = coordinatesPointer[baseIndex]
            let y = coordinatesPointer[baseIndex + 1]
            let width = coordinatesPointer[baseIndex + 2]
            let height = coordinatesPointer[baseIndex + 3]
            
            let rect = CGRect(
                x: CGFloat(x - width / 2),
                y: CGFloat(y - height / 2),
                width: CGFloat(width),
                height: CGFloat(height)
            ).clampedToUnit()
            
            // Aspect Ratio Check - More lenient for perspective/distortion
            // A ball should be roughly square (1:1 ratio).
            // We allow more deviation to account for perspective, motion blur, and distortion.
            let aspectRatio = rect.width / rect.height
            let maxDeviation: CGFloat = 0.5 // Allow 0.5 to 1.5 (more lenient)
            
            guard abs(aspectRatio - 1.0) <= maxDeviation else {
                // Only log if confidence is high to reduce noise
                if bestConfidence > 0.5 {
                    print("DEBUG: Filtered out \(label) due to aspect ratio: \(String(format: "%.2f", aspectRatio))")
                }
                continue
            }
            
            // Size Check - Reject huge boxes (likely floor/shoes/garbage)
            // A ball shouldn't take up more than 50% of the screen width/height
            if rect.width > 0.5 || rect.height > 0.5 {
                print("DEBUG: Filtered out \(label) due to size: \(String(format: "%.2f x %.2f", rect.width, rect.height))")
                continue
            }
            
            let detection = MLBallDetection(
                boundingBox: rect,
                confidence: bestConfidence,
                label: label
            )
            
            if let existing = bestDetection {
                if detection.confidence > existing.confidence {
                    bestDetection = detection
                }
            } else {
                bestDetection = detection
            }
        }
        
        return bestDetection
    }
    
    private func labelName(for index: Int) -> String {
        "class\(index)"
    }
    
    private func isBallClass(label: String, classIndex: Int) -> Bool {
        // DEBUG: Print what we found, but enforce the filter
        print("DEBUG: Detected class \(classIndex) (\(label))")
        
        if targetLabels.contains(label.lowercased()) { return true }
        return classIndex == 0
    }
}

private extension CGRect {
    func clampedToUnit() -> CGRect {
        let minX = max(0, min(1, origin.x))
        let minY = max(0, min(1, origin.y))
        let width = max(0, min(1 - minX, size.width))
        let height = max(0, min(1 - minY, size.height))
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}

private extension UIImage {
    func fixedOrientation() -> UIImage {
        if imageOrientation == .up {
            return self
        }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return normalizedImage
    }
    
    func centerCroppedToSquare() -> UIImage? {
        let edge = min(size.width, size.height)
        let origin = CGPoint(
            x: (size.width - edge) / 2.0,
            y: (size.height - edge) / 2.0
        )
        
        let cropRect = CGRect(origin: origin, size: CGSize(width: edge, height: edge))
        
        guard let cgImage = cgImage?.cropping(to: cropRect) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
    
    func resized(to targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }
        
        guard let cgImage = self.cgImage else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return buffer
    }
}

