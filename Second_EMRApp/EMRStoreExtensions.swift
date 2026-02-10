import Foundation

// MARK: - EMRStore Helper Methods Extension
// Add these methods to EMRStore for DemographicsView and other views

extension EMRStore {
    
    // MARK: - Patient Methods
    
    /// Update an existing patient
    func updatePatient(_ patient: Patient) {
        if let idx = patients.firstIndex(where: { $0.id == patient.id }) {
            patients[idx] = patient
            lastModified = Date()
            savePatients()

            // Cloud sync
            SyncManager.shared.queuePatientChange(patient, operation: .update)
        }
    }
    
    /// Hard delete a patient (use with caution!)
    func deletePatient(_ patientID: UUID) {
        // Remove patient
        patients.removeAll { $0.id == patientID }
        
        // Remove all notes for this patient
        notes.removeAll { $0.patientID == patientID }
        
        // Remove all vitals for this patient
        vitals.removeAll { $0.patientID == patientID }
        
        // Remove all attachments for this patient
        attachments.removeAll { $0.patientID == patientID }
        
        // Update selection if needed
        if selectedPatientID == patientID {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }
        
        lastModified = Date()
        forcePersistAll()
    }
    
    // MARK: - Record Methods
    
    /// Get all non-deleted records for a patient
    func recordsForPatient(_ patientID: UUID) -> [RecordNote] {
        return notes
            .filter { $0.patientID == patientID && !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Get a specific record by ID
    func getRecord(_ recordID: UUID) -> RecordNote? {
        return notes.first { $0.id == recordID }
    }
    
    // MARK: - Attachment Methods
    /// Get all non-deleted attachments for a specific patient
    func attachmentsForPatient(_ patientID: UUID) -> [Attachment] {
        attachments
            .filter { $0.patientID == patientID && !$0.isDeleted }
            .sorted { (lhs: Attachment, rhs: Attachment) in
                // ✅ Use the property that actually exists now:
                lhs.createdAt > rhs.createdAt
            }
    }
}


