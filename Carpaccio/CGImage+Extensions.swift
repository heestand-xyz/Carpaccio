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
}

public extension CGImage {
    func convertedToColorSpace(_ colorSpace: CGColorSpace) throws -> CGImage {
        guard let convertedImage = self.copy(colorSpace: colorSpace) else {
            throw CGImageExtensionError.failedToConvertColorSpace
        }
        return convertedImage
    }
}
