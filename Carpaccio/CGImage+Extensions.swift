//
//  CGImage+Extensions.swift
//  Carpaccio-OSX
//
//  Created by Markus Piipari on 7.10.2019.
//  Copyright © 2019 Matias Piipari & Co. All rights reserved.
//

import CoreGraphics

public enum CGImageExtensionError: LocalizedError {
    case failedToLoadCGImage
    case failedToOpenCGImage(url: URL)
    case failedToDecodePNGData
    case failedToEncodeAsPNGData
    case failedToConvertColorSpace

    public var errorDescription: String? {
        switch self {
        case .failedToOpenCGImage(let url):
            // TODO: Include to underlying CGImage error
            return "Failed to open image at \(url)"
        case .failedToLoadCGImage:
            // TODO: Include to underlying CGImage error
            return "Failed to load image"
        case .failedToDecodePNGData:
            return "Failed to decode PNG image data"
        case .failedToEncodeAsPNGData:
            return "Failed to encode PNG image data"
        case .failedToConvertColorSpace:
            return "Failed to convert image color space"
        }
    }
}

public extension CGImage {
    var size: CGSize {
        return CGSize(width: width, height: height)
    }

    static func loadCGImage(
        from source: CGImageSource,
        metadata inputMetadata: ImageMetadata? = nil,
        constrainingToSize constrainedSize: CGSize? = nil,
        usingEmbeddedThumbnailIfAvailable allowEmbeddedThumbnail: Bool = false
    ) throws -> CGImage {

        let metadata: ImageMetadata = try {
            if let metadata = inputMetadata {
                return metadata
            }
            return try ImageMetadata(imageSource: source)
        }()

        var options: [String: NSNumber] = [
            kCGImageSourceShouldAllowFloat as String: true as NSNumber,
            (allowEmbeddedThumbnail ? kCGImageSourceCreateThumbnailFromImageIfAbsent : kCGImageSourceCreateThumbnailFromImageAlways) as String: true as NSNumber,
            kCGImageSourceCreateThumbnailWithTransform as String: true as NSNumber,
            kCGImageSourceShouldCacheImmediately as String: true as NSNumber
        ]

        if let constrainedSize = constrainedSize {
            let maximumPixelDimension = constrainedSize.maximumPixelSize(forImageSize: metadata.size)
            options[kCGImageSourceThumbnailMaxPixelSize as String] = maximumPixelDimension as NSNumber
        }

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CGImageExtensionError.failedToLoadCGImage
        }

        return cgImage
    }

    static func loadCGImage(
        from url: URL,
        metadata: ImageMetadata? = nil,
        constrainingToSize constrainedSize: CGSize? = nil,
        usingEmbeddedThumbnailIfAvailable allowEmbeddedThumbnail: Bool = false
    ) throws -> CGImage {

        let options = [kCGImageSourceShouldCache as String: false as NSNumber] as CFDictionary

        guard let source: CGImageSource = CGImageSourceCreateWithURL(url as CFURL, options) else {
            throw CGImageExtensionError.failedToOpenCGImage(url: url)
        }

        return try loadCGImage(from: source, metadata: metadata, constrainingToSize: constrainedSize, usingEmbeddedThumbnailIfAvailable: allowEmbeddedThumbnail)
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

    func convertedToColorSpace(_ colorSpace: CGColorSpace) throws -> CGImage {
        guard let convertedImage = self.copy(colorSpace: colorSpace) else {
            throw CGImageExtensionError.failedToConvertColorSpace
        }
        return convertedImage
    }
}
