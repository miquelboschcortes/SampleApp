/*
See LICENSE folder for this sample’s licensing information.

Abstract:
 A class emulating functionality related to energy generation, consumption and storage
 in a fictional home setup.
*/

import Foundation
import CoreData
import SwiftUI
import OSLog

public final class HomeEmulator: ObservableObject {
    public var generator: HomeGenerator
    public var battery: HomeBattery

    /// Aggregate power consumption of all accessories that are currently switched on, in watts.
    @Published public private(set) var powerConsumption: Double

    private let persistenceController: PersistenceController

    private var heartbeatTimer: Timer?

    public var statusDescription: String {
        powerConsumption > 0 ? "In Use" : "Idle"
    }

    public enum HealthLevel: Sendable {
        case healthy
        case warning(TimeInterval)
        case critical(TimeInterval)

        public var attributedDescription: AttributedString {
            var result: AttributedString
            switch self {
            case .critical:
                result = AttributedString("Critical")
                result.foregroundColor = .systemRed
            case .warning:
                result = AttributedString("Warning - high consumption")
                result.foregroundColor = .systemOrange
            case .healthy:
                result = AttributedString("Healthy")
            }
            return result
        }
    }

    public var healthLevel: HealthLevel {
        switch timeToEmptyBattery {
        case ...(60 * 60):
            return .critical(timeToEmptyBattery)
        case ...(12 * 60 * 60):
            return .warning(timeToEmptyBattery)
        default:
            return .healthy
        }
    }

    /// Estimate of the time remaining before the battery will be completely drained, assuming no futher user intervention.

    public var timeToEmptyBattery: TimeInterval {
        // Over time, we can work on the assumption that the generator output will remain constant.
        // On the other hand, there may be scheduled power ons or power offs that we need to take into account.
        // To compute the time to empty battery, we integrate the power usage (accessory consumption - generated
        // power) over time, and stop when it grows beyond the current battery charge, or - at the latest - when
        // we reach the last scheduled power event.

        /// Power being consumed, in watts
        var power = powerConsumption - generator.powerOutput

        /// Energy that will be used from now, in watt hours
        var energyConsumed = 0.0

        // If we're already consuming more power than is being generated, and our battery is dead,
        // then return zero.
        if power > 0 && battery.charge == 0 {
            return 0
        }

        var time = Date.timeIntervalSinceReferenceDate
        var cachedPowerState: [Accessory: Bool] = [:]
        let request = ScheduledPowerEvent.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ScheduledPowerEvent.timestamp, ascending: true)]
        if let events = try? viewContext.fetch(request) {
            for event in events {
                let timeToEvent = max(0.0, event.timestamp - time)
                // Check that the scheduled event is actually changing the power state
                // of the accessory, and not e.g. switching on an accessory that's already on.
                if let accessory = event.accessory,
                   event.on != cachedPowerState[accessory, default: accessory.on] {
                    let energyDelta = power * timeToEvent / 3600.0
                    if energyConsumed + energyDelta >= battery.charge {
                        return time + battery.charge / power * 3600.0
                    }
                    // Update our state to the new time when the scheduled power change occurs.
                    energyConsumed += energyDelta
                    time += timeToEvent
                    power += accessory.powerWhenOn * (event.on ? 1.0 : -1.0)
                    cachedPowerState[accessory] = event.on
                }
            }
        }

        // At this point, we know that `energyConsumed < battery.charge`.
        guard power > 0 else { return .infinity }

        return (battery.charge - energyConsumed) / power * 3600.0
    }

    public var viewContext: NSManagedObjectContext {
        persistenceController.container.viewContext
    }

    // MARK: -

    public enum ExecutionMode: Sendable {
        case keepRunning
        case updateOnce
        case doNothing
    }

    public init(inMemory: Bool = false, executionMode: ExecutionMode = .keepRunning) {
        if inMemory {
            persistenceController = PersistenceController.preview
        } else {
            persistenceController = PersistenceController.shared
        }

        generator = HomeGenerator(context: persistenceController.container.viewContext)
        let consumption = Self.fetchAccessoryConsumption(context: persistenceController.container.viewContext)
        powerConsumption = consumption
        battery = HomeBattery(
            initialChargingPower: generator.powerOutput - consumption,
            context: persistenceController.container.viewContext
        )

        switch executionMode {
        case .keepRunning:
            heartbeatTimer = Timer(timeInterval: heartbeatInterval, repeats: true) { [self] _ in heartbeat() }
            if let heartbeatTimer {
                RunLoop.current.add(heartbeatTimer, forMode: .common)
            }
        case .updateOnce:
            // Run this once, to generate data points corresponding to the current time.
            heartbeat()
        case .doNothing:
            break
        }
    }

    deinit {
        heartbeatTimer?.invalidate()
    }

    /// Simulate the way energy levels vary over time.

    private var heartbeatInterval = 1.0

    private func heartbeat() {
        let context = PersistenceController.shared.makeTaskContext()
        context.perform { [self] in
            do {
                try processScheduledActions(context: context)
                try updateAccessoryConsumption(context: context)
                try updateBatteryCharge(context: context)
            } catch {
                fatalError("Unresolved error while fetching battery data.")
            }

            PersistenceController.save(context: context)
        }
    }
}

