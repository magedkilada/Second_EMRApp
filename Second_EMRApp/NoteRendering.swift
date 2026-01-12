import Foundation

private func renderNoteWithHeader(
    note: RecordNote,
    patient: Patient,
    physicianName: String,
    clinic: String
) -> String {

    let dfDate = DateFormatter()
    dfDate.dateStyle = .short
    dfDate.timeStyle = .none

    let dfDateTime = DateFormatter()
    dfDateTime.dateStyle = .short
    dfDateTime.timeStyle = .short

    let patientName = patient.nameEnglish.isEmpty ? "—" : patient.nameEnglish
    let mrn = patient.mrn.isEmpty ? "—" : patient.mrn
    let dob = dfDate.string(from: patient.dob)
    let sex = "—"   // Patient model currently has no gender field
    let phone = patient.phone.isEmpty ? "—" : patient.phone

    let created = dfDateTime.string(from: note.createdAt)
    let updated = dfDateTime.string(from: note.updatedAt)

    let header = """
    Patient: \(patientName)
    MRN: \(mrn) | DOB: \(dob) | Sex: \(sex) | Phone: \(phone)
    Clinic: \(clinic)
    Physician: \(physicianName)
    Note Created: \(created)
    Note Updated: \(updated)
    ------------------------------------------------------------

    """

    return header + note.body
}
