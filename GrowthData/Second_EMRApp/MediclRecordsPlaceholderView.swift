import SwiftUI

struct MedicalRecordsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Medical Records",
            systemImage: "doc.text",
            description: Text("Medical records workspace will be added next.")
        )
    }
}

#Preview {
    MedicalRecordsPlaceholderView()
}