// MARK: -

extension HomeEmulator {
    /// Process any pending scheduled power events.

    private func processScheduledActions(context: NSManagedObjectContext) throws {
        let request = ScheduledPowerEvent.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K < %@", #keyPath(ScheduledPowerEvent.timestamp),
            Date.now as NSDate
        )
        let actions = try context.fetch(request)
        for action in actions {
            action.accessory?.on = action.on
            Logger.energy.debug("""
                scheduled event: switching \(action.on ? "on" : "off") \
                “\(action.accessory?.name ?? "unknown")”
                """)
            context.delete(action)
        }
    }

    /// This is where we update the battery charge based on generated energy and energy consumption by accessories.

    private func updateBatteryCharge(context: NSManagedObjectContext) throws {
        // First, we check if anyone has stored a new battery charge within the last interval.
        // In fact, another process using the same framework may have done so.
        // It won't do any harm repeating the work, but it's unnecessary so we check here.

        // We look at existing battery charge data within a time window that allows for
        // some tolerance, equal to 10% of the timer interval.
        let tolerance = heartbeatInterval * 0.1
        let now = Date.timeIntervalSinceReferenceDate
        let request = BatteryCharge.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K < %@",
            #keyPath(BatteryCharge.timestamp),
            NSDate(timeIntervalSinceReferenceDate: now + tolerance)
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BatteryCharge.timestamp, ascending: false)]
        request.fetchLimit = 1
        if let lastCharge = try context.fetch(request).first {
            if (now - heartbeatInterval + tolerance) ..< now + tolerance ~= lastCharge.timestamp {
                // We have very recent battery charge data, no need to generate a new data point now.

                Logger.energy.debug("""
                    battery update: we have recent data from \(Date(timeIntervalSinceReferenceDate: lastCharge.timestamp)): \
                    charge = \(lastCharge.charge) Wh
                    """)
            } else {
                // Compute the new battery charge based on current consumption.
                let timeDelta = now - lastCharge.timestamp
                let powerDelta = generator.powerOutput - powerConsumption
                battery.update(charge: lastCharge.charge + powerDelta * timeDelta / 3600.0, at: powerDelta)

                let batteryCharge = BatteryCharge(context: context)
                batteryCharge.timestamp = now
                batteryCharge.charge = battery.charge

                Logger.energy.debug("""
                    battery update: storing charge = \(batteryCharge.charge) Wh, \
                    \(timeDelta.formatted(.number.precision(.fractionLength(3)))) s. since last data point
                    """)
            }
        } else {
            // We don't have any past battery charge data, generate a new data point now.
            battery.update(charge: HomeBattery.factoryCharge, at: 0.0)

            let batteryCharge = BatteryCharge(context: context)
            batteryCharge.timestamp = now
            batteryCharge.charge = battery.charge

            Logger.energy.debug("battery update: initializing charge to \(batteryCharge.charge) Wh")
        }
    }

    /// This is where we update `powerConsumption`, which is the cached aggregate power consumption of all accessories
    /// based on their state.

    private func updateAccessoryConsumption(context: NSManagedObjectContext) throws {
        let consumption = Self.fetchAccessoryConsumption(context: context)
        if consumption != powerConsumption {
            DispatchQueue.main.sync { [self] in
                powerConsumption = consumption
            }
        }

        // We look at existing consumption data within a time window that allows for
        // some tolerance, equal to 10% of the timer interval.
        let tolerance = heartbeatInterval * 0.1
        let now = Date.timeIntervalSinceReferenceDate
        let request = AccessoryConsumption.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(
                format: "%K < %@",
                #keyPath(AccessoryConsumption.timestamp),
                NSDate(timeIntervalSinceReferenceDate: now + tolerance)
            ),
            NSPredicate(
                format: "%K == NULL",
                #keyPath(AccessoryConsumption.accessory)
            )
        ])
        request.sortDescriptors = [NSSortDescriptor(keyPath: \AccessoryConsumption.timestamp, ascending: false)]
        request.fetchLimit = 1
        if let lastItem = try context.fetch(request).first,
           (now - heartbeatInterval + tolerance) ..< now + tolerance ~= lastItem.timestamp || lastItem.power == consumption {
            // We have very recent consumption data, no need to generate a new data point now.
            Logger.energy.debug("""
                consumption update: we have recent data from \(Date(timeIntervalSinceReferenceDate: lastItem.timestamp)): \
                power = \(lastItem.power) W
                """)
        } else {
            // Store updated aggregate consumption data.
            let item = AccessoryConsumption(context: context)
            item.timestamp = now
            item.power = consumption

            Logger.energy.debug("consumption update: storing power = \(item.power) W")

            // Store updated accessory-specific consumption data.
            for accessory in try Self.fetchAccessories(context: context) {
                let item = AccessoryConsumption(context: context)
                item.timestamp = now
                item.power = accessory.on ? accessory.powerWhenOn : 0.0
                item.accessory = accessory
            }
        }
    }

    private static func fetchAccessories(poweredOn: Bool? = nil, context: NSManagedObjectContext) throws -> [Accessory] {
        let request = Accessory.fetchRequest()
        if let poweredOn {
            request.predicate = NSPredicate(format: "%K == %@", #keyPath(Accessory.on), poweredOn as NSNumber)
        }
        return try context.fetch(request)
    }

    private static func fetchAccessoryConsumption(context: NSManagedObjectContext) -> Double {
        do {
            let accessories = try Self.fetchAccessories(poweredOn: true, context: context)
            return accessories.reduce(0.0) { partialResult, accessory in
                partialResult + accessory.powerWhenOn
            }
        } catch {
            fatalError("Unresolved error while fetching accessory data.")
        }
    }

    public struct EnergyMetrics: Sendable {
        public var time: Date
        public var consumption: Double        // Consumption by all accessories, watts
        public var chargeLevel: Double        // Percent
        public var chargingState: HomeBattery.ChargingState
        public var timeToEmpty: TimeInterval
    }

    public func predictFutureEnergyMetrics() -> [EnergyMetrics] {
        var metrics: [EnergyMetrics] = []

        // To predict how the energy metrics will evolve over time, we assume that the generator output
        // will remain constant and that no new power on or off events will be scheduled by the user,
        // in addition to the ones we already know about.

        let now = Date.timeIntervalSinceReferenceDate
        var time = now
        var timeToEmpty = timeToEmptyBattery
        let increment: TimeInterval = 3.0

        metrics.append(EnergyMetrics(
            time: Date(timeIntervalSinceReferenceDate: time),
            consumption: powerConsumption,
            chargeLevel: battery.chargeLevel,
            chargingState: battery.chargingState,
            timeToEmpty: timeToEmpty
        ))

        /// Power being drawn, in watts
        var power = powerConsumption - generator.powerOutput

        /// Battery energy that will be used from now, in watt hours
        var energyConsumed = 0.0

        var cachedPowerState: [Accessory: Bool] = [:]
        let request = ScheduledPowerEvent.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ScheduledPowerEvent.timestamp, ascending: true)]
        if let events = try? viewContext.fetch(request) {
            for event in events {
                let timeToEvent = max(0.0, event.timestamp - time)
                // Check that the scheduled event is actually changing the power state
                // of the accessory, and not e.g. switching on an accessory that's already on.
                if let accessory = event.accessory,
                   event.on != cachedPowerState[accessory, default: accessory.on] {

                    /// Energy decrease over `timeToEvent`, in watt hours
                    let energyDelta = power * timeToEvent / 3600.0

                    // Update state linearly every `increment` seconds between `time` and the scheduled event time.
                    for timeStep in stride(from: increment, to: timeToEvent, by: increment) {
                        let chargeLevel = ((battery.charge - energyConsumed - energyDelta * timeStep / timeToEvent) / HomeBattery.maxCapacity)
                            .clamped(to: 0.0 ... 1.0)
                        metrics.append(EnergyMetrics(
                            time: Date(timeIntervalSinceReferenceDate: time + timeStep),
                            consumption: power + generator.powerOutput,
                            chargeLevel: chargeLevel,
                            chargingState: HomeBattery.ChargingState.state(forPower: -energyDelta, chargeLevel: chargeLevel),
                            timeToEmpty: timeToEmpty - timeStep
                        ))
                    }

                    // Update state to the new time when the scheduled power change occurs.
                    energyConsumed = (energyConsumed + energyDelta)
                        .clamped(to: -(HomeBattery.maxCapacity - battery.charge) ... battery.charge)
                    let remainingBatteryCharge = battery.charge - energyConsumed
                    power += accessory.powerWhenOn * (event.on ? 1.0 : -1.0)
                    cachedPowerState[accessory] = event.on
                    time += timeToEvent
                    timeToEmpty -= timeToEvent

                    let chargeLevel = remainingBatteryCharge / HomeBattery.maxCapacity
                    metrics.append(EnergyMetrics(
                        time: Date(timeIntervalSinceReferenceDate: time),
                        consumption: power + generator.powerOutput,
                        chargeLevel: chargeLevel,
                        chargingState: HomeBattery.ChargingState.state(forPower: -energyDelta, chargeLevel: chargeLevel),
                        timeToEmpty: timeToEmpty
                    ))
                }
            }
        }

        // If we have generated less than 15 minutes worth of metrics, generate more now.
        let timeToEnd = now + 15 * 60 - time
        var lastChargeLevel: Double?
        for timeStep in stride(from: increment, to: timeToEnd, by: increment) {
            let chargeLevel = ((battery.charge - energyConsumed - power * timeStep / 3600.0) / HomeBattery.maxCapacity)
                .clamped(to: 0.0 ... 1.0)
            // We want the battery level to differ at least half a percent from the previous value,
            // in order to append a new entry.
            if abs(chargeLevel - (lastChargeLevel ?? -1.0)) > 0.005 {
                metrics.append(EnergyMetrics(
                    time: Date(timeIntervalSinceReferenceDate: time + timeStep),
                    consumption: power + generator.powerOutput,
                    chargeLevel: chargeLevel,
                    chargingState: HomeBattery.ChargingState.state(forPower: -power, chargeLevel: chargeLevel),
                    timeToEmpty: timeToEmpty - timeStep
                ))
                lastChargeLevel = chargeLevel
            }
        }

        return metrics
    }
}

