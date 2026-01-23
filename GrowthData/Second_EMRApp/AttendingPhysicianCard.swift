import SwiftUI

struct AttendingPhysicianCard: View {
    @EnvironmentObject private var physicians: PhysiciansStore
    let onManage: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Attending Physician")
                        .font(.headline)

                    if let p = physicians.selectedPhysician {
                        Text(p.name).font(.title3).bold()
                        Text(p.specialty).foregroundStyle(.secondary)
                        if !p.clinic.isEmpty { Text(p.clinic).foregroundStyle(.secondary) }
                    } else {
                        Text("None selected").foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onManage) {
                    Label("Manage", systemImage: "pencil")
                }
            }
        }
    }
}
