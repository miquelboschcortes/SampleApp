/*
See LICENSE folder for this sample’s licensing information.

Abstract:
 A list of available accessories in the home.
*/

import SwiftUI
import Energy

struct AccessoryListView: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.name, order: .forward)],
        animation: .default)
    private var accessories: FetchedResults<Accessory>

    var body: some View {
        NavigationStack {
            List {
                ForEach(accessories) { accessory in
                    NavigationLink {
                        AccessoryDetailView(accessory: accessory)
                    } label: {
                        AccessoryView(accessory: accessory)
                    }
                }
            }
            .navigationBarTitle("Accessories")
        }
    }
}

struct AccessoryListView_Previews: PreviewProvider {
    static var previews: some View {
        AccessoryListView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .environmentObject(HomeEmulator.preview)
    }
}
