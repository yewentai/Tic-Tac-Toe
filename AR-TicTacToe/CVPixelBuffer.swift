//
//  CVPixelBuffer.swift
//  AR-TicTacToe
//
//  Created by jeffee hsiung on 5/8/24.
//  Copyright © 2024 Bjarne Møller Lundgren. All rights reserved.
//

import CoreVideo

extension CVPixelBuffer {
    // Static variable to set a threshold for what counts as significant white pixel presence.
    public static var whitePixelThreshold = 200
    
    /// Searches for the highest white pixel that exceeds the threshold.
    /// - Returns: A normalized CGPoint representing the topmost white pixel's location, or nil if below threshold.
    func searchTopPoint() -> CGPoint? {
        // Retrieve dimensions and prepare for pixel access.
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(self)

        CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0)) }

        var returnPoint: CGPoint?
        var whitePixelsCount = 0

        if let baseAddress = CVPixelBufferGetBaseAddress(self) {
            let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

            // Iterate over pixels from top to bottom since we're looking for the topmost significant point.
            outerLoop: for y in (0 ..< height).reversed() {
                for x in (0 ..< width) {
                    // Accessing pixel data for RGB values and determining if it's significant.
                    let pixelIndex = y * bytesPerRow + x * 4
                    let pixel = buffer[pixelIndex]
                    let abovePixel = buffer[min(pixelIndex + bytesPerRow, height * bytesPerRow)]
                    let belowPixel = buffer[max(pixelIndex - bytesPerRow, 0)]
                    let rightPixel = buffer[min(pixelIndex + 4, width * 4)]
                    let leftPixel = buffer[max(pixelIndex - 4, 0)]

                    // Checking connectivity and significance of a white pixel and its neighbors.
                    if pixel > 0 && abovePixel > 0 && belowPixel > 0 && rightPixel > 0 && leftPixel > 0 {
                        let newPoint = CGPoint(x: x, y: y)
                        returnPoint = CGPoint(x: newPoint.x / CGFloat(width), y: newPoint.y / CGFloat(height))
                        whitePixelsCount += 1
                        if whitePixelsCount >= CVPixelBuffer.whitePixelThreshold {
                            break outerLoop
                        }
                    }
                }
            }
        }
        
        // Evaluate the number of significant pixels detected.
        if whitePixelsCount < CVPixelBuffer.whitePixelThreshold {
            returnPoint = nil
        }
        
        return returnPoint
    }
    
    func searchBottomPoint() -> CGPoint? {
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(self)

        CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0)) }

        var returnPoint: CGPoint?
        var whitePixelsCount = 0

        if let baseAddress = CVPixelBufferGetBaseAddress(self) {
            let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

            // Search from bottom to top.
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let pixelIndex = y * bytesPerRow + x * 4
                    let pixel = buffer[pixelIndex]
                    let abovePixel = buffer[min(pixelIndex + bytesPerRow, height * bytesPerRow)]
                    let belowPixel = buffer[max(pixelIndex - bytesPerRow, 0)]
                    let rightPixel = buffer[min(pixelIndex + 4, width * 4)]
                    let leftPixel = buffer[max(pixelIndex - 4, 0)]

                    if pixel > 0 && abovePixel > 0 && belowPixel > 0 && rightPixel > 0 && leftPixel > 0 {
                        let newPoint = CGPoint(x: x, y: y)
                        returnPoint = CGPoint(x: newPoint.x / CGFloat(width), y: newPoint.y / CGFloat(height))
                        whitePixelsCount += 1
                        if whitePixelsCount >= CVPixelBuffer.whitePixelThreshold {
                            return returnPoint
                        }
                    }
                }
            }
        }

        return nil
    }

    func searchMidPoint() -> CGPoint? {
        guard let topPoint = searchTopPoint(), let bottomPoint = searchBottomPoint() else {
            return nil
        }

        // Calculate the midpoint between the top and bottom points.
        let midX = (topPoint.x + bottomPoint.x) / 2
        let midY = (topPoint.y + bottomPoint.y) / 2
        return CGPoint(x: midX, y: midY)
    }
    
}
