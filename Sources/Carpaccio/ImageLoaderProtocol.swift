//
//  ImageLoading.swift
//  Carpaccio
//
//  Created by Markus Piipari on 27/07/16.
//  Copyright © 2016 Matias Piipari & Co. All rights reserved.
//

import Foundation
import QuartzCore
import CoreImage

public typealias ImageMetadataHandler = (_ metadata: ImageMetadata) -> Void

public typealias PresentableImageHandler = (_ image: BitmapImage, _ metadata: ImageMetadata) -> Void

public enum ImageLoadingError: Swift.Error, LocalizedError
{
    case failedToExtractImageMetadata(URL: URL, message: String)
    case failedToLoadThumbnailImage(URL: URL, message: String)
    case failedToLoadFullSizeImage(URL: URL, message: String)
    case noImageSource(URL: URL, message: String)
    case failedToInitializeDecoder(URL: URL, message: String)
    case failedToDecode(URL: URL, message: String)
    case failedToLoadDecodedImage(URL: URL, message: String)
    case loadingSetToNever(URL: URL, message: String)
    case expectingMetadata(URL: URL, message: String)
    case failedToConvertColorSpace(url: URL, message: String)
    case cancelled(url: URL, message: String)

    public var errorCode: Int {
        switch self {
        case .failedToExtractImageMetadata: return 1
        case .failedToLoadThumbnailImage: return 2
        case .failedToLoadFullSizeImage: return 3
        case .noImageSource: return 4
        case .failedToInitializeDecoder: return 5
        case .failedToDecode: return 6
        case .failedToLoadDecodedImage: return 7
        case .loadingSetToNever: return 8
        case .expectingMetadata: return 9
        case .failedToConvertColorSpace: return 10
        case .cancelled: return 11
        }
    }

    public var errorDescription: String? {
        switch self {
        case .failedToExtractImageMetadata(let url, let msg):
            return "Failed to extract image metadata for file at URL \(url): \(msg)"
        case .failedToLoadThumbnailImage(let url, let msg):
            return "Failed to load image thumbnail at URL \(url): \(msg)"
        case .failedToLoadFullSizeImage(let url, let msg):
            return "Failed to load full sized image from file at URL \(url): \(msg)"
        case .noImageSource(let url, let msg):
            return "No sources of image data present in file at URL \(url): \(msg)"
        case .failedToInitializeDecoder(let url, let msg):
            return "Failed to initialize decoder for image file at URL \(url): \(msg)"
        case .failedToDecode(let url, let msg):
            return "Failed to decode image from file at URL \(url): \(msg)"
        case .failedToLoadDecodedImage(let url, let msg):
            return "Failed to load decoded image from image file at URL \(url): \(msg)"
        case .loadingSetToNever(let url, let msg):
            return "Image at \(url) set to be never to be loaded: \(msg)"
        case .expectingMetadata(let url, let msg):
            return "Failing to receive expected metadata for file at URL \(url): \(msg)"
        case .failedToConvertColorSpace(let url, let msg):
            return "Failed to convert image color space for file at URL \(url): \(msg)"
        case .cancelled(let url, let msg):
            return "Operation for image at URL \(url) was cancelled: \(msg)"
        }
    }

    public var failureReason: String? {
        switch self {
        case .failedToExtractImageMetadata(_, let msg):
            return msg
        case .failedToLoadThumbnailImage(_, let msg):
            return msg
        case .failedToLoadFullSizeImage(_, let msg):
            return msg
        case .noImageSource(_, let msg):
            return msg
        case .failedToInitializeDecoder(_, let msg):
            return msg
        case .failedToDecode(_, let msg):
            return msg
        case .failedToLoadDecodedImage(_, let msg):
            return msg
        case .loadingSetToNever(_, let msg):
            return msg
        case .expectingMetadata(_, let msg):
            return msg
        case .failedToConvertColorSpace(_, let msg):
            return msg
        case .cancelled(_, let msg):
            return msg
        }
    }

    public var recoverySuggestion: String? {
        return "Please check that the file in question exists, is a valid image and that you have permissions to access it."
    }

    public var helpAnchor: String? {
        return "Please check that the file in question exists, is a valid image that you have permissions to access it. For example, check that it opens in another image reading application."
    }
}

public typealias ImageLoadingErrorHandler = (_ error: ImageLoadingError) -> Void

public struct ImageLoadingOptions {
    public let maximumPixelDimensions: CGSize?

    public let allowDraftMode: Bool
    public let baselineExposure: Double?
    public let noiseReductionAmount: Double
    public let colorNoiseReductionAmount: Double
    public let noiseReductionSharpnessAmount: Double
    public let noiseReductionContrastAmount: Double
    public let boostShadowAmount: Double
    public let enableVendorLensCorrection: Bool

