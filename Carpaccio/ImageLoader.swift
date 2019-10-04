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
public class ImageLoader: ImageLoaderProtocol, URLBackedImageLoaderProtocol
{
    enum Error: Swift.Error, LocalizedError {
        case filterInitializationFailed(URL: URL)
        case failedToOpenImage(message: String)

        var errorDescription: String? {
            switch self {
            case .filterInitializationFailed(let URL):
                return "Failed to initialize image loader filter for image at URL \(URL)"
            case .failedToOpenImage(let msg):
                return "Failed to open image: \(msg)"
            }
        }

        var failureReason: String? {
            switch self {
            case .filterInitializationFailed(let URL):
                return "Failed to initialize image loader filter for file at \"\(URL)\""
            case .failedToOpenImage(let msg):
                return msg
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
        case decodeFullImage
        case fullImageWhenTooSmallThumbnail
        case fullImageWhenThumbnailMissing
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
            throw Error.failedToOpenImage(message: "Failed to open image at \(imageURL)")
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
    
    func bailIfCancelled(_ checker: CancellationChecker?, _ message: String) throws {
        if let checker = checker, checker() {
            throw ImageLoadingError.cancelled(url: self.imageURL, message: message)
        }
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
        
        try bailIfCancelled(cancelChecker, "Before loading thumbnail image")
        let size = metadata.size
        let maxPixelSize = maximumSize?.maximumPixelSize(forImageSize: size)
        let createFromFullImage = self.thumbnailScheme == .decodeFullImage
        
        var options: [String: AnyObject] = [String(kCGImageSourceCreateThumbnailWithTransform): kCFBooleanTrue,
                                            String(createFromFullImage ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent): kCFBooleanTrue]
        
        if let sz = maxPixelSize {
            options[String(kCGImageSourceThumbnailMaxPixelSize)] = NSNumber(value: Int(round(sz)))
        }
        
        let thumbnailImage: CGImage = try {
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary?) else {
                throw ImageLoadingError.noImageSource(URL: self.imageURL, message: "Failed to load thumbnail image: creating image source failed")
            }
            
            if let colorSpace = self.colorSpace {
                try bailIfCancelled(cancelChecker, "Before converting thumbnail image color space")
                
                guard let image = thumbnail.copy(colorSpace: colorSpace) else {
                    throw ImageLoadingError.failedToConvertColorSpace(url: self.imageURL, message: "Failed to convert color space of image to \(colorSpace.name as String? ?? "untitled color space")")
                }
                return image
            } else {
                return thumbnail
            }
        }()
        
        if !allowCropping {
            return (thumbnailImage, metadata)
        } else {
            try bailIfCancelled(cancelChecker, "Before cropping to native proportions")
            return (ImageLoader.cropToNativeProportionsIfNeeded(thumbnailImage: thumbnailImage, metadata: metadata), metadata)
        }
    }
    
    /**
     
     If the proportions of thumbnail image don't match those of the native full size, crop to the same proportions.
     
     This, for example, can happen with Nikon RAW files, where the smallest thumbnail included in a NEF file can be 4:3,
     while the actual full-size image is 3:2. In that case, the thumbnail will contain black bars around the actual image,
     to extend 3:2 to 4:3 proportions. The solution: crop.
     
     */
    private class func cropToNativeProportionsIfNeeded(thumbnailImage thumbnail: CGImage, metadata: ImageMetadata) -> CGImage
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
    
    private static var _imageBakingContexts = [BakingContextKey: CIContext]()
    
    private static func bakingContextForImageAt(_ imageURL: URL, usingColorSpace colorSpace: CGColorSpace) -> CIContext {
        let key = BakingContextKey(pathExtension: imageURL.pathExtension, colorSpace: colorSpace)
        
        if let context = _imageBakingContexts[key] {
            return context
        }
        
        let context = CIContext(options: convertToOptionalCIContextOptionDictionary([
            convertFromCIContextOption(CIContextOption.cacheIntermediates): false,
            convertFromCIContextOption(CIContextOption.useSoftwareRenderer): false,
            convertFromCIContextOption(CIContextOption.outputColorSpace): colorSpace
            ]))
        _imageBakingContexts[key] = context
        
        return context
    }
    
    public func loadFullSizeImage(options: FullSizedImageLoadingOptions) throws -> (BitmapImage, ImageMetadata)
    {
        let metadata = try loadImageMetadataIfNeeded()
        let scaleFactor: Double
        
        if let sz = options.maximumPixelDimensions {
            let imageSize = metadata.size
            let height = sz.scaledHeight(forImageSize: imageSize)
            scaleFactor = Double(height / imageSize.height)
        }
        else {
            scaleFactor = 1.0
        }
        
        guard let RAWFilter = CIFilter(imageURL: self.imageURL, options: nil) else {
            throw ImageLoadingError.failedToInitializeDecoder(URL: self.imageURL,
                                                              message: "Failed to load full-size RAW image \(self.imageURL.path)")
        }
        
        // NOTE: Having draft mode on appears to be crucial to performance, 
        // with a difference of 0.3s vs. 2.5s per image on this iMac 5K, for instance.
        // The quality is still quite excellent for displaying scaled-down presentations in a collection view, 
        // subjectively better than what you get from LibRAW with the half-size option.
        RAWFilter.setValue(true, forKey: convertFromCIRAWFilterOption(CIRAWFilterOption.allowDraftMode))
        RAWFilter.setValue(scaleFactor, forKey: convertFromCIRAWFilterOption(CIRAWFilterOption.scaleFactor))
        
        RAWFilter.setValue(options.noiseReductionAmount, forKey: convertFromCIRAWFilterOption(CIRAWFilterOption.noiseReductionAmount))
        RAWFilter.setValue(options.colorNoiseReductionAmount, forKey: convertFromCIRAWFilterOption(CIRAWFilterOption.colorNoiseReductionAmount))
        RAWFilter.setValue(options.noiseReductionSharpnessAmount, forKey: convertFromCIRAWFilterOption(CIRAWFilterOption.noiseReductionSharpnessAmount))
        RAWFilter.setValue(options.noiseReductionContrastAmount, forKey: convertFromCIRAWFilterOption(CIRAWFilterOption.noiseReductionContrastAmount))
        RAWFilter.setValue(options.boostShadowAmount, forKey: convertFromCIRAWFilterOption(CIRAWFilterOption.boostShadowAmount))
        RAWFilter.setValue(options.enableVendorLensCorrection, forKey: convertFromCIRAWFilterOption(CIRAWFilterOption.enableVendorLensCorrection))
        
        guard let image = RAWFilter.outputImage else {
            throw ImageLoadingError.failedToDecode(URL: self.imageURL,
                                                   message: "Failed to decode full-size RAW image \(self.imageURL.path)")
        }
        var bakedImage: BitmapImage? = nil
        // Pixel format and color space set as discussed around 21:50 in https://developer.apple.com/videos/play/wwdc2016/505/
        let colorSpace = self.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let context = ImageLoader.bakingContextForImageAt(self.imageURL, usingColorSpace: colorSpace)
        if let cgImage = context.createCGImage(image,
                                               from: image.extent,
                                               format: CIFormat.RGBA8,
                                               colorSpace: colorSpace,
                                               deferred: false) // The `deferred: false` argument is important, to ensure significant work will not be performed later on the main thread at drawing time
        {
            bakedImage = BitmapImageUtility.image(cgImage: cgImage, size: CGSize.zero)
        }
        
        if bakedImage == nil {
            bakedImage = BitmapImageUtility.image(ciImage: image)
        }
        
        guard let nonNilNakedImage = bakedImage else {
            throw ImageLoadingError.failedToLoadDecodedImage(URL: self.imageURL,
                                                             message: "Failed to load decoded image \(self.imageURL.path)")
        }

        return (nonNilNakedImage, metadata)
    }
}

public extension CGSize
{
    init(constrainWidth w: CGFloat) {
        self.init(width: w, height: CGFloat.infinity)
    }
    
