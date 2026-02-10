import SwiftUI

struct PhysiciansManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PhysiciansStore

    enum Mode: Equatable {
        case list
        case add
        case edit(Physician)
    }

    @State private var mode: Mode = .list
    @State private var confirmDelete: Physician? = nil

    // Edit/Add form fields
    @State private var formName = ""
    @State private var formSpecialty = ""
    @State private var formClinic = ""
    @State private var formPhone = ""
    @State private var formEmail = ""
    @State private var formID: UUID = UUID()

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .list:
                    physiciansList
                case .add:
                    physicianForm(title: "New Physician", buttonLabel: "Add") {
                        let physician = Physician(
                            name: formName,
                            specialty: formSpecialty,
                            clinic: formClinic,
                            phone: formPhone,
                            email: formEmail
                        )
                        store.add(physician)
                        mode = .list
                    }
                case .edit:
                    physicianForm(title: "Edit Physician", buttonLabel: "Save") {
                        let physician = Physician(
                            id: formID,
                            name: formName,
                            specialty: formSpecialty,
                            clinic: formClinic,
                            phone: formPhone,
                            email: formEmail
                        )
                        store.update(physician)
                        mode = .list
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mode == .list ? "Done" : "Back") {
                        if mode == .list {
                            dismiss()
                        } else {
                            mode = .list
                        }
                    }
                }

                if mode == .list {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { startAdd() } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .alert("Delete physician?", isPresented: deleteAlert) {
            deleteAlertButtons
        } message: {
            Text("This will remove the physician from your list.")
        }
    }

    // MARK: - List View

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
                    onEdit: { startEdit(physician) },
                    onDelete: { confirmDelete = physician }
                )
            }
        }
        .navigationTitle("Physicians")
    }

    // MARK: - Form View

    private func physicianForm(title: String, buttonLabel: String, onSubmit: @escaping () -> Void) -> some View {
        Form {
            Section("Required") {
                TextField("Name *", text: $formName)
            }

            Section("Professional Details") {
                TextField("Specialty", text: $formSpecialty)
                TextField("Clinic/Hospital", text: $formClinic)
            }

            Section("Contact Information") {
                TextField("Phone", text: $formPhone)
                    .mobileKeyboard(.phonePad)

                TextField("Email", text: $formEmail)
                    .mobileKeyboard(.emailAddress)
                    .mobileAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button(buttonLabel) { onSubmit() }
                    .disabled(formName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(title)
    }

    // MARK: - Helpers

    private func startAdd() {
        formName = ""
        formSpecialty = ""
        formClinic = ""
        formPhone = ""
        formEmail = ""
        formID = UUID()
        mode = .add
    }

    private func startEdit(_ physician: Physician) {
        formName = physician.name
        formSpecialty = physician.specialty
        formClinic = physician.clinic
        formPhone = physician.phone
        formEmail = physician.email
        formID = physician.id
        mode = .edit(physician)
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
