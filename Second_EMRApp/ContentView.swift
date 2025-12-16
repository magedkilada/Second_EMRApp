import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {

    // MARK: - Stores
    @StateObject private var store = EMRStore()
    @StateObject private var physicians = PhysiciansStore()

    // MARK: - UI State
    @State private var selectedPatientID: UUID?
    @State private var tab: WorkspaceTab = .demographics

    // MARK: - Import State
    @State private var importingCategory: Attachment.Category = .medicalReport
    @State private var showFileImporter: Bool = false

    @State private var showPhotoPicker: Bool = false
    @State private var pickedPhoto: PhotosPickerItem? = nil

    enum WorkspaceTab: String, CaseIterable, Identifiable {
        case demographics = "Demographics"
        case records = "Medical Records"
        case referencesAI = "References + AI"
        var id: String { rawValue }
    }

    private var visiblePatients: [Patient] {
        store.patients.filter { !$0.isDeleted }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .onAppear {
            if selectedPatientID == nil {
                selectedPatientID = visiblePatients.first?.id
            }
        }
        // FILE IMPORTER (category already chosen from menu)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            guard let patientID = selectedPatientID else { return }

            if case .success(let urls) = result, let url = urls.first {
                _ = store.importFile(
                    patientID: patientID,
                    category: importingCategory,
                    sourceURL: url
                )
            }
        }
        // PHOTO PICKER (category already chosen from menu)
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickedPhoto,
            matching: .images
        )
        .onChange(of: pickedPhoto) { _, newItem in
            guard let patientID = selectedPatientID else { return }
            guard let newItem else { return }

            Task {
                await importPickedPhoto(newItem, patientID: patientID, category: importingCategory)
                await MainActor.run { pickedPhoto = nil }
            }
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        List(visiblePatients, selection: $selectedPatientID) { patient in
            VStack(alignment: .leading, spacing: 4) {
                Text(patient.nameEnglish.isEmpty ? "Unnamed (English)" : patient.nameEnglish)
                    .font(.headline)

                if !patient.mrn.isEmpty {
                    Text("MRN: \(patient.mrn)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tag(patient.id)
        }
        .navigationTitle("Patients")
        .toolbar {
            Button {
                var p = Patient()
                p.createdAt = Date()
                p.updatedAt = Date()
                store.patients.insert(p, at: 0)
                selectedPatientID = p.id
            } label: {
                Label("Add Patient", systemImage: "plus")
            }
        }
        .toolbar {
            Menu {
                // ✅ Import FILE submenu (shows categories)
                Menu("Import File…") {
                    ForEach(Attachment.Category.allCases) { cat in
                        Button(cat.rawValue) {
                            importingCategory = cat
                            showFileImporter = true
                        }
                    }
                }

                // ✅ Import PHOTO submenu (shows categories)
                Menu("Import Photo…") {
                    ForEach(Attachment.Category.allCases) { cat in
                        Button(cat.rawValue) {
                            importingCategory = cat
                            showPhotoPicker = true
                        }
                    }
                }
            } label: {
                Label("Import", systemImage: "paperclip")
            }
            .disabled(selectedPatientID == nil)
        }
    }

    // MARK: - Detail
    private var detail: some View {
        Group {
            if let id = selectedPatientID,
               let index = store.patients.firstIndex(where: { $0.id == id }) {

                let patientBinding = Binding<Patient>(
                    get: { store.patients[index] },
                    set: { store.patients[index] = $0 }
                )

                VStack(spacing: 8) {

                    Picker("", selection: $tab) {
                        ForEach(WorkspaceTab.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    switch tab {
                    case .demographics:
                        PatientDemographicsView(
                            patient: patientBinding,
                            onSave: {
                                store.patients[index].updatedAt = Date()
                            },
                            onRequestDelete: { }
                        )
                    case .referencesAI:
                        ReferencesAIHubView(
                            store: store,
                            selectedPatientID: selectedPatientID
                        )

                    case .records:
                        RecordsWorkspaceView(
                            store: store,
                            patientID: id,
                            patient: store.patients[index]   // VALUE, not Binding
                        )
                    }
                }
                .navigationTitle(tab.rawValue)
                .navigationBarTitleDisplayMode(.inline)

            } else {
                ContentUnavailableView(
                    "No Patient Selected",
                    systemImage: "person.text.rectangle",
                    description: Text("Add or select a patient")
                )
            }
        }
    }

    // MARK: - Photo Import (Category-aware)
    @MainActor
    private func importPickedPhoto(_ item: PhotosPickerItem, patientID: UUID, category: Attachment.Category) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }

            // Convert to JPEG for predictable preview/QuickLook behavior
            let jpegData: Data
            if let image = UIImage(data: data),
               let jpg = image.jpegData(compressionQuality: 0.9) {
                jpegData = jpg
            } else {
                // fallback: save original bytes (rare)
                jpegData = data
            }

            let fileName = "\(UUID().uuidString).jpg"
            let dir = attachmentsDir(for: patientID)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let dstURL = dir.appendingPathComponent(fileName)
            try jpegData.write(to: dstURL, options: .atomic)

            let att = Attachment(
                patientID: patientID,
                category: category,
                originalFileName: fileName,
                storedFileName: fileName
            )
            store.attachments.append(att)
        } catch {
            // Optional: you can surface an alert using store.lastErrorMessage if you have it.
            // store.lastErrorMessage = error.localizedDescription
        }
    }

    private func attachmentsDir(for patientID: UUID) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(patientID.uuidString, isDirectory: true)
    }
}
