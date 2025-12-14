import Foundation
import SwiftUI
import Combine

@MainActor
public final class EMRStore: ObservableObject {

    @Published public var patients: [Patient] = []
    @Published public var selectedPatientID: UUID? = nil

    private let saveURL: URL

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.saveURL = docs.appendingPathComponent("patients.json")
        load()

        if selectedPatientID == nil {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }
    }

    // MARK: - CRUD

    public func addNewPatient() {
        var p = Patient()
        // Keep fields empty so TextFields show placeholders
        p.nameEnglish = ""
        p.nameArabic = ""
        p.phone = ""
        p.mrn = ""
        p.nationalID = ""
        p.passport = ""
        p.email = ""
        p.dob = Date() // user can change; DOB picker prevents future
        // If your Patient has sex, keep a default:
        // p.sex = .male

        patients.insert(p, at: 0)
        selectedPatientID = p.id
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
            set: { self.patients[idx] = $0 }
        )
    }

    // MARK: - Validation rules

    public func canSave(_ p: Patient) -> Bool {
        let nameOK = !p.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let phoneOK = !p.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let dobOK = p.dob <= Date()
        return nameOK && phoneOK && dobOK
    }

    public func normalizeForSave(_ p: inout Patient) {
        // Enforce limits at save-time (and we will ALSO enforce on typing in the view)
        p.nameEnglish = p.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        p.nameArabic = p.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func savePatient(id: UUID) -> Bool {
        guard let idx = patients.firstIndex(where: { $0.id == id }) else { return false }
        var p = patients[idx]
        normalizeForSave(&p)

        guard canSave(p) else { return false }

        patients[idx] = p
        save()
        return true
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        do {
            patients = try JSONDecoder().decode([Patient].self, from: data)
        } catch {
            patients = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(patients)
            try data.write(to: saveURL, options: [.atomic])
        } catch {
            // You can print(error) if you want, but keep silent in production
        }
    }
}


