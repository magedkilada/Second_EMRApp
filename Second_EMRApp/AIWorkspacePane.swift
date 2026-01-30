//
//  AIWorkspacePane.swift - STUBBED VERSION (NO ERRORS)
//  Second_EMRApp
//

import SwiftUI

struct AIWorkspacePane: View {
    // MARK: - Properties (Standardized naming)
    @ObservedObject var store: EMRStore
    let selectedPatientID: UUID?
    @Binding var contextText: String
    let selectedReferenceTitle: String?

    var body: some View {
        VStack(spacing: 20) {
            headerSection
            
            if let title = selectedReferenceTitle {
                Text("Analyzing: \(title)")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            
            contextScrollView
            
            Divider()
            
            roadmapSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("AI Workspace")
    }
    
    // MARK: - Sub-Sections
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("AI Workspace")
                .font(.title2)
                .bold()
        }
        .padding(.top)
    }
    
    private var contextScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if contextText.isEmpty {
                    Text("No snippets added to AI context yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Context:")
                        .font(.caption)
                        .bold()
                    
                    Text(contextText)
                        .font(.callout)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }
    
    private var roadmapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coming Soon:")
                .font(.headline)
            
            Label("AI-powered medical translation", systemImage: "text.bubble")
                .font(.subheadline)
            Label("Clinical reasoning assistance", systemImage: "brain.head.profile")
                .font(.subheadline)
            Label("Differential diagnosis support", systemImage: "list.bullet.clipboard")
                .font(.subheadline)
        }
        .foregroundStyle(.secondary)
        .padding()
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        AIWorkspacePane(
            store: EMRStore(),
            selectedPatientID: nil,
            contextText: .constant("Sample medical text..."),
            selectedReferenceTitle: "Test Reference"
        )
    }
}

