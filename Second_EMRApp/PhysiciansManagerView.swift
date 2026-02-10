import SwiftUI

struct PhysiciansManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PhysiciansStore

    enum Destination: Hashable {
        case add
        case edit(Physician)
    }

    @State private var path: [Destination] = []
    @State private var confirmDelete: Physician? = nil
    @State private var showCantDeleteLast = false

    var body: some View {
        NavigationStack(path: $path) {
            physiciansList
                .navigationTitle("Physicians")
                .toolbar { toolbarContent }
                .navigationDestination(for: Destination.self) { dest in
                    switch dest {
                    case .add:
                        AddPhysicianForm { newPhysician in
                            store.add(newPhysician)
                            path.removeLast()
                        }
                    case .edit(let physician):
                        EditPhysicianForm(physician: physician) { updated in
                            store.update(updated)
                            path.removeLast()
                        }
                    }
                }
        }
        .alert("Delete physician?", isPresented: deleteAlert) {
            deleteAlertButtons
        } message: {
            deleteAlertMessage
        }
        .alert("Cannot delete", isPresented: $showCantDeleteLast) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You must keep at least one physician in the list.")
        }
    }

    // MARK: - Sub-Views

    private var physiciansList: some View {
        List {
            ForEach(store.activePhysicians) { physician in
                PhysicianRow(
                    physician: physician,
                    isSelected: store.selectedPhysicianID == physician.id,
                    onSelect: {
                        store.selectedPhysicianID = physician.id
                        store.save()
                    },
                    onEdit: { path.append(.edit(physician)) },
                    onDelete: { requestDelete(physician) }
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button { path.append(.add) } label: {
                Image(systemName: "plus")
            }
        }
    }

    private var deleteAlert: Binding<Bool> {
        Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )
    }

    @ViewBuilder
    private var deleteAlertButtons: some View {
        Button("Delete", role: .destructive) {
            if let p = confirmDelete { store.softDelete(p.id) }
            confirmDelete = nil
        }
        Button("Cancel", role: .cancel) {
            confirmDelete = nil
        }
    }

    private var deleteAlertMessage: some View {
        Text("This will remove the physician from your list.")
    }

    // MARK: - Helpers

    private func requestDelete(_ physician: Physician) {
        if store.activePhysicians.count <= 1 {
            showCantDeleteLast = true
        } else {
            confirmDelete = physician
        }
    }
}

// MARK: - Supporting Row View
struct PhysicianRow: View {
    let physician: Physician
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button { onSelect() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(physician.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !physician.specialty.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "stethoscope")
                                .font(.caption2)
                            Text(physician.specialty)
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if !physician.clinic.isEmpty {
                            Label(physician.clinic, systemImage: "building.2")
                                .font(.caption)
                        }

                        if !physician.phone.isEmpty {
                            Label(physician.phone, systemImage: "phone")
                                .font(.caption)
                        }

                        if !physician.email.isEmpty {
                            Label(physician.email, systemImage: "envelope")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button { onEdit() } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }

            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add Physician Form (pushed via navigation)
struct AddPhysicianForm: View {
    @State private var name: String = ""
    @State private var specialty: String = ""
    @State private var clinic: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""

    let onAdd: (Physician) -> Void

    var body: some View {
        Form {
            Section("Required") {
                TextField("Name *", text: $name)
            }

            Section("Professional Details") {
                TextField("Specialty", text: $specialty)
                TextField("Clinic/Hospital", text: $clinic)
            }

            Section("Contact Information") {
                TextField("Phone", text: $phone)
                    .mobileKeyboard(.phonePad)

                TextField("Email", text: $email)
                    .mobileKeyboard(.emailAddress)
                    .mobileAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("New Physician")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let physician = Physician(
                        name: name,
                        specialty: specialty,
                        clinic: clinic,
                        phone: phone,
                        email: email
                    )
                    onAdd(physician)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

// MARK: - Edit Physician Form (pushed via navigation)
struct EditPhysicianForm: View {
    @State private var id: UUID
    @State private var name: String
    @State private var specialty: String
    @State private var clinic: String
    @State private var phone: String
    @State private var email: String

    let onSave: (Physician) -> Void

    init(physician: Physician, onSave: @escaping (Physician) -> Void) {
        _id = State(initialValue: physician.id)
        _name = State(initialValue: physician.name)
        _specialty = State(initialValue: physician.specialty)
        _clinic = State(initialValue: physician.clinic)
        _phone = State(initialValue: physician.phone)
        _email = State(initialValue: physician.email)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Required") {
                TextField("Name *", text: $name)
            }

            Section("Professional Details") {
                TextField("Specialty", text: $specialty)
                TextField("Clinic/Hospital", text: $clinic)
            }

            Section("Contact Information") {
                TextField("Phone", text: $phone)
                    .mobileKeyboard(.phonePad)

                TextField("Email", text: $email)
                    .mobileKeyboard(.emailAddress)
                    .mobileAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("Edit Physician")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let physician = Physician(
                        id: id,
                        name: name,
                        specialty: specialty,
                        clinic: clinic,
                        phone: phone,
                        email: email
                    )
                    onSave(physician)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
