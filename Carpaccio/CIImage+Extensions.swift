//
//  CIImage+Extensions.swift
//  Carpaccio-OSX
//
//  Created by Markus on 27.6.2020.
//  Copyright © 2020 Matias Piipari & Co. All rights reserved.
//

import Foundation
import CoreImage

public extension CIImage {
    static func loadCIImage(from url: URL, imageMetadata: ImageMetadata?, options: ImageLoadingOptions) throws -> CIImage {
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

        // Note: having draft mode on appears to be crucial to performance, with a difference
        // of 0.3s vs. 2.5s per image on a late 2015 iMac 5K, for instance. The quality is still
        // quite excellent for displaying scaled-down presentations in a collection view,
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
        rawFilter.setValue(true, forKey: kCIInputEnableEDRModeKey)

        guard let rawImage = rawFilter.outputImage else {
            throw ImageLoadingError.failedToDecode(URL: url, message: "Failed to decode image at \(url.path)")
        }

        return rawImage
    }

    func cgImage(using outputColorSpace: CGColorSpace? = nil) throws -> CGImage {
        let colorSpace = outputColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let context = ImageBakery.ciContext(for: colorSpace)

        //
        // Pixel format and color space set as discussed around 21:50 in:
        //
        //   https://developer.apple.com/videos/play/wwdc2016/505/
        //
        // The `deferred: false` argument is important, to ensure significant rendering work will not
        // be performed later _at drawing time_ on the main thread.
        //
        guard let cgImage = context.createCGImage(self, from: extent, format: CIFormat.RGBAh, colorSpace: colorSpace, deferred: false) else {
            throw ImageLoadingError.failedToCreateCGImage
        }
        return cgImage
    }

    func bitmapImage(using colorSpace: CGColorSpace? = nil) throws -> BitmapImage {
        let cgImage = try self.cgImage(using: colorSpace)
        return BitmapImageUtility.image(cgImage: cgImage, size: CGSize.zero)
    }

}

fileprivate struct ImageBakery {
    private static var ciContextsByOutputColorSpace = [CGColorSpace: CIContext]()
    private static let ciContextQueue = DispatchQueue(label: "com.sashimiapp.ImageBakeryQueue")

    fileprivate static func ciContext(for colorSpace: CGColorSpace) -> CIContext {
        return ciContextQueue.sync {
            if let context = ciContextsByOutputColorSpace[colorSpace] {
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

            ciContextsByOutputColorSpace[colorSpace] = context
            return context
        }
    }
}

extension CGColorSpace: Hashable {
}
