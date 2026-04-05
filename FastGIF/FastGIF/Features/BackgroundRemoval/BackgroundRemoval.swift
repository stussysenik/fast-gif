import Foundation
import Vision
import CoreImage

/// AI-powered background removal using Apple's Vision framework.
/// Zero ML model download — uses on-device person/subject segmentation.
struct RemoveBackground: Stage {
    func process(_ frames: [Frame]) async throws -> [Frame] {
        var results = [Frame]()
        for frame in frames {
            let masked = try removeBackground(from: frame.image)
            results.append(Frame(image: masked, delay: frame.delay))
        }
        return results
    }
}

private func removeBackground(from image: CGImage) throws -> CGImage {
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .accurate
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    guard let result = request.results?.first else {
        return image
    }
    let maskBuffer = result.pixelBuffer
    guard CVPixelBufferGetPixelFormatType(maskBuffer) != 0 else {
        return image // No person detected — return original
    }

    let ciImage = CIImage(cgImage: image)
    let maskImage = CIImage(cvPixelBuffer: maskBuffer)
        .transformed(by: CGAffineTransform(
            scaleX: ciImage.extent.width / CGFloat(CVPixelBufferGetWidth(maskBuffer)),
            y: ciImage.extent.height / CGFloat(CVPixelBufferGetHeight(maskBuffer))
        ))

    let blendFilter = CIFilter(name: "CIBlendWithMask")!
    blendFilter.setValue(ciImage, forKey: kCIInputImageKey)
    blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
    blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let output = blendFilter.outputImage,
          let cgImage = context.createCGImage(output, from: ciImage.extent) else {
        return image
    }
    return cgImage
}