// MARK: -

extension HomeEmulator {
    public static var preview: HomeEmulator = {
        let result = HomeEmulator(inMemory: true, executionMode: .doNothing)
        return result
    }()
}

// MARK: - Generator

public class HomeGenerator: ObservableObject {
    /// Power output from the generator, in watts.
    @Published public var powerOutput: Double {
        didSet {
            guard powerOutput != oldValue else { return }
            storePowerSetting()
        }
    }
    public static let powerOutputRange = 0.0 ... 3500.0
    public var statusDescription: String { powerOutput > 0 ? "Running" : "Idle" }

    init(context: NSManagedObjectContext) {
        // Retrieve the latest power output setting
        let request = GeneratorOutput.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \GeneratorOutput.timestamp, ascending: false)]
        request.fetchLimit = 1
        if let power = try? context.fetch(request).first?.power {
            powerOutput = power.clamped(to: Self.powerOutputRange)
        } else {
            powerOutput = 3000    // Initial default value
            storePowerSetting()
        }
    }
}

extension HomeGenerator {
    /// Stores the generator power setting to the database.
    private func storePowerSetting() {
        let context = PersistenceController.shared.makeTaskContext()
        let value = powerOutput
        context.perform {
            let generatorPower = GeneratorOutput(context: context)
            generatorPower.timestamp = Date.timeIntervalSinceReferenceDate
            generatorPower.power = value
            PersistenceController.save(context: context)

            Logger.energy.debug("generator update: storing power = \(value) W")
        }
    }
}

