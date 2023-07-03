/*
See LICENSE folder for this sample’s licensing information.

Abstract:
 Misc utilities.
*/

import Foundation
import OSLog

// MARK: - Ranges

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Logging

extension Logger {
    static public let energy = Logger(
        subsystem: "com.example.apple-samplecode.2023-04.widgets",
        category: "energy"
    )
}
