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
    public var aspectRatio: CGFloat {
        if self.width == 0.0 {
            return 0.0
        }
        if self.height == 0.0 {
            return CGFloat.infinity
        }
        return self.width / self.height
    }
    
    public func proportionalWidth(forHeight height: CGFloat) -> CGFloat {
        return height * self.aspectRatio
    }
    
    public func proportionalHeight(forWidth width: CGFloat) -> CGFloat {
        return width / self.aspectRatio
    }
    
    public func distance(to: CGSize) -> CGFloat {
        let xDist = to.width - self.width
        let yDist = to.width - self.width
        return sqrt((xDist * xDist) + (yDist * yDist))
    }

    /**

     Determine if another size is smaller, in either dimension, by at least a given ratio, which should be
     in the range 0.0 < ratio <= 1.0. The default ratio is 0.0, which means comparing dimensions 1:1.

     If any dimension of either size is set to CGFloat.infinity, that axis will not be considered.

     Examples:

     ...

     */
    // TODO: Add examples for sizeIsSmaller() !!!
    public func sizeIsSmaller(_ otherSize: CGSize, byAtLeastRatio ratio: CGFloat = 1.0) -> Bool {
        guard ratio >= 0.0 && ratio < 1.0 else {
            return false
        }

        if width < CGFloat.infinity && otherSize.width < CGFloat.infinity && width * (1.0 - ratio) > otherSize.width {
            print("Width of \(otherSize) is smaller than \(self) by at least \(Int(ratio * 100.0))%")
            return true
        }

        if height < CGFloat.infinity && otherSize.height < CGFloat.infinity && height * (1.0 - ratio) > otherSize.height {
            print("Height of \(otherSize) is smaller than \(self) by at least \(Int(ratio * 100.0))%")
            return true
        }

        return false
    }
}