// MARK: - Battery

/// Emulates a battery backup system for a home.
public class HomeBattery: ObservableObject {

    /// The power currently being discharged from the battery (positive values)
    /// or charging the battery (negative values), in watts.
    @Published public private(set) var chargingPower: Double

    /// The level of charge in the battery, in watt-hours.
    @Published public private(set) var charge: Double

    init(initialChargingPower: Double, context: NSManagedObjectContext) {
        chargingPower = initialChargingPower

        let request = BatteryCharge.fetchRequest()
        request.predicate = NSPredicate(format: "%K < %@", #keyPath(BatteryCharge.timestamp), NSDate(timeIntervalSinceNow: 0))
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BatteryCharge.timestamp, ascending: false)]
        request.fetchLimit = 1
        if let lastCharge = try? context.fetch(request).first {
            charge = lastCharge.charge
        } else {
            charge = Self.factoryCharge
        }
    }
}

extension HomeBattery {

    /// The maximum level of charge in the battery, in watt-hours.
    public static let maxCapacity = 100.0

    /// The level of charge in the battery as it comes from the factory, in watt-hours.
    public static let factoryCharge = 50.0
}

extension HomeBattery {

    /// Battery charge level, normalized to the 0...1 range.
    public var chargeLevel: Double { charge / Self.maxCapacity }