    init(constrainHeight h: CGFloat) {
        self.init(width: CGFloat.infinity, height: h)
    }
    
    /** Assuming this NSSize value describes desired maximum width and/or height of a scaled output image, return appropriate value for the `kCGImageSourceThumbnailMaxPixelSize` option. */
    func maximumPixelSize(forImageSize imageSize: CGSize) -> CGFloat
    {
        let widthIsUnconstrained = self.width > imageSize.width
        let heightIsUnconstrained = self.height > imageSize.height
        let ratio = imageSize.aspectRatio
        
        if widthIsUnconstrained && heightIsUnconstrained
        {
            if ratio > 1.0 {
                return imageSize.width
            }
            return imageSize.height
        }
        else if widthIsUnconstrained {
            if ratio > 1.0 {
                return imageSize.proportionalWidth(forHeight: self.height)
            }
            return self.height
        }
        else if heightIsUnconstrained {
            if ratio > 1.0 {
                return self.width
            }
            return imageSize.proportionalHeight(forWidth: self.width)
        }
        
        return min(self.width, self.height)
    }
    
    func scaledHeight(forImageSize imageSize: CGSize) -> CGFloat
    {
        return min(imageSize.height, self.height)
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToOptionalCIContextOptionDictionary(_ input: [String: Any]?) -> [CIContextOption: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (CIContextOption(rawValue: key), value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromCIContextOption(_ input: CIContextOption) -> String {
	return input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromCIRAWFilterOption(_ input: CIRAWFilterOption) -> String {
	return input.rawValue
}

extension CGColorSpace: Hashable {
    
}
