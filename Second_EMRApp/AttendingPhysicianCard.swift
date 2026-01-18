import SwiftUI

struct AttendingPhysicianCard: View {
    @EnvironmentObject private var physicians: PhysiciansStore
    let onManage: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Attending Physician")
                        .font(.headline)
                    Spacer()
                    Button("Manage", action: onManage)
                        .font(.caption)
                }

                Picker("Attending Physician", selection: $physicians.selectedPhysicianID) {
                    Text("—").tag(UUID?.none)
                    ForEach(physicians.physicians) { p in
                        Text(p.name).tag(UUID?.some(p.id))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}
