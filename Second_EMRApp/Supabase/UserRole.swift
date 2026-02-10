//
//  UserRole.swift
//  Second_EMRApp
//
//  Role-based access control for the EMR app
//

import Foundation

public enum UserRole: String, Codable, CaseIterable {
    case physician
    case nurse
    case secretary

    public var displayName: String {
        switch self {
        case .physician: return "Physician"
        case .nurse: return "Nurse"
        case .secretary: return "Secretary"
        }
    }

    // MARK: - Permission Checks

    /// Physicians have full access
    public var canManageNotes: Bool {
        self == .physician
    }

    public var canManageAttachments: Bool {
        self == .physician
    }

    /// Physicians and Nurses can manage vitals
    public var canManageVitals: Bool {
        self == .physician || self == .nurse
    }

    /// Physicians and Secretaries can manage appointments
    public var canManageAppointments: Bool {
        self == .physician || self == .secretary
    }

    /// Physicians can manage physician records
    public var canManagePhysicians: Bool {
        self == .physician
    }

    /// Physicians can manage references
    public var canManageReferences: Bool {
        self == .physician
    }

    /// All roles can create/edit patients (demographics)
    public var canEditPatientDemographics: Bool {
        true
    }

    /// Staff can only delete patients if no records exist
    /// Physicians can always delete
    public func canDeletePatient(hasRecords: Bool) -> Bool {
        if self == .physician { return true }
        return !hasRecords
    }
}

// MARK: - User Profile

public struct UserProfile: Codable, Identifiable {
    public let id: UUID
    public let email: String
    public var fullName: String?
    public var role: UserRole
    public let createdAt: Date?
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case role
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(id: UUID, email: String, fullName: String? = nil, role: UserRole = .secretary) {
        self.id = id
        self.email = email
        self.fullName = fullName
        self.role = role
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public var displayName: String {
        if let name = fullName, !name.isEmpty {
            return name
        }
        return email.components(separatedBy: "@").first ?? email
    }
}
