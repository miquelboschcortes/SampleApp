/*
See LICENSE folder for this sample’s licensing information.

Abstract:
 A class to manage data persistence through CoreData.
*/

import CoreData

public class PersistenceController {
    public static let shared: PersistenceController = {
        let result = PersistenceController()
        if (try? result.container.viewContext.count(for: Accessory.fetchRequest())) == 0 {
            result.setupInitialAppliances()
        }
        return result
    }()

    public static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        result.setupWithDummyData()
        return result
    }()

    public let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        guard let energyBundle = Bundle(identifier: "com.example.apple.samplecode.energy-framework"),
              let modelURL = energyBundle.url(forResource: "Model", withExtension: "momd"),
              let mom = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Could not load the model from the framework")
        }
        container = NSPersistentContainer(name: "Model", managedObjectModel: mom)
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { _, error in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate.
                // You should not use this function in a shipping application, although it may be
                // useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when
                   the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private func setupWithDummyData() {
        let viewContext = container.viewContext

        // Dummy accessories
        for index in 1...3 {
            let newAccessory = Accessory(context: viewContext)
            newAccessory.name = "Appliance \(index)"
            newAccessory.icon = "lamp.desk"
            newAccessory.powerWhenOn = 20.0
        }

        let now = Date.timeIntervalSinceReferenceDate

        // Dummy accessory consumption (watts)
        let table1 = [1230.0, 1430.0, 2430.0, 2030.0, 2130.0, 870.0, 2100.0]
        for value in table1.enumerated() {
            let item = AccessoryConsumption(context: viewContext)
            item.timestamp = now - Double(table1.count - value.offset) * 60.0
            item.power = value.element
        }

        // Dummy generator output (watts)
        let table2 = [4000.0, 4000.0, 3000.0, 3000.0, 3000.0, 3000.0, 4000.0]
        for value in table2.enumerated() {
            let item = GeneratorOutput(context: viewContext)
            item.timestamp = now - Double(table2.count - value.offset) * 60.0
            item.power = value.element
        }

        // Dummy battery charge (watt hours)
        let table3 = [0.90, 0.94, 0.85, 0.87, 0.89, 0.93, 0.94]
            .map { $0 * HomeBattery.maxCapacity}
        for value in table3.enumerated() {
            let item = BatteryCharge(context: viewContext)
            item.timestamp = now - Double(table3.count - value.offset) * 60.0
            item.charge = value.element
        }

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }

    private func setupInitialAppliances() {
        let context = container.viewContext
        let appliances = [
            (
                name: "Kitchen Lights",
                icon: "light.recessed.3",
                powerWhenOn: 50.0
            ),
            (
                name: "Dishwasher",
                icon: "dishwasher",
                powerWhenOn: 1500.0
            ),
            (
                name: "Air Conditioning",
                icon: "air.conditioner.horizontal",
                powerWhenOn: 3500.0
            ),
            (
                name: "Oven",
                icon: "oven",
                powerWhenOn: 2200.0
            ),
            (
                name: "Living Room Lights",
                icon: "lamp.floor",
                powerWhenOn: 90.0
            )
        ]

        for appliance in appliances {
            let accessory = Accessory(context: context)
            accessory.name = appliance.name
            accessory.icon = appliance.icon
            accessory.powerWhenOn = appliance.powerWhenOn
        }
        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }

    public static func addMoreAppliances(to context: NSManagedObjectContext) {
        let appliances = [
            (
                name: "Hallway Lights",
                icon: "light.cylindrical.ceiling",
                powerWhenOn: 40.0
            ),
            (
                name: "Car Charger",
                icon: "bolt.car",
                powerWhenOn: 24000.0
            ),
            (
                name: "Humidifier",
                icon: "humidifier.and.droplets",
                powerWhenOn: 20.0
            ),
            (
                name: "Microwave",
                icon: "microwave",
                powerWhenOn: 1100.0
            )
        ]

        for appliance in appliances {
            let accessory = Accessory(context: context)
            accessory.name = appliance.name
            accessory.icon = appliance.icon
            accessory.powerWhenOn = appliance.powerWhenOn
        }
        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }

    // MARK: -

    func makeTaskContext() -> NSManagedObjectContext {
        // Create a private queue context.
        let taskContext = container.newBackgroundContext()
        taskContext.automaticallyMergesChangesFromParent = true
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return taskContext
    }

    static func save(context: NSManagedObjectContext) {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }

    func makeChildContext() -> NSManagedObjectContext {
        // Create a child context of the view context.
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.parent = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    func save(childContext context: NSManagedObjectContext) {
        if context.hasChanges {
            do {
                try context.save()
                if let parent = context.parent,
                   parent == container.viewContext {
                    try parent.performAndWait {
                        try parent.save()
                    }
                }
            } catch {
                let nserror = error as NSError
                fatalError("Unresolved error \(nserror), \(nserror.userInfo)")
            }
        }
    }
}
