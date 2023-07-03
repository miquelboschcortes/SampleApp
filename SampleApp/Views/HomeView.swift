/*
See LICENSE folder for this sample’s licensing information.

Abstract:
 A view showing overall energy generation, consumption and storage,
 along with an indication of health based on projected consumption.
*/

import SwiftUI
import CoreData
import Energy

struct HomeView: View {
    @EnvironmentObject private var homeEmulator: HomeEmulator
    @EnvironmentObject private var homeGenerator: HomeGenerator

    private var didSave = NotificationCenter.default.publisher(
        for: .NSManagedObjectContextDidSave
    ).receive(on: DispatchQueue.main)

    @Environment(\.isSwiftPreview) private var isSwiftPreview

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 5.0) {
                    // House
                    EnergyCardView(
                        text: homeEmulator.statusDescription,
                        color: .orange) {
                            Image(systemName: "house")
                                .font(.system(size: 84.0))
                                .frame(width: 100.0, height: 100.0, alignment: .bottom)
                            HStack(spacing: 4.0) {
                                if homeGenerator.powerOutput - homeEmulator.battery.chargingPower >= homeEmulator.powerConsumption {
                                    Image(systemName: "bolt")
                                } else {
                                    Image(systemName: "bolt.slash")
                                }
                                Text(Measurement(
                                    value: homeEmulator.powerConsumption,
                                    unit: UnitPower.watts
                                ).formatted(.measurement(width: .abbreviated)))
                                Image(systemName: "arrow.down")
                                    .opacity(homeEmulator.powerConsumption > 0 ? 1.0 : 0.0)
                            }
                            .fontWeight(.semibold)
                        }

                    FluxView()

                    HStack(alignment: .top, spacing: 70.0) {
                        // Battery
                        EnergyCardView(
                            text: homeEmulator.battery.statusDescription,
                            color: .blue) {
                                ZStack(alignment: .center) {
                                    Image(systemName: "batteryblock")
                                        .font(.system(size: 84.0))
                                    Text(homeEmulator.battery.chargeLevel.formatted(.percent.precision(.fractionLength(0))))
                                        .fontWeight(.heavy)
                                        .font(.system(size: 24.0, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundColor(homeEmulator.battery.lowBattery ? .red : .primary)
                                        .padding([.top], 10.0)
                                }
                                .frame(width: 100.0, height: 100.0, alignment: .bottom)
                                HStack(spacing: 4.0) {
                                    Image(systemName: "bolt")
                                    if homeEmulator.battery.chargingPower == 0 {
                                        Text("–")
                                    } else {
                                        Text(Measurement(
                                            value: homeEmulator.battery.chargingPower.magnitude,
                                            unit: UnitPower.watts
                                        ).formatted(.measurement(width: .abbreviated)))
                                        if homeEmulator.battery.chargingPower < 0 {
                                            Image(systemName: "arrow.down")
                                        } else {
                                            Image(systemName: "arrow.up")
                                        }
                                    }
                                }
                                .fontWeight(.semibold)
                            }

                        // Generator
                        EnergyCardView(
                            text: homeGenerator.statusDescription,
                            color: .green) {
                                Image(systemName: "bolt.square")
                                    .font(.system(size: 84.0))
                                    .frame(width: 100.0, height: 100.0, alignment: .bottom)
                                HStack(spacing: 4.0) {
                                    Image(systemName: "bolt")
                                    Text(Measurement(
                                        value: homeGenerator.powerOutput.magnitude,
                                        unit: UnitPower.watts
                                    ).formatted(.measurement(width: .abbreviated)))
                                    if homeGenerator.powerOutput > 0 {
                                        Image(systemName: "arrow.up")
                                    }
                                }
                                .fontWeight(.semibold)
                            }
                    }

                    // Chart
                    VStack(alignment: .leading) {
                        Text("Energy Balance")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(homeEmulator.healthLevel.attributedDescription)
                            .font(.headline)
                        HomeEnergyChart()
                            .frame(height: 150.0)
                    }
                    .onReceive(didSave) { _ in
                        if !isSwiftPreview {
                            homeGenerator.objectWillChange.send()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Home Status")
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(HomeEmulator.preview)
            .environmentObject(HomeEmulator.preview.generator)
            .environmentObject(HomeEmulator.preview.battery)
            .environment(\.isSwiftPreview, true)
    }
}

private struct IsSwiftPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSwiftPreview: Bool {
        get { self[IsSwiftPreviewKey.self] }
        set { self[IsSwiftPreviewKey.self] = newValue }
    }
}

// MARK: - Card view

struct EnergyCardView<Content>: View where Content: View {
    let text: String
    let color: Color

    let content: Content

    public init(text: String, color: Color, @ViewBuilder content: () -> Content) {
        self.text = text
        self.color = color
        self.content = content()
    }

    var body: some View {
        VStack {
            content
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            color.opacity(0.2).gradient,
            in: RoundedRectangle(
                cornerSize: CGSize(width: 14, height: 14),
                style: .continuous
            )
        )
    }
}

// MARK: - Flux

struct FluxLineShape: Shape {
    // `offset` is expressed in normalized coordinates, we use it to draw the arc
    // just below the bottom edge of the frame.
    static let offset = 0.2
    static let anchor = UnitPoint(x: 0.5, y: 0.5 + offset)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.size.width                // Arc radius
        let height = sqrt(3.0) * 0.5 * radius        // Height of the equilateral triangle with side == our width
        path.addRelativeArc(
            center: CGPoint(x: rect.midX, y: rect.maxY + height + radius * Self.offset),
            radius: radius,
            startAngle: .degrees(-120.0),
            delta: .degrees(60.0)
        )
        return path
    }
}

struct FluxLineView: View {
    var segment: Int
    var animated: Bool
    var forward = true
    @State private var phase = 0.0

    var body: some View {
        FluxLineShape()
            .rotation(.degrees(Double(120 * segment)), anchor: FluxLineShape.anchor)
            .stroke(style: StrokeStyle(
                lineWidth: 5,
                lineCap: .round,
                lineJoin: .round,
                dash: animated ? [8, 8] : [],
                dashPhase: forward ? phase : (32 - phase)
            ))
            .shadow(color: .blue, radius: animated ? 8.0 : 0.0)
            .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: phase)
            .onAppear {
                if animated {
                    phase = 32
                }
            }
    }
}

struct FluxView: View {
    @EnvironmentObject private var homeEmulator: HomeEmulator
    @EnvironmentObject private var homeGenerator: HomeGenerator
    @EnvironmentObject private var homeBattery: HomeBattery
    @Environment(\.isSwiftPreview) private var isSwiftPreview

    var body: some View {
        ZStack {
            // Generator to battery
            FluxLineView(
                segment: 0,
                animated: isSwiftPreview || homeBattery.chargingState == .charging
            )
            .foregroundColor(.green)

            // Battery to home
            FluxLineView(
                segment: 1,
                animated: homeEmulator.powerConsumption > homeGenerator.powerOutput && homeBattery.charge > 0
            )
            .foregroundColor(.green)

            // Generator to home
            FluxLineView(
                segment: 2,
                animated: homeGenerator.powerOutput > 0 && homeEmulator.powerConsumption > 0,
                forward: false
            )
            .foregroundColor(.green)
        }
        .frame(width: 60, height: 60)
    }
}
