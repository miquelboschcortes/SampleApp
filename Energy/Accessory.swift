/*
See LICENSE folder for this sample’s licensing information.

Abstract:
 A Section to show recent trips in a horizontal scrolling list
*/

import Foundation
import CoreData

enum AccessoryError {
    case missingManagedObjectContext
}

extension AccessoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingManagedObjectContext:
            return """
                In order to switch power on/off for an Accessory, \
                it must have its managedObjectContext set.
                """
        }
    }
}

extension Accessory {
    public func switchPower(on poweredOn: Bool, delay: TimeInterval = 0, for duration: TimeInterval? = nil) throws {
        guard let managedObjectContext else { throw AccessoryError.missingManagedObjectContext }

        let firstEvent = ScheduledPowerEvent(context: managedObjectContext)
        firstEvent.accessory = self
        firstEvent.on = poweredOn
        firstEvent.timestamp = Date.timeIntervalSinceReferenceDate + delay

        if let duration {
            let secondEvent = ScheduledPowerEvent(context: managedObjectContext)
            secondEvent.accessory = self
            secondEvent.on = !poweredOn
            secondEvent.timestamp = firstEvent.timestamp + duration
        }
    }
}
