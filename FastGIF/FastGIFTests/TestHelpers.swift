//
//  TestHelpers.swift
//  FastGIFTests
//
//  Shared test utilities for creating test CGImages and Frames.
//

import XCTest
import CoreGraphics
@testable import FastGIF

extension XCTestCase {

    /// Create a solid-color test CGImage using UIKit graphics context.
    /// - Parameters:
    ///   - width: Image width in pixels (default 10).
    ///   - height: Image height in pixels (default 10).
    ///   - color: Fill color (default solid red).
    /// - Returns: A CGImage of the specified dimensions filled with the given color.
    static func makeTestCGImage(
        width: Int = 10,
        height: Int = 10,
        color: CGColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    ) -> CGImage {
        let size = CGSize(width: width, height: height)
        UIGraphicsBeginImageContext(size)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(color)
        context.fill(CGRect(origin: .zero, size: size))
        let image = context.makeImage()!
        UIGraphicsEndImageContext()
        return image
    }

    /// Create a test Frame wrapping a solid-color CGImage.
    /// - Parameters:
    ///   - width: Image width in pixels (default 10).
    ///   - height: Image height in pixels (default 10).
    ///   - delay: Frame delay in seconds (default 0.1).
    ///   - color: Fill color (default solid red).
    /// - Returns: A Frame containing the generated image.
    static func makeTestFrame(
        width: Int = 10,
        height: Int = 10,
        delay: Double = 0.1,
        color: CGColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    ) -> Frame {
        Frame(
            image: makeTestCGImage(width: width, height: height, color: color),
            delay: delay
        )
    }

    /// Create an array of test Frames with distinct colors.
    /// - Parameters:
    ///   - count: Number of frames to generate.
    ///   - width: Image width in pixels (default 10).
    ///   - height: Image height in pixels (default 10).
    ///   - delay: Frame delay in seconds (default 0.1).
    /// - Returns: An array of Frames with sequentially varying hue.
    static func makeTestFrames(
        count: Int,
        width: Int = 10,
        height: Int = 10,
        delay: Double = 0.1
    ) -> [Frame] {
        (0..<count).map { i in
            let hue = CGFloat(i) / CGFloat(max(count, 1))
            let color = CGColor(
                red: abs(sin(hue * .pi * 2)),
                green: abs(sin(hue * .pi * 2 + .pi / 3)),
                blue: abs(sin(hue * .pi * 2 + 2 * .pi / 3)),
                alpha: 1
            )
            return makeTestFrame(width: width, height: height, delay: delay, color: color)
        }
    }
}
