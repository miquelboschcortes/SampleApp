/*
See LICENSE folder for this sample’s licensing information.

Abstract:
 A detail view for an accessory.
*/

import SwiftUI
import Energy

struct AccessoryDetailView: View {
    @ObservedObject var accessory: Accessory

    @Environment(\.managedObjectContext) private var viewContext

    @Environment(\.isSwiftPreview) private var isSwiftPreview

    var body: some View {
        VStack {
            Image(systemName: accessory.icon ?? "powerplug")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
            Text(accessory.name ?? "Unknown accessory")
                .font(.headline)
            Spacer()
                .frame(height: 40.0)
            HomeEnergyChart(for: accessory)
                .frame(height: 150.0)
                .onReceive(
                    NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
                    .receive(on: DispatchQueue.main)
                ) { _ in
                    if !isSwiftPreview {
                        accessory.objectWillChange.send()
                    }
                }
            Spacer()
                .frame(height: 40.0)
            Button("Switch \(accessory.on ? "off" : "on") in 5 sec.") {
                do {
                    try accessory.switchPower(on: !accessory.on, delay: 5.0)
                    try viewContext.save()
                } catch {
                    let nsError = error as NSError
                    fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
                }
            }
                .buttonStyle(.bordered)
            Button("Switch \(accessory.on ? "off" : "on") then \(accessory.on ? "on" : "off") in 10 sec.") {
                do {
                    try accessory.switchPower(on: !accessory.on, delay: 10.0, for: 10.0)
                    try viewContext.save()
                } catch {
                    let nsError = error as NSError
                    fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
                }
            }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

// swiftlint: disable force_try
struct AccessoryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        AccessoryDetailView(
            accessory: try! PersistenceController.preview.container.viewContext
                .fetch(Accessory.fetchRequest())
                .first!
        )
        .previewLayout(.sizeThatFits)
        .environment(\.isSwiftPreview, true)
    }
}
