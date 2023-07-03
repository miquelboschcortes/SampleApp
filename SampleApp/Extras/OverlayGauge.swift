/*
See LICENSE folder for this sample’s licensing information.

Abstract:
 A gauge style that displays a large solid bar.
*/

import SwiftUI
import WidgetKit

public struct OverlayGauge<Label: View, CurrentValueLabel: View>: View {
	public var value: Double
	public var bounds: ClosedRange<Double>
	@ViewBuilder public var label: () -> Label
	@ViewBuilder public var currentValueLabel: () -> CurrentValueLabel

	public init(
		value: Double,
		in bounds: ClosedRange<Double> = 0...1,
		label: @escaping () -> Label,
		currentValueLabel: @escaping () -> CurrentValueLabel
	) {
		self.value = value.clamped(to: bounds)
		self.bounds = bounds
		self.label = label
		self.currentValueLabel = currentValueLabel
	}

	public var body: some View {
		Gauge(value: value, in: bounds, label: label, currentValueLabel: currentValueLabel)
			.gaugeStyle(OverlayGaugeStyle())
	}
}

struct OverlayGaugeStyle: GaugeStyle {
	private var metrics = Metrics()

	func makeBody(configuration: Configuration) -> some View {
		GeometryReader { proxy in
			ZStack(alignment: .leading) {
				RoundedRectangle(cornerRadius: metrics.cornerRadius)
					.fill(.secondary)
					.opacity(metrics.unfilledOpacity)
				RoundedRectangle(cornerRadius: metrics.cornerRadius - metrics.barInset)
					.fill(.primary)
					.frame(width: (proxy.size.width - metrics.barInset * 2.0) * configuration.value)
					.padding(metrics.barInset)
				HStack {
					configuration.label
						.padding(.leading)
					Spacer()
					configuration.currentValueLabel
						.padding(.trailing)
				}
				.colorScheme(.dark)
				.blendMode(.difference)
			}
			.frame(height: metrics.height)
		}
	}

	struct Metrics {
		var height: CGFloat { 40.0 }
		var cornerRadius: CGFloat { 8.0 }
		var barInset: CGFloat { 2.0 }
		var unfilledOpacity: Double { 0.35 }
	}
}

struct OverlayGaugeStyle_Previews: PreviewProvider {
	static var previews: some View {
		let value = 0.9

		OverlayGauge(value: value) {
			Image(systemName: "bolt.batteryblock.fill")
		} currentValueLabel: {
			Text(value.formatted(.percent))
		}
		.fontWeight(.bold)
		.padding()
		.previewContext(WidgetPreviewContext(family: .systemMedium))
	}
}
