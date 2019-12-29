//
//  Utility.swift
//  Carpaccio
//
//  Created by Markus Piipari on 30/07/16.
//  Copyright © 2016 Matias Piipari & Co. All rights reserved.
//

import Foundation
import QuartzCore

public extension CGSize {
    var aspectRatio: CGFloat {
        if self.width == 0.0 {
            return 0.0
        }
        if self.height == 0.0 {
            return CGFloat.infinity
        }
        return self.width / self.height
    }

    init(constrainWidth w: CGFloat) {
        self.init(width: w, height: CGFloat.infinity)
    }

    init(constrainHeight h: CGFloat) {
        self.init(width: CGFloat.infinity, height: h)
    }

    /**
     Assuming this CGSize value describes desired maximum width and/or height of a scaled output image,
     return an the value for the `kCGImageSourceThumbnailMaxPixelSize` option so that an image gets scaled
     down proportionally, if appropriate.
     */
    func maximumPixelSize(forImageSize imageSize: CGSize) -> CGFloat {
        let widthIsUnconstrained = self.width >= imageSize.width
        let heightIsUnconstrained = self.height >= imageSize.height
        let ratio = imageSize.aspectRatio

        if widthIsUnconstrained && heightIsUnconstrained {
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

    var maximumPixelSizeConstraint: CGFloat {
        if width >= 1.0 && width != CGFloat.infinity {
            return width
        }
        if height >= 1.0 && height != CGFloat.infinity {
            return height
        }
        return 1.0
    }

    func scaledHeight(forImageSize imageSize: CGSize) -> CGFloat {
        return min(imageSize.height, self.height)
    }

    func proportionalWidth(forHeight height: CGFloat) -> CGFloat {
        return height * self.aspectRatio
    }
    
    func proportionalHeight(forWidth width: CGFloat) -> CGFloat {
        return width / self.aspectRatio
    }
    
    func distance(to: CGSize) -> CGFloat {
        let xDist = to.width - self.width
        let yDist = to.width - self.width
        return sqrt((xDist * xDist) + (yDist * yDist))
    }

    /**

     Determine if either the width, or height, of this size is equal to, or larger than, a given maximum target
     size's width or height.

     The math performed can be scaled by a minimum ratio. For example, if a 50% smaller width or height is enough,
     you should use a `ratio` value of `0.50`. The default is a minimum ratio of `1.0`, meaning at least one of
     this size's dimensions must be greater than or equal to the same dimension of `targetMaxSize`.

     Note that if a dimension of `targetMaxSize` is set to `CGFloat.infinity`, that particular axis will not be
     considered. In such a case, _any_ value of this size, on that axis, is considered insufficient. In other words,
     a `targetMaxSize` of `CGSize(width: CGFloat.infinity, height: CGFloat.infinity)` will always return `false`.

     */
    func isSufficientToFulfill(targetSize: CGSize, atMinimumRatio ratio: CGFloat = 1.0) -> Bool {
        let considerWidth = targetSize.width >= 1.0 && targetSize.width != CGFloat.infinity
        if considerWidth {
            let widthIsSufficient = ((1.0 / ratio) * width) >= targetSize.width
            if widthIsSufficient {
                return true
            }
        }

        let considerHeight = targetSize.height >= 1.0 && targetSize.height != CGFloat.infinity
        if considerHeight {
            let heightIsSufficient = ((1.0 / ratio) * height) >= targetSize.height
            if heightIsSufficient {
                return true
            }
        }

        return false
    }
}

