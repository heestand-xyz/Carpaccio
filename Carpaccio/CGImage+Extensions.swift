//
//  CGImage+Extensions.swift
//  Carpaccio-OSX
//
//  Created by Markus Piipari on 7.10.2019.
//  Copyright © 2019 Matias Piipari & Co. All rights reserved.
//

import CoreGraphics
import CoreImage

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
        thumbnailScheme proposedScheme: ImageLoader.ThumbnailScheme
    ) throws -> CGImage {

        // Ensure we have metadata
        let metadata = try ImageMetadata.loadImageMetadataIfNeeded(from: source, having: inputMetadata)

        // Optional prepare pass for the `decodeFullImageIfEmbeddedThumbnailTooSmall` scheme:
        // see if an embedded thumbnail is large enough
        switch proposedScheme {
        case .decodeFullImageIfEmbeddedThumbnailTooSmall:
            if let candidate = try? loadCGImage(from: source, metadata: metadata, constrainingToSize: constrainedSize, thumbnailScheme: .decodeEmbeddedThumbnail),
                !proposedScheme.shouldLoadFullSizeImage(having: candidate, desiredMaximumPixelDimensions: constrainedSize) {
                return candidate
            }
        default: ()
        }

        // In case the caller didn't provide any size constraints, we will decode
        // the full image _unless_ an embedded thumbnail is explicitly requested
        let thumbnailScheme: ImageLoader.ThumbnailScheme = {
            switch proposedScheme {
            case .decodeEmbeddedThumbnail:
                return proposedScheme
            default:
                if let size = constrainedSize, size.isConstrained {
                    return proposedScheme
                }
                return .decodeFullImage
            }
        }()

        // Main pass: decode either full image or embedded thumbnail, according to scheme
        var options: [String: NSNumber] = [
            kCGImageSourceCreateThumbnailWithTransform as String: true as NSNumber,
            kCGImageSourceShouldAllowFloat as String: true as NSNumber,
            kCGImageSourceShouldCacheImmediately as String: true as NSNumber
        ]

        if let constrainedSize = constrainedSize {
            let maximumPixelDimension = constrainedSize.maximumPixelSize(forImageSize: metadata.size)
            options[kCGImageSourceThumbnailMaxPixelSize as String] = maximumPixelDimension as NSNumber
        }

        switch thumbnailScheme {
        case .decodeFullImage, .decodeFullImageIfEmbeddedThumbnailTooSmall:
            options[kCGImageSourceCreateThumbnailFromImageAlways as String] = true as NSNumber
        case .decodeFullImageIfEmbeddedThumbnailMissing:
            options[kCGImageSourceCreateThumbnailFromImageIfAbsent as String] = true as NSNumber
        case .decodeEmbeddedThumbnail:
            options[kCGImageSourceCreateThumbnailFromImageIfAbsent as String] = false as NSNumber
        }

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CGImageExtensionError.failedToLoadCGImage
        }

        return cgImage
    }

    static func loadCGImage(
        from url: URL,
        metadata inputMetadata: ImageMetadata? = nil,
        constrainingToSize constrainedSize: CGSize? = nil,
        thumbnailScheme: ImageLoader.ThumbnailScheme
    ) throws -> CGImage {

        let options = [kCGImageSourceShouldCache as String: false as NSNumber] as CFDictionary

        guard let source: CGImageSource = CGImageSourceCreateWithURL(url as CFURL, options) else {
            throw CGImageExtensionError.failedToOpenCGImage(url: url)
        }

        let metadata = try ImageMetadata.loadImageMetadataIfNeeded(from: source, having: inputMetadata)
        
        if Image.isRAWImage(at: url) {
            return try CIImage.loadCIImage(from: url, imageMetadata: metadata, options: ImageLoadingOptions(maximumPixelDimensions: constrainedSize)).cgImage()
        } else {
            return try loadCGImage(from: source, metadata: metadata, constrainingToSize: constrainedSize, thumbnailScheme: thumbnailScheme)
        }
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
