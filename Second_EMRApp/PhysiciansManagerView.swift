import SwiftUI

// MARK: - Manager

struct PhysiciansManagerView: View {
    @EnvironmentObject private var physicians: PhysiciansStore
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd = false
    @State private var editTarget: Physician? = nil

    @State private var pendingDelete: Physician? = nil
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                if physicians.physicians.isEmpty {
                    ContentUnavailableView("No physicians",
                                           systemImage: "person.crop.circle.badge.questionmark")
                } else {
                    Section("Physicians") {
                        ForEach(physicians.physicians) { p in
                            PhysicianRow(
                                physician: p,
                                isSelected: physicians.selectedPhysicianID == p.id,
                                onSelect: {
                                    physicians.selectedPhysicianID = p.id
                                    physicians.save()
                                },
                                onEdit: { editTarget = p },
                                onDelete: {
                                    pendingDelete = p
                                    confirmDelete = true
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Manage Physicians")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }

            // ✅ Delete confirmation
            .alert("Delete physician?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete", role: .destructive) {
                    guard let p = pendingDelete else { return }
                    physicians.delete(id: p.id)
                    pendingDelete = nil
                }
            } message: {
                Text("This cannot be undone.")
            }

            // ✅ Add
            .sheet(isPresented: $showAdd) {
                AddPhysicianView { newPhysician in
                    physicians.add(newPhysician)
                }
            }

            // ✅ Edit
            .sheet(item: $editTarget) { p in
                EditPhysicianView(physician: p) { updated in
                    physicians.update(updated)
                }
            }
        }
    }
}

// MARK: - Row (keeps compiler happy)

private struct PhysicianRow: View {
    let physician: Physician
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(physician.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed" : physician.name)
                    .font(.headline)

                let line = detailLine
                if !line.isEmpty {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }

            Menu {
                Button("Select") { onSelect() }
                Button("Edit") { onEdit() }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private var detailLine: String {
        let spec = physician.specialty.trimmingCharacters(in: .whitespacesAndNewlines)
        let clinic = physician.clinic.trimmingCharacters(in: .whitespacesAndNewlines)

        if !spec.isEmpty && !clinic.isEmpty { return "\(spec) • \(clinic)" }
        if !spec.isEmpty { return spec }
        if !clinic.isEmpty { return clinic }
        return ""
    }
}

// --- Editors (same as before) ---

private struct EditPhysicianView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var id: UUID
    @State private var name: String
    @State private var specialty: String
    @State private var clinic: String

    let onSave: (Physician) -> Void

    init(physician: Physician, onSave: @escaping (Physician) -> Void) {
        _id = State(initialValue: physician.id)
        _name = State(initialValue: physician.name)
        _specialty = State(initialValue: physician.specialty)
        _clinic = State(initialValue: physician.clinic)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Specialty", text: $specialty)
                TextField("Clinic", text: $clinic)
            }
            .navigationTitle("Edit Physician")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(Physician(id: id, name: name, specialty: specialty, clinic: clinic))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct AddPhysicianView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var specialty: String = ""
    @State private var clinic: String = ""

    let onAdd: (Physician) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Specialty", text: $specialty)
                TextField("Clinic", text: $clinic)
            }
            .navigationTitle("New Physician")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onAdd(Physician(name: name, specialty: specialty, clinic: clinic))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
