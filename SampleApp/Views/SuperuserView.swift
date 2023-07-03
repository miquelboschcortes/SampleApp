/*
See LICENSE folder for this sample’s licensing information.

Abstract:
 A view allowing the user to control characteristics of the fictional home setup.
*/

import SwiftUI
import Energy

struct SuperuserView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var homeEmulator: HomeEmulator
    @EnvironmentObject private var homeGenerator: HomeGenerator

    var body: some View {
        VStack {
            Button("Add Appliances") {
                PersistenceController.addMoreAppliances(to: viewContext)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
                .frame(height: 40.0)

            HStack {
                Text("Generator output:")
                Slider(
                    value: $homeGenerator.powerOutput,
                    in: HomeGenerator.powerOutputRange,
                    step: 100
                )
                Text(Measurement(
                    value: homeGenerator.powerOutput.magnitude,
                    unit: UnitPower.watts
                ).formatted(.measurement(width: .abbreviated, usage: .asProvided)))
                    .monospacedDigit()
            }
        }
        .padding()
    }
}

struct SuperuserView_Previews: PreviewProvider {
    static var previews: some View {
        SuperuserView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .environmentObject(HomeEmulator.preview)
            .environmentObject(HomeEmulator.preview.generator)
    }
}
