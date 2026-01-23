import Foundation
import SwiftUI

struct PhysiciansManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PhysiciansStore

    @State private var showAdd = false
    @State private var editing: Physician? = nil
    @State private var confirmDelete: Physician? = nil
    @State private var showCantDeleteLast = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.physicians) { p in
                    HStack(spacing: 12) {

                        // ✅ Selection tap area (only this selects)
                        Button {
                            store.selectedPhysicianID = p.id
                            store.save()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.name).font(.headline)
                                Text("\(p.specialty) • \(p.clinic)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if store.selectedPhysicianID == p.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }

                        // ✅ Edit
                        Button {
                            editing = p
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)

                        // ✅ Delete
                        Button(role: .destructive) {
                            requestDelete(p)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { requestDelete(p) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { editing = p } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
            .navigationTitle("Physicians")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddPhysicianView { newPhysician in
                    store.add(newPhysician)
                }
            }
            .sheet(item: $editing) { p in
                EditPhysicianView(physician: p) { updated in
                    store.update(updated)
                }
            }
            .alert("Delete physician?", isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let p = confirmDelete { store.delete(id: p.id) }
                    confirmDelete = nil
                }
                Button("Cancel", role: .cancel) { confirmDelete = nil }
            } message: {
                Text("This will remove the physician from your list.")
            }
            .alert("Cannot delete", isPresented: $showCantDeleteLast) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You must keep at least one physician in the list.")
            }
        }
    }

    private func requestDelete(_ p: Physician) {
        if store.physicians.count <= 1 {
            showCantDeleteLast = true
        } else {
            confirmDelete = p
        }
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
