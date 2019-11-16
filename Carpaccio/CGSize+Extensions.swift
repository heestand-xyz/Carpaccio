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
     considered. In such a case, _any_ value of this size, on that axis, is considered sufficient.

     */
    func isSufficientInAnyDimension(comparedTo targetMaxSize: CGSize, atMinimumRatio ratio: CGFloat = 1.0) -> Bool {
        let widthIsSufficient = targetMaxSize.width == CGFloat.infinity || ((1.0 / ratio) * width) >= targetMaxSize.width
        if widthIsSufficient {
            return true
        }

        let heightIsSufficient = targetMaxSize.height == CGFloat.infinity || ((1.0 / ratio) * height) >= targetMaxSize.height
        if heightIsSufficient {
            return true
        }

        return false
    }
}

