import SwiftUI

struct PhysiciansManagerView: View {

    @EnvironmentObject private var physicians: PhysiciansStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingPhysician: Physician? = nil
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(physicians.physicians) { physician in
                    Button {
                        editingPhysician = physician
                        showEditor = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(physician.name.isEmpty ? "Unnamed Physician" : physician.name)
                                .font(.headline)

                            if !physician.specialty.isEmpty {
                                Text(physician.specialty)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !physician.clinic.isEmpty {
                                Text(physician.clinic)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let id = physicians.physicians[index].id
                        physicians.deletePhysician(id: id)
                    }
                }
            }
            .navigationTitle("Manage Physicians")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingPhysician = physicians.addPhysician()
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                if let physician = editingPhysician {
                    PhysicianEditorView(physician: physician)
                }
            }
        }
    }
}

struct PhysicianEditorView: View {

    @EnvironmentObject private var physicians: PhysiciansStore
    @Environment(\.dismiss) private var dismiss

    @State private var editablePhysician: Physician

    init(physician: Physician) {
        _editablePhysician = State(initialValue: physician)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $editablePhysician.name)
                    TextField("Specialty", text: $editablePhysician.specialty)
                    TextField("Clinic", text: $editablePhysician.clinic)
                }

                Section("Professional") {
                    TextField("License Number", text: $editablePhysician.licenseNumber)
                }

                Section("Contact") {
                    TextField("Phone", text: $editablePhysician.contactPhone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $editablePhysician.contactEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Edit Physician")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        physicians.updatePhysician(editablePhysician)
                        dismiss()
                    }
                }
            }
        }
    }
}
