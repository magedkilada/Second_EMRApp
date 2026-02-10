//
//  AuthView.swift
//  Second_EMRApp
//
//  Login and Sign Up screen for Supabase authentication
//

import SwiftUI

struct AuthView: View {
    @StateObject private var supabase = SupabaseManager.shared

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var fullName = ""
    @State private var selectedRole: UserRole = .secretary

    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Logo / Header
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 60))
                        .foregroundStyle(.purple)

                    Text("Neuro EMR")
                        .font(.largeTitle.bold())

                    Text(isSignUp ? "Create your account" : "Sign in to continue")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                // Check if Supabase is configured
                if !SupabaseConfig.isConfigured {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)

                        Text("Supabase Not Configured")
                            .font(.headline)

                        Text("To enable cloud sync:\n1. Add Supabase Swift SDK to project\n2. Set your API key in SupabaseConfig.swift")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Divider().padding(.vertical)

                        Text("The app works fully offline. Cloud sync is optional.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    // Form
                    VStack(spacing: 16) {
                        if isSignUp {
                            TextField("Full Name", text: $fullName)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.words)
                                #endif
                        }

                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            #endif

                        SecureField("Password", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)

                        if isSignUp {
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textContentType(.newPassword)

                            Picker("Role", selection: $selectedRole) {
                                ForEach(UserRole.allCases, id: \.self) { role in
                                    Text(role.displayName).tag(role)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 32)

                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            Task { await authenticate() }
                        } label: {
                            if supabase.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!isFormValid || supabase.isLoading)

                        Button {
                            withAnimation {
                                isSignUp.toggle()
                                clearForm()
                            }
                        } label: {
                            Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()

                // Offline indicator
                if !SyncManager.shared.isOnline {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("No internet connection")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.bottom)
                }
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .alert("Authentication Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var isFormValid: Bool {
        let emailValid = email.contains("@") && email.contains(".")
        let passwordValid = password.count >= 6

        if isSignUp {
            return emailValid && passwordValid && password == confirmPassword && !fullName.isEmpty
        } else {
            return emailValid && passwordValid
        }
    }

    private func authenticate() async {
        do {
            if isSignUp {
                try await supabase.signUp(
                    email: email,
                    password: password,
                    fullName: fullName,
                    role: selectedRole
                )
            } else {
                try await supabase.signIn(email: email, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
        fullName = ""
        selectedRole = .secretary
    }
}

// MARK: - Role Info Sheet

struct RoleInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    roleRow(
                        role: .physician,
                        icon: "stethoscope",
                        color: .purple,
                        permissions: [
                            "Full access to all patient data",
                            "Create and edit clinical notes",
                            "Upload and manage attachments",
                            "Record vitals",
                            "Manage appointments",
                            "Manage physician records",
                            "Manage reference library"
                        ]
                    )
                }

                Section {
                    roleRow(
                        role: .nurse,
                        icon: "cross.case.fill",
                        color: .blue,
                        permissions: [
                            "View all patient data",
                            "Create/edit patient demographics",
                            "Record and manage vitals",
                            "View clinical notes (read-only)",
                            "View attachments (read-only)",
                            "View appointments (read-only)"
                        ]
                    )
                }

                Section {
                    roleRow(
                        role: .secretary,
                        icon: "calendar.badge.clock",
                        color: .green,
                        permissions: [
                            "View all patient data",
                            "Create/edit patient demographics",
                            "Manage appointments",
                            "View clinical notes (read-only)",
                            "View attachments (read-only)",
                            "View vitals (read-only)"
                        ]
                    )
                }
            }
            .navigationTitle("User Roles")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func roleRow(role: UserRole, icon: String, color: Color, permissions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(role.displayName)
                    .font(.headline)
            }

            ForEach(permissions, id: \.self) { permission in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(permission)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    AuthView()
}
