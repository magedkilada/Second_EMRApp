import Foundation
import SwiftUI

@MainActor
public final class EMRStore: ObservableObject {

    @Published public var patients: [Patient] = []
    @Published public var selectedPatientID: UUID? = nil

    public init() {
        load()
        if selectedPatientID == nil {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }
    }

    // MARK: - CRUD

    public func addNewPatient() {
        var p = Patient()
        p.nameEnglish = "New Patient"
        patients.insert(p, at: 0)
        selectedPatientID = p.id
        save()
    }

    public func update(_ patient: Patient) {
        guard let idx = patients.firstIndex(where: { $0.id == patient.id }) else { return }
        patients[idx] = patient
        save()
    }

    public func deletePatient(id: UUID) {
        guard let idx = patients.firstIndex(where: { $0.id == id }) else { return }
        patients.remove(at: idx)

        if selectedPatientID == id {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }
        save()
    }

    public func patientBinding(for id: UUID) -> Binding<Patient>? {
        guard let idx = patients.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.patients[idx] },
            set: { newValue in
                self.patients[idx] = newValue
                self.save()
            }
        )
    }

    // MARK: - Persistence (JSON)

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("patients.json")
    }

    public func save() {
        do {
            let data = try JSONEncoder().encode(patients)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("SAVE ERROR:", error)
        }
    }

    public func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            patients = try JSONDecoder().decode([Patient].self, from: data)
        } catch {
            // first run is normal (file doesn't exist)
            patients = []
        }
    }
}
