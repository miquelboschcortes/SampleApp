/*
See LICENSE folder for this sample’s licensing information.

Abstract:
 An individual row representing an accessory.
*/

import SwiftUI
import Energy

struct AccessoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var accessory: Accessory

    var body: some View {
        HStack {
            Image(systemName: accessory.icon ?? "powerplug")
                .imageScale(.large)
                .colorScheme(accessory.on ? .light : colorScheme)
                .dynamicTypeSize(.xxxLarge)
                .padding(.all)
                .frame(width: 64, height: 64)
                .background(accessory.on ? AnyShapeStyle(.yellow.gradient) : AnyShapeStyle(.quaternary), in: Circle())
            VStack(alignment: .leading) {
                Toggle(accessory.name ?? "", isOn: $accessory.on)
                Text(Measurement(value: accessory.powerWhenOn, unit: UnitPower.watts).formatted(.measurement(width: .wide)))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }

        .onReceive(accessory.publisher(for: \.on)) { _ in
            try? viewContext.save()
        }
    }
}

// swiftlint: disable force_try
struct AccessoryView_Previews: PreviewProvider {
    static var previews: some View {
        AccessoryView(
            accessory: try! PersistenceController.preview.container.viewContext
                .fetch(Accessory.fetchRequest())
                .first!
        )
        .previewLayout(.sizeThatFits)
    }
}
