//
//  ImageLoader.swift
//  Carpaccio
//
//  Created by Markus Piipari on 31/07/16.
//  Copyright © 2016 Matias Piipari & Co. All rights reserved.
//

import Foundation

import CoreGraphics
import CoreImage
import ImageIO

/**
 Implementation of ImageLoaderProtocol, capable of dealing with RAW file formats,
 as well common compressed image file formats.
 */
public class ImageLoader: ImageLoaderProtocol, URLBackedImageLoaderProtocol {
    enum Error: Swift.Error, LocalizedError {
        case filterInitializationFailed(URL: URL)

        var errorDescription: String? {
            switch self {
            case .filterInitializationFailed(let URL):
                return "Failed to initialize image loader filter for image at URL \(URL)"
            }
        }

        var failureReason: String? {
            switch self {
            case .filterInitializationFailed(let URL):
                return "Failed to initialize image loader filter for file at \"\(URL)\""
            }
        }

        var helpAnchor: String? {
            return "Ensure that images of the kind you are trying to load are supported by your system."
        }

        var recoverySuggestion: String? {
            return self.helpAnchor
        }
    }

    public enum ThumbnailScheme: Int {
        case never
        case alwaysDecodeFullImage
        case fullImageIfThumbnailTooSmall
        case fullImageIfThumbnailMissing

        /**
         With this thumbnail scheme in effect, determine if it's any use to load a thumbnail embedded
         in an image file at all.
         */
        public var shouldLoadThumbnail: Bool {
            switch self {
            case .alwaysDecodeFullImage, .never:
                return false
            case .fullImageIfThumbnailMissing, .fullImageIfThumbnailTooSmall:
                return true
            }
        }

        /**

         With this thumbnail scheme in effect, determine if the full size image should be loaded, given:

         - An already loaded thumbnail image candidate (if any)

         - A target maximum size (if any)

         - A threshold for how much smaller the thumbnail image can be in each dimension, and still qualify.

           Default ratio is 1.0, meaning either the thumbnail image candidate's width or height must be equal
           to, or greater than, the width or height of the given target maximum size. If, say, a 20% smaller
           thumbnail image (in either width or height) is fine to scale up for display, you would provide a
           `ratio` value of `0.80`.

         */
        public func shouldLoadFullSizeImage(having thumbnailCGImage: CGImage?, desiredMaximumPixelDimensions targetMaxSize: CGSize?, ratio: CGFloat = 1.0) -> Bool {
            switch self {
            case .alwaysDecodeFullImage:
                return true
            case .fullImageIfThumbnailMissing:
                return thumbnailCGImage == nil
            case .fullImageIfThumbnailTooSmall:
                guard let cgImage = thumbnailCGImage else {
                    // No candidate thumbnail has been loaded yet, so must load full image
                    return true
                }
                guard let targetMaxSize = targetMaxSize else {
                    // There is no size requirement, so no point in loading full image
                    return false
                }
                let candidateSize = CGSize(width: cgImage.width, height: cgImage.height)
                let should = !candidateSize.isSufficientToFulfill(targetSize: targetMaxSize, atMinimumRatio: ratio)
                return should
            case .never:
                return false
            }
        }
    }
    
    public let imageURL: URL
    public let colorSpace: CGColorSpace?
    
    public let cachedImageURL: URL? = nil // For now, we don't implement a disk cache for images loaded by ImageLoader
    public let thumbnailScheme: ThumbnailScheme
    
    public required init(imageURL: URL, thumbnailScheme: ThumbnailScheme, colorSpace: CGColorSpace?) {
        self.imageURL = imageURL
        self.thumbnailScheme = thumbnailScheme
        self.colorSpace = colorSpace
    }
    
    public required init(imageLoader otherLoader: ImageLoaderProtocol, thumbnailScheme: ThumbnailScheme, colorSpace: CGColorSpace?) {
        self.imageURL = otherLoader.imageURL
        self.thumbnailScheme = thumbnailScheme
        self.colorSpace = colorSpace
        if otherLoader.imageMetadataState == .completed, let metadata = try? otherLoader.loadImageMetadata() {
            self.cachedImageMetadata = metadata
            self.imageMetadataState = .completed
        }
    }
    
