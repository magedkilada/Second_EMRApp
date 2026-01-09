import SwiftUI

struct AttendingPhysicianCard: View {
    @EnvironmentObject private var physicians: PhysiciansStore
    let onManage: () -> Void

    @State private var showPicker = false

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(physicians.selectedPhysicianName ?? "—")
                        .font(.headline)

                    if !physicianDetailLine.isEmpty {
                        Text(physicianDetailLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Tap to choose")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    onManage()
                } label: {
                    Text("Manage")
                }
                .buttonStyle(.bordered)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showPicker = true
            }
        }
        .confirmationDialog(
            "Choose Physician",
            isPresented: $showPicker,
            titleVisibility: .visible
        ) {
            if physicians.physicians.isEmpty {
                Button("No physicians saved", role: .cancel) { }
            } else {
                ForEach(physicians.physicians) { p in
                    Button(pickerLabel(for: p)) {
                        physicians.selectedPhysicianID = p.id
                        physicians.save()
                    }
                }

                Button("Clear Selection", role: .destructive) {
                    physicians.selectedPhysicianID = nil
                    physicians.save()
                }

                Button("Cancel", role: .cancel) { }
            }
        } message: {
            Text("Select the treating physician for this session.")
        }
    }

    private var physicianDetailLine: String {
        guard let p = physicians.selectedPhysician else { return "" }
        let spec = p.specialty.trimmingCharacters(in: .whitespacesAndNewlines)
        let clinic = p.clinic.trimmingCharacters(in: .whitespacesAndNewlines)

        if !spec.isEmpty && !clinic.isEmpty { return "\(spec) • \(clinic)" }
        if !spec.isEmpty { return spec }
        if !clinic.isEmpty { return clinic }
        return ""
    }

    private func pickerLabel(for p: Physician) -> String {
        let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let spec = p.specialty.trimmingCharacters(in: .whitespacesAndNewlines)
        let clinic = p.clinic.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = [name.isEmpty ? "Unnamed" : name]
        if !spec.isEmpty { parts.append(spec) }
        if !clinic.isEmpty { parts.append(clinic) }
        return parts.joined(separator: " • ")
    }
}
