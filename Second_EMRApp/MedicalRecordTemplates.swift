import Foundation

struct MedicalRecordTemplates {

    static func getTemplate(for type: MedicalRecordType) -> String {
        switch type {
        case .historyAndPhysical:
            return historyAndPhysicalTemplate
        case .soapNote:
            return soapNoteTemplate
        case .operativeNote:
            return operativeNoteTemplate
        case .dischargeSummary:
            return dischargeSummaryTemplate
        case .eegReport:
            return eegReportTemplate
        case .prescription:
            return prescriptionTemplate
        }
    }

    // ✅ REMOVED manual vital signs - Smart Vitals will insert automatically
    private static let historyAndPhysicalTemplate = """
    HISTORY & PHYSICAL (H&P)

    CHIEF COMPLAINT:

    HISTORY OF PRESENT ILLNESS:

    PAST MEDICAL HISTORY:

    PAST SURGICAL HISTORY:

    MEDICATIONS:

    ALLERGIES:

    SOCIAL HISTORY:

    FAMILY HISTORY:

    REVIEW OF SYSTEMS:

    PHYSICAL EXAMINATION:

    General:
    HEENT:
    Neck:
    Cardiovascular:
    Respiratory:
    Abdomen:
    Extremities:
    Neurologic:
    Mental Status:
    Cranial Nerves:
    Motor:
    Sensory:
    Reflexes:
    Coordination:
    Gait:

    ASSESSMENT:

    PLAN:
    """

    // ✅ REMOVED manual vital signs - Smart Vitals will insert automatically
    private static let soapNoteTemplate = """
    SOAP / PROGRESS NOTE

    SUBJECTIVE:

    OBJECTIVE:

    ASSESSMENT:

    PLAN:
    """

    private static let operativeNoteTemplate = """
    OPERATIVE NOTE

    DATE OF OPERATION:

    PREOPERATIVE DIAGNOSIS:

    POSTOPERATIVE DIAGNOSIS:

    PROCEDURE(S) PERFORMED:

    SURGEON:

    ASSISTANT(S):

    ANESTHESIA:

    ANESTHESIOLOGIST:

    ESTIMATED BLOOD LOSS:

    COMPLICATIONS:

    SPECIMENS:

    INDICATIONS:

    DESCRIPTION OF PROCEDURE:

    CLOSURE:

    CONDITION:

    DISPOSITION:
    """

    private static let dischargeSummaryTemplate = """
    DISCHARGE SUMMARY

    ADMISSION DATE:

    DISCHARGE DATE:

    ADMITTING DIAGNOSIS:

    DISCHARGE DIAGNOSIS:

    PROCEDURES PERFORMED:

    BRIEF HOSPITAL COURSE:

    CONDITION ON DISCHARGE:

    DISCHARGE MEDICATIONS:

    DISCHARGE INSTRUCTIONS:

    FOLLOW-UP:
    """

    private static let eegReportTemplate = """
    EEG REPORT

    DATE OF STUDY:

    INDICATION:

    MEDICATIONS:

    TECHNICAL DATA:
    Recording Duration:
    Electrode Placement:
    Activation Procedures:

    DESCRIPTION:

    Background Activity:

    Sleep:

    Activation:

    Abnormalities:

    IMPRESSION:

    CLINICAL CORRELATION:
    """

    private static let prescriptionTemplate = """
    PRESCRIPTION

    DATE:

    PATIENT INFORMATION:
    Name:
    DOB:
    MRN:

    MEDICATION:
    Drug Name:
    Strength:
    Form:
    Quantity:
    Directions:
    Refills:

    INDICATION:

    PRECAUTIONS:

    PRESCRIBER:
    Name:
    Signature:
    License #:
    Date:
    """
}