    public init(
        maximumPixelDimensions: CGSize? = nil,
        allowDraftMode: Bool = true,
        baselineExposure: Double? = nil,
        noiseReductionAmount: Double = 0.5,
        colorNoiseReductionAmount: Double = 1.0,
        noiseReductionSharpnessAmount: Double = 0.5,
        noiseReductionContrastAmount: Double = 0.5,
        boostShadowAmount: Double = 2.0,
        enableVendorLensCorrection: Bool = true
    ) {
        self.maximumPixelDimensions = maximumPixelDimensions
        self.allowDraftMode = allowDraftMode
        self.baselineExposure = baselineExposure
        self.noiseReductionAmount = noiseReductionAmount
        self.colorNoiseReductionAmount = colorNoiseReductionAmount
        self.noiseReductionSharpnessAmount = noiseReductionSharpnessAmount
        self.noiseReductionContrastAmount = noiseReductionContrastAmount
        self.boostShadowAmount = boostShadowAmount
        self.enableVendorLensCorrection = enableVendorLensCorrection
    }
}

/**
 
 This enumeration indicates the current stage of loading an image's metadata. The values
 can be used by a client to determine whether a particular image should be completely
 omitted, or if an error indication should be communicated to the user.
 
 */
public enum ImageLoaderMetadataState {
    /** Metadata has not yet been loaded. */
    case initialized
    
    /** Metadata is currently being loaded. */
    case loadingMetadata
    
    /** Loading image metadata has succesfully completed. */
    case completed
    
    /** Loading image metadata failed with an error. */
    case failed
}

/**
 Closure type for determining if a potentially lengthy thumbnail image loading step should
 not be performed after all, due to the image not being needed anymore.
 */
public typealias CancellationChecker = () -> Bool

public protocol ImageLoaderProtocol {
    var imageURL: URL { get }
    var imageMetadataState: ImageLoaderMetadataState { get }
    var colorSpace: CGColorSpace? { get }
    
    /** _If_, in addition to `imageURL`, full image image data happens to have been copied into a disk cache location,
      * a direct URL pointing to that location. */
    var cachedImageURL: URL? { get }
    
    /**
     Load image metadata synchronously. After a first succesful load, an implementation may choose to return a cached
     copy on later calls.
     */
    func loadImageMetadata() throws -> ImageMetadata
    
    /**
     Load a thumbnail representation of this loader's associated image, optionally:
     - Scaled down to a maximum pixel size
     - Cropped to the proportions of the image's metadata (to remove letterboxing by some cameras' thumbnails)
     */
    func loadThumbnailImage(maximumPixelDimensions maxPixelSize: CGSize?, allowCropping: Bool, cancelled: CancellationChecker?) throws -> (BitmapImage, ImageMetadata)
    
    func loadThumbnailCGImage(maximumPixelDimensions maximumSize: CGSize?, allowCropping: Bool, cancelled: CancellationChecker?) throws -> (CGImage, ImageMetadata)
    
    func loadThumbnailImage(cancelled: CancellationChecker?) throws -> (BitmapImage, ImageMetadata)
    
    /** Load full-size image. */
    func loadFullSizeImage(options: ImageLoadingOptions) throws -> (BitmapImage, ImageMetadata)
    
    /** Load full-size image with default options. */
    func loadFullSizeImage() throws -> (BitmapImage, ImageMetadata)

    func loadEditableImage(options: ImageLoadingOptions, cancelled: CancellationChecker?) throws -> (CIImage, ImageMetadata)
}

public protocol URLBackedImageLoaderProtocol: ImageLoaderProtocol {
    init(imageURL: URL, thumbnailScheme: ImageLoader.ThumbnailScheme, colorSpace: CGColorSpace?)
    init(imageLoader: ImageLoaderProtocol, thumbnailScheme: ImageLoader.ThumbnailScheme, colorSpace: CGColorSpace?)
}

public extension ImageLoaderProtocol {
    func loadThumbnailImage(cancelled: CancellationChecker?) throws -> (BitmapImage, ImageMetadata) {
        return try self.loadThumbnailImage(maximumPixelDimensions: nil, allowCropping: true, cancelled: cancelled)
    }
    
    func loadThumbnailImage(maximumPixelDimensions: CGSize?, cancelled: CancellationChecker?) throws -> (BitmapImage, ImageMetadata) {
        return try self.loadThumbnailImage(maximumPixelDimensions: maximumPixelDimensions, allowCropping: true, cancelled: cancelled)
    }
    
    func loadThumbnailImage(allowCropping: Bool, cancelled: CancellationChecker?) throws -> (BitmapImage, ImageMetadata) {
        return try self.loadThumbnailImage(maximumPixelDimensions: nil, allowCropping: allowCropping, cancelled: cancelled)
    }
    
    func loadFullSizeImage() throws -> (BitmapImage, ImageMetadata) {
        return try self.loadFullSizeImage(options: ImageLoadingOptions())
    }

    /**
     Convenience func to be called by image loader implementations themselves, to check if a particular
     thumbnail or full size image loading operation has been cancelled.
     @throws An `ImageLoadingError.cancelled` error if cancellation checker returns `true`.
     */
    func stopIfCancelled(_ checker: CancellationChecker?, _ message: String) throws {
        if let checker = checker, checker() {
            throw ImageLoadingError.cancelled(url: self.imageURL, message: message)
        }
    }
}
