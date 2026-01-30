//
//  ContentView.swift
//  Second_EMRApp
//

import SwiftUI

struct ContentView: View {

    // MARK: - Environment
    @EnvironmentObject private var store: EMRStore
    @EnvironmentObject private var physicians: PhysiciansStore
    @Environment(\.horizontalSizeClass) private var hSize

    // MARK: - UI State
    @State private var patientSearchText: String = ""
    @State private var activeTab: WorkspaceTab = .demographics
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum WorkspaceTab: String, CaseIterable {
        case demographics = "Demographics"
        case medicalRecords = "Medical Records"
        case references = "References"

        var icon: String {
            switch self {
            case .demographics: return "person.text.rectangle"
            case .medicalRecords: return "doc.text.fill"
            case .references: return "books.vertical.fill"
            }
        }
    }

    // MARK: - Derived
    private var selectedPatient: Patient? {
        guard let id = store.selectedPatientID else { return nil }
        return store.patients.first(where: { $0.id == id && !$0.isDeleted })
    }

    private var isCompact: Bool {
        hSize == .compact
    }

    // MARK: - Body
    var body: some View {
        if isCompact {
            compactLayout
        } else {
            regularLayout
        }
    }

    // MARK: - Regular (iPad) Layout
    private var regularLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LeftSidebarView(searchText: $patientSearchText)
                .environmentObject(store)
                .environmentObject(physicians)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 400)
        } detail: {
            if let patient = selectedPatient {
                VStack(spacing: 0) {
                    topTabBar
                    Divider()
                    tabContent(patient: patient)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .onChange(of: store.selectedPatientID) { _, _ in
                    activeTab = .demographics
                }
            } else {
                emptyPatientState
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Compact (iPhone) Layout
    private var compactLayout: some View {
        NavigationStack {
            LeftSidebarView(searchText: $patientSearchText)
                .environmentObject(store)
                .environmentObject(physicians)
                .navigationDestination(item: $store.selectedPatientID) { _ in
                    if let patient = selectedPatient {
                        VStack(spacing: 0) {
                            compactTabBar
                            Divider()
                            tabContent(patient: patient)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .navigationTitle(patient.nameEnglish)
                        .inlineNavigationTitle()
                    }
                }
        }
    }

    // MARK: - Shared tab content
    @ViewBuilder
    private func tabContent(patient: Patient) -> some View {
        switch activeTab {
        case .demographics:
            PatientSummaryDashboard(patient: patient)
                .environmentObject(store)
                .environmentObject(physicians)
        case .medicalRecords:
            RecordsWorkspaceView(patient: patient)
                .environmentObject(store)
                .environmentObject(physicians)
        case .references:
            ReferencesView()
        }
    }

    // MARK: - Top Tab Bar (iPad)
    private var topTabBar: some View {
        HStack(spacing: 8) {
            ForEach(WorkspaceTab.allCases, id: \.self) { tab in
                tabButton(tab: tab)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.systemGroupedBg)
    }

    // MARK: - Compact Tab Bar (iPhone) — icon-only to save space
    private var compactTabBar: some View {
        HStack(spacing: 4) {
            ForEach(WorkspaceTab.allCases, id: \.self) { tab in
                Button {
                    activeTab = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18))
                        Text(tab.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(activeTab == tab ? Color.blue : Color.secondarySystemGroupedBg)
                    .foregroundStyle(activeTab == tab ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.systemGroupedBg)
    }

    private func tabButton(tab: WorkspaceTab) -> some View {
        Button {
            activeTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                Text(tab.rawValue).fontWeight(.semibold)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(activeTab == tab ? Color.blue : Color.secondarySystemGroupedBg)
            .foregroundStyle(activeTab == tab ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State
    private var emptyPatientState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Select a patient")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Choose a patient from the left sidebar to begin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
