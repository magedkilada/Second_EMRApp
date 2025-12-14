import SwiftUI

struct RecordsWorkspaceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("References")
                            .font(.headline)

                        Text("• GCS\n• Hunt/Hess Grade\n• Fisher Grade\n• Developmental chart\n• Growth chart")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        Text("Next: we’ll convert these into tappable calculators/tables.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ContentUnavailableView(
                    "Medical Records",
                    systemImage: "doc.text",
                    description: Text("Medical records workspace will be added next (notes, AI, import, translate, smart search).")
                )
                .padding(.top, 10)
            }
            .padding()
        }
        .navigationTitle("Medical Records")
    }
}
