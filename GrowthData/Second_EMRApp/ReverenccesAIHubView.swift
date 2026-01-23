import SwiftUI

struct ReferencesAIHubView: View {

    @ObservedObject var store: EMRStore
    let selectedPatientID: UUID?

    @StateObject private var refStore = ReferencesStore()

    @State private var selectedReferenceID: UUID?

    // AI state
    @State private var aiContextText: String = ""
    @State private var aiPrompt: String = ""
    @State private var aiOutput: String = ""

    private var selectedReference: ReferenceItem? {
        guard let id = selectedReferenceID else { return nil }
        return refStore.items.first(where: { $0.id == id })
    }

    var body: some View {
        NavigationSplitView {

            // LEFT: References
            ReferenceListPane(
                refStore: refStore,
                selectedReferenceID: $selectedReferenceID,
                onAddToAIContext: { snippet in
                    if !aiContextText.isEmpty {
                        aiContextText += "\n\n"
                    }
                    aiContextText += snippet
                }
            )

        } detail: {

            // RIGHT: AI Workspace
            AIWorkspacePane(
                store: store,
                selectedPatientID: selectedPatientID,
                contextText: $aiContextText,
                selectedReferenceTitle: selectedReference?.title
            )
        }
    }
}