    public var chargingState: ChargingState {
        ChargingState.state(forPower: chargingPower, chargeLevel: chargeLevel)
    }

    public var statusDescription: String {
        chargingState.description
    }

    public var lowBattery: Bool {
        chargeLevel < 0.2
    }

    fileprivate func update(charge newValue: Double, at power: Double) {
        DispatchQueue.main.sync { [self] in
            charge = newValue.clamped(to: 0.0 ... Self.maxCapacity)
            chargingPower = charge > 0.0 ? power : 0.0
        }
    }
}

extension HomeBattery {
    public enum ChargingState: Sendable {
        case fullyCharged
        case charging
        case discharging
        case empty
        case notCharging
    }
}

extension HomeBattery.ChargingState {
    public static func state(forPower power: Double, chargeLevel level: Double) -> Self {
        switch power {
        case 0:
            return level == 1.0 ? .fullyCharged : .notCharging
        case ..<0:
            return level > 0.0 ? .discharging : .empty
        case 0...:
            return level < 1.0 ? .charging : .fullyCharged
        default:
            return .notCharging
        }
    }
}

extension HomeBattery.ChargingState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fullyCharged: return "Fully Charged"
        case .charging: return "Charging"
        case .discharging: return "Discharging"
        case .empty: return "Empty"
        case .notCharging: return "Not Charging"
        }
    }
}
