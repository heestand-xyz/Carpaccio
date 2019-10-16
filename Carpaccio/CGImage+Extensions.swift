//
//  CGImage+Extensions.swift
//  Carpaccio-OSX
//
//  Created by Markus Piipari on 7.10.2019.
//  Copyright © 2019 Matias Piipari & Co. All rights reserved.
//

import CoreGraphics

public enum CGImageExtensionError: Swift.Error {
    case failedToConvertColorSpace
    case failedToDecodePNGData
    case failedToEncodeAsPNGData
}

public extension CGImage {
    func convertedToColorSpace(_ colorSpace: CGColorSpace) throws -> CGImage {
        guard let convertedImage = self.copy(colorSpace: colorSpace) else {
            throw CGImageExtensionError.failedToConvertColorSpace
        }
        return convertedImage
    }

    static func cgImageFromPNGData(_ pngData: Data) throws -> CGImage {
        guard let source = CGDataProvider(data: pngData as CFData) else {
            throw CGImageExtensionError.failedToDecodePNGData
        }
        guard let image = CGImage(pngDataProviderSource: source, decode: nil, shouldInterpolate: false, intent: .perceptual) else {
            throw CGImageExtensionError.failedToDecodePNGData
        }
        return image
    }

    func encodedAsPNGData(hasAlpha: Bool) throws -> Data {
        guard
            let mutableData = CFDataCreateMutable(nil, 0),
            let imageDestination = CGImageDestinationCreateWithData(mutableData, kUTTypePNG, 1, nil) else {
                throw CGImageExtensionError.failedToEncodeAsPNGData
        }

        let options: [String: Any] = [kCGImagePropertyHasAlpha as String: hasAlpha]

        CGImageDestinationAddImage(imageDestination, self, options as CFDictionary)
        CGImageDestinationFinalize(imageDestination)

        let pngData = mutableData as Data
        return pngData
    }
}
