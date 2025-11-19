import Foundation
import CoreML
import UIKit
import CoreVideo

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
    private let minimumConfidence: Float = 0.35
    
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
    
    func detectBall(in image: UIImage, completion: @escaping (MLBallDetection?) -> Void) {
        guard let model = model else {
            completion(nil)
            return
        }
        
        processingQueue.async { [weak self] in
            guard let buffer = image
                .fixedOrientation()
                .centerCroppedToSquare()?
                .resized(to: CGSize(width: 960, height: 960))?
                .pixelBuffer(width: 960, height: 960) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            do {
                let inputProvider = try MLDictionaryFeatureProvider(dictionary: [
                    "image": buffer,
                    "iouThreshold": 0.7,
                    "confidenceThreshold": 0.25
                ])
                
                let output = try model.prediction(from: inputProvider)
                
                guard
                    let confidenceArray = output.featureValue(for: "confidence")?.multiArrayValue,
                    let coordinatesArray = output.featureValue(for: "coordinates")?.multiArrayValue
                else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                let candidate = self?.parseDetections(
                    confidenceArray: confidenceArray,
                    coordinatesArray: coordinatesArray
                )
                
                DispatchQueue.main.async {
                    completion(candidate)
                }
            } catch {
                print("⚠️ best.mlpackage prediction failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
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

