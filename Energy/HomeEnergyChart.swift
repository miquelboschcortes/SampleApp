/*
See LICENSE folder for this sample’s licensing information.

Abstract:
 A chart of historical energy consumption, generation and storage.
*/

import SwiftUI
import Charts

public struct HomeEnergyChart: View {

    static let timeframe: TimeInterval = 5 * 60.0

    @FetchRequest
    private var consumption: FetchedResults<AccessoryConsumption>

    @FetchRequest
    private var generatorOutput: FetchedResults<GeneratorOutput>

    @FetchRequest
    private var batteryCharge: FetchedResults<BatteryCharge>

    /// Creates a chart showing energy consumption, generation and battery charge based
    /// on the managed object context.
    ///
    /// - Parameters:
    ///   - accessory: When `nil`, the chart displays overall metrics on the energy state.
    ///   Otherwise, the chart will only show energy consumption data specific to one accessory.

    public init(for accessory: Accessory? = nil) {
        _consumption = FetchRequest<AccessoryConsumption>(
            sortDescriptors: [SortDescriptor(\.timestamp, order: .forward)],
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                {
                    if let accessory {
                        return NSPredicate(
                            format: "%K == %@",
                            #keyPath(AccessoryConsumption.accessory),
                            accessory
                        )
                    } else {
                        return NSPredicate(
                            format: "%K == NULL",
                            #keyPath(AccessoryConsumption.accessory)
                        )
                    }
                }(),
                NSPredicate(
                    format: "%K <= %@",
                    #keyPath(AccessoryConsumption.timestamp),
                    NSDate(timeIntervalSinceNow: 0)
                )
            ]),
            animation: .none
        )
        _generatorOutput = FetchRequest<GeneratorOutput>(
            sortDescriptors: [SortDescriptor(\.timestamp, order: .forward)],
            predicate: accessory != nil ? NSPredicate(value: false) : NSPredicate(
                format: "%K <= %@",
                #keyPath(GeneratorOutput.timestamp),
                NSDate(timeIntervalSinceNow: 0)
            ),
            animation: .none
        )
        _batteryCharge = FetchRequest<BatteryCharge>(
            sortDescriptors: [SortDescriptor(\.timestamp, order: .forward)],
            predicate: accessory != nil ? NSPredicate(value: false) : NSPredicate(
                format: "(%K >= %@) AND (%K <= %@)",
                #keyPath(BatteryCharge.timestamp),
                NSDate(timeIntervalSinceNow: -Self.timeframe),
                #keyPath(BatteryCharge.timestamp),
                NSDate(timeIntervalSinceNow: 0)
            ),
            animation: .none
        )
    }

    public var body: some View {
        Chart {
            ForEach(chargeData) { point in
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("battery", point.value)
                )
                .foregroundStyle(Color.blue.opacity(0.25))
                .interpolationMethod(.monotone)
            }
            ForEach(energyData, id: \.metric) { series in
                ForEach(series.data) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value(series.metric, point.value)
                    )
                    .foregroundStyle(by: .value("Metric", series.metric))
                    .interpolationMethod(series.interpolation)
                }
            }
        }
        .chartForegroundStyleScale([
            "consumption": Color.orange,
            "generation": Color.green,
            "battery": Color.blue
        ])
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: IntegerFormatStyle<Int>())
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute(), centered: false, collisionResolution: .greedy)
            }
        }
    }
}

extension HomeEnergyChart {

    // UI model for the energy chart
    struct EnergyDataset {
        struct Point: Identifiable {
            let id = UUID()
            var time: Date
            var value: Double
        }

        var metric: String
        var data: [Point]
        var interpolation: InterpolationMethod
        var color: Color
    }

    var energyData: [EnergyDataset] {
        let minimumDate = Date.timeIntervalSinceReferenceDate - Self.timeframe

        var consumptionData: [EnergyDataset.Point] = []
        if !consumption.isEmpty {
            let indexBeforeVisibleRange = consumption.lastIndex(where: { $0.timestamp < minimumDate }) ?? 0

            consumptionData = [EnergyDataset.Point(
                time: Date(timeIntervalSinceReferenceDate: minimumDate),
                value: consumption[indexBeforeVisibleRange].power)
            ] + consumption
                .dropFirst(indexBeforeVisibleRange + 1)
                .map { item in
                    EnergyDataset.Point(time: Date(timeIntervalSinceReferenceDate: item.timestamp), value: item.power)
                }
            if let last = consumptionData.last {
                consumptionData.append(EnergyDataset.Point(time: Date.now, value: last.value))
            }
        }

        var generatorData: [EnergyDataset.Point] = []
        if !generatorOutput.isEmpty {
            let indexBeforeVisibleRange = generatorOutput.lastIndex(where: { $0.timestamp < minimumDate }) ?? 0

            generatorData = [EnergyDataset.Point(
                time: Date(timeIntervalSinceReferenceDate: minimumDate),
                value: generatorOutput[indexBeforeVisibleRange].power)
            ] + generatorOutput
                .dropFirst(indexBeforeVisibleRange + 1)
                .map { item in
                    EnergyDataset.Point(time: Date(timeIntervalSinceReferenceDate: item.timestamp), value: item.power)
                }
            if let last = generatorData.last {
                generatorData.append(EnergyDataset.Point(time: Date.now, value: last.value))
            }
        }

        return [
            EnergyDataset(
                metric: "consumption",
                data: consumptionData,
                interpolation: .stepEnd,
                color: Color.orange
            ),
            EnergyDataset(
                metric: "generation",
                data: generatorData,
                interpolation: .linear,
                color: Color.green
            )
        ]
    }

    var chargeData: [EnergyDataset.Point] {
        batteryCharge.map { item in
            EnergyDataset.Point(
                time: Date(timeIntervalSinceReferenceDate: item.timestamp),
                value: item.charge / HomeBattery.maxCapacity * HomeGenerator.powerOutputRange.upperBound
            )
        }
    }
}

struct HomeEnergyChart_Previews: PreviewProvider {
    static var previews: some View {
        let chart = HomeEnergyChart()

        Group {
            chart
            chart.preferredColorScheme(.dark)
        }
        .previewLayout(.sizeThatFits)
        .frame(width: 300, height: 200)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