    private func imageSource() throws -> CGImageSource {
        // We intentionally don't store the image source, to not gob up resources, but rather open it anew each time
        let options = [String(kCGImageSourceShouldCache): false,
                       String(kCGImageSourceShouldAllowFloat): true] as NSDictionary as CFDictionary
        
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, options) else{
            throw CGImageExtensionError.failedToOpenCGImage(url: imageURL)
        }
        
        return imageSource
    }
    
    public private(set) var imageMetadataState: ImageLoaderMetadataState = .initialized
    internal fileprivate(set) var cachedImageMetadata: ImageMetadata?

    private func dumpAllImageMetadata(_ imageSource: CGImageSource)
    {
        let metadata = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil)
        let options: [String: AnyObject] = [String(kCGImageMetadataEnumerateRecursively): true as CFNumber]
        var results = [String: AnyObject]()

        CGImageMetadataEnumerateTagsUsingBlock(metadata!, nil, options as CFDictionary?) { path, tag in
            
            if let value = CGImageMetadataTagCopyValue(tag) {
                results[path as String] = value
            }
            else {
                results[path as String] = "??" as NSString
            }
            return true
        }
        
        print("---- All metadata for \(self.imageURL.path): ----")
        
        for key in results.keys.sorted() {
            print("    \(key) = \(results[key]!)")
        }
        
        print("----")
    }
    
    public func loadImageMetadata() throws -> ImageMetadata {
        let metadata = try loadImageMetadataIfNeeded()
        return metadata
    }
    
    var count = 0
    
    internal func loadImageMetadataIfNeeded(forceReload: Bool = false) throws -> ImageMetadata {
        count += 1
        
        if forceReload {
            imageMetadataState = .initialized
            cachedImageMetadata = nil
        }
        
        if imageMetadataState == .initialized {
            do {
                imageMetadataState = .loadingMetadata
                let imageSource = try self.imageSource()
                let metadata = try ImageMetadata(imageSource: imageSource)
                cachedImageMetadata = metadata
                imageMetadataState = .completed
            } catch {
                imageMetadataState = .failed
                throw error
            }
        }
        
        guard let metadata = cachedImageMetadata, imageMetadataState == .completed else {
            throw Image.Error.noMetadata
        }
        
        return metadata
    }

    public func loadThumbnailCGImage(maximumPixelDimensions maximumSize: CGSize? = nil,
                                     allowCropping: Bool = true,
                                     cancelled cancelChecker: CancellationChecker?) throws -> (CGImage, ImageMetadata)
    {
        let metadata = try loadImageMetadataIfNeeded()
        let source = try imageSource()
        
        guard self.thumbnailScheme != .never else {
            throw ImageLoadingError.loadingSetToNever(URL: self.imageURL, message: "Image thumbnail failed to be loaded as the loader responsible for it is set to never load thumbnails.")
        }

        // Load thumbnail
        try stopIfCancelled(cancelChecker, "Before loading thumbnail image")

        let createFromFullImage = thumbnailScheme == .alwaysDecodeFullImage

        var options: [String: AnyObject] = {
            var options: [String: AnyObject] = [String(kCGImageSourceCreateThumbnailWithTransform): kCFBooleanTrue]

            if createFromFullImage {
                options[String(kCGImageSourceCreateThumbnailFromImageAlways)] = kCFBooleanTrue
            } else {
                options[String(kCGImageSourceCreateThumbnailFromImageIfAbsent)] = kCFBooleanTrue
            }

            if let maximumPixelDimension = maximumSize?.maximumPixelSize(forImageSize: metadata.size) {
                options[String(kCGImageSourceThumbnailMaxPixelSize)] = NSNumber(value: maximumPixelDimension)
            }

            return options
        }()
        
        let thumbnailImage: CGImage = try {
            let thumbnailCandidate = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary?)

            // Retry from full image, if needed, and wasn't already
            guard let thumbnail: CGImage = {
                if !createFromFullImage && thumbnailScheme.shouldLoadFullSizeImage(having: thumbnailCandidate, desiredMaximumPixelDimensions: maximumSize, ratio: 1.0) {
                    options[kCGImageSourceCreateThumbnailFromImageAlways as String] = kCFBooleanTrue
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary?)
                }
                return thumbnailCandidate
            }() else {
                throw ImageLoadingError.noImageSource(URL: self.imageURL, message: "Failed to load thumbnail")
            }

            // Convert color space, if needed
            guard let colorSpace = self.colorSpace else {
                return thumbnail
            }

            try stopIfCancelled(cancelChecker, "Before converting color space of thumbnail image")

            let image = try thumbnail.convertedToColorSpace(colorSpace)
            return image
        }()

        // Crop letterboxing out, if needed
        guard allowCropping else {
            return (thumbnailImage, metadata)
        }

        try stopIfCancelled(cancelChecker, "Before cropping to native proportions")

        return (ImageLoader.cropToNativeProportionsIfNeeded(thumbnailImage: thumbnailImage, metadata: metadata), metadata)
    }
    
    /**
     
     If the proportions of thumbnail image don't match those of the native full size, crop to the same proportions.
     
     This, for example, can happen with Nikon RAW files, where the smallest thumbnail included in a NEF file can be 4:3,
     while the actual full-size image is 3:2. In that case, the thumbnail will contain black bars around the actual image,
     to extend 3:2 to 4:3 proportions. The solution: crop.
     
     */
    public class func cropToNativeProportionsIfNeeded(thumbnailImage thumbnail: CGImage, metadata: ImageMetadata) -> CGImage
    {
        let thumbnailSize = CGSize(width: CGFloat(thumbnail.width), height:CGFloat(thumbnail.height))
        let absThumbAspectDiff = abs(metadata.size.aspectRatio - thumbnailSize.aspectRatio)
        
        // small differences can happen and in those cases we should not crop but simply rescale the thumbnail
        // (to avoid decreasing image quality).
        let metadataAndThumbAgreeOnAspectRatio = absThumbAspectDiff < 0.01
        
        if metadataAndThumbAgreeOnAspectRatio {
            return thumbnail
        }
        
        let cropRect: CGRect?
        
        switch metadata.shape
        {
        case .landscape:
            let expectedHeight = metadata.size.proportionalHeight(forWidth: CGFloat(thumbnail.width))
            let d = Int(round(abs(expectedHeight - CGFloat(thumbnail.height))))
            if (d >= 1)
            {
                let cropAmount: CGFloat = 0.5 * (d % 2 == 0 ? CGFloat(d) : CGFloat(d + 1))
                cropRect = CGRect(x: 0.0, y: cropAmount, width: CGFloat(thumbnail.width), height: CGFloat(thumbnail.height) - 2.0 * cropAmount)
            }
            else
            {
                cropRect = nil
            }
        case .portrait:
            let expectedWidth = metadata.size.proportionalWidth(forHeight: CGFloat(thumbnail.height))
            let d = Int(round(abs(expectedWidth - CGFloat(thumbnail.width))))
            if (d >= 1)
            {
                let cropAmount: CGFloat = 0.5 * (d % 2 == 0 ? CGFloat(d) : CGFloat(d + 1))
                cropRect = CGRect(x: cropAmount, y: 0.0, width: CGFloat(thumbnail.width) - 2.0 * cropAmount, height: CGFloat(thumbnail.height))
            }
            else
            {
                cropRect = nil
            }
        case .square:
            // highly unlikely to actually occur – 
            // as I'm not sure what the correct procedure here would be,
            // I will do nothing.
            cropRect = nil
        }
        
        if let r = cropRect, let croppedThumbnail = thumbnail.cropping(to: r) {
            return croppedThumbnail
        }
        
        return thumbnail
    }
    
    /** Retrieve a thumbnail image for this loader's image. */
    public func loadThumbnailImage(maximumPixelDimensions maxPixelSize: CGSize?, allowCropping: Bool, cancelled: CancellationChecker?) throws -> (BitmapImage, ImageMetadata) {
        let (thumbnailImage, metadata) = try loadThumbnailCGImage(maximumPixelDimensions: maxPixelSize, allowCropping: allowCropping, cancelled: cancelled)
        return (BitmapImageUtility.image(cgImage: thumbnailImage, size: CGSize.zero), metadata)
    }
    
    struct BakingContextKey: Hashable {
        let pathExtension: String
        let colorSpace: CGColorSpace
    }
    
    private static var imageBakingContextsByColorSpace = [CGColorSpace: CIContext]()
    
    fileprivate static func imageBakingContext(for colorSpace: CGColorSpace) -> CIContext {
        if let context = imageBakingContextsByColorSpace[colorSpace] {
            return context
        }
        
        let context = CIContext(options: [
            CIContextOption.cacheIntermediates: false,
            CIContextOption.priorityRequestLow: false,
            CIContextOption.useSoftwareRenderer: false,
            CIContextOption.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            CIContextOption.workingFormat: CIFormat.RGBAh,
            CIContextOption.outputColorSpace: colorSpace
        ])

        imageBakingContextsByColorSpace[colorSpace] = context
        return context
    }
    
    public func loadFullSizeImage(options: ImageLoadingOptions) throws -> (BitmapImage, ImageMetadata) {
        let metadata = try loadImageMetadataIfNeeded()
        let ciImage = try ImageLoader.loadCIImage(at: imageURL, imageMetadata: metadata, options: options)

        guard let bitmapImage = ciImage.bitmapImage(using: colorSpace) else {
            throw ImageLoadingError.failedToLoadDecodedImage(URL: imageURL, message: "Failed to make adjustable CIImage into a bitmap image")
        }

        return (bitmapImage, metadata)
    }

    public func loadEditableImage(options: ImageLoadingOptions, cancelled: CancellationChecker?) throws -> (CIImage, ImageMetadata) {
        let metadata = try loadImageMetadataIfNeeded()
        try stopIfCancelled(cancelled, "Before loading editable image")
        let ciImage = try ImageLoader.loadCIImage(at: imageURL, imageMetadata: metadata, options: options)
        return (ciImage, metadata)
    }

    public static func loadCIImage(at url: URL, imageMetadata: ImageMetadata?, options: ImageLoadingOptions) throws -> CIImage {
        guard let rawFilter = CIFilter(imageURL: url, options: nil) else {
            throw ImageLoadingError.failedToInitializeDecoder(URL: url, message: "Failed to load full-size RAW image at \(url.path)")
        }

        let scale: Double = {
            guard let targetSize = options.maximumPixelDimensions, let metadata = imageMetadata else {
                return 1.0
            }
            let height = targetSize.scaledHeight(forImageSize: metadata.size)
            return Double(height / metadata.size.height)
        }()

        // NOTE: Having draft mode on appears to be crucial to performance,
        // with a difference of 0.3s vs. 2.5s per image on this iMac 5K, for instance.
        // The quality is still quite excellent for displaying scaled-down presentations in a collection view,
        // subjectively better than what you get from LibRAW with the half-size option.
        rawFilter.setValue(true, forKey: CIRAWFilterOption.allowDraftMode.rawValue)
        rawFilter.setValue(scale, forKey: CIRAWFilterOption.scaleFactor.rawValue)

        if let value = options.baselineExposure {
            rawFilter.setValue(value, forKey: CIRAWFilterOption.baselineExposure.rawValue)
        }

        rawFilter.setValue(options.noiseReductionAmount, forKey: CIRAWFilterOption.noiseReductionAmount.rawValue)
        rawFilter.setValue(options.colorNoiseReductionAmount, forKey: CIRAWFilterOption.colorNoiseReductionAmount.rawValue)
        rawFilter.setValue(options.noiseReductionSharpnessAmount, forKey: CIRAWFilterOption.noiseReductionSharpnessAmount.rawValue)
        rawFilter.setValue(options.noiseReductionContrastAmount, forKey: CIRAWFilterOption.noiseReductionContrastAmount.rawValue)
        rawFilter.setValue(options.boostShadowAmount, forKey: CIRAWFilterOption.boostShadowAmount.rawValue)
        rawFilter.setValue(options.enableVendorLensCorrection, forKey: CIRAWFilterOption.enableVendorLensCorrection.rawValue)

        guard let rawImage = rawFilter.outputImage else {
            throw ImageLoadingError.failedToDecode(URL: url, message: "Failed to decode image at \(url.path)")
        }

        return rawImage
    }
}

extension CGColorSpace: Hashable {
}

public extension CIImage {
    func bitmapImage(using requestedColorSpace: CGColorSpace? = nil) -> BitmapImage? {
        let colorSpace = requestedColorSpace ?? CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let context = ImageLoader.imageBakingContext(for: colorSpace)

        //
        // Pixel format and color space set as discussed around 21:50 in:
        //
        //   https://developer.apple.com/videos/play/wwdc2016/505/
        //
        // The `deferred: false` argument is important, to ensure significant rendering work will not
        // be performed later _at drawing time_ on the main thread.
        //
        if let cgImage = context.createCGImage(self, from: extent, format: CIFormat.RGBAh, colorSpace: colorSpace, deferred: false) {
            return BitmapImageUtility.image(cgImage: cgImage, size: CGSize.zero)
        }
        return BitmapImageUtility.image(ciImage: self)
    }
}
