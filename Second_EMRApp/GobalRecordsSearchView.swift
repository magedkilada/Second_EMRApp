import SwiftUI

struct GlobalRecordsSearchView: View {

    @EnvironmentObject private var store: EMRStore
    @Environment(\.dismiss) private var dismiss

    @Binding var query: String

    private var q: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    // MARK: - Matched Notes (NO isDeleted, NO sorting assumptions)

    private var matchedNotes: [RecordNote] {
        guard !q.isEmpty else { return [] }

        return store.notes.filter { n in
            let haystack = [
                n.displayTitle,
                n.type.rawValue,
                n.body
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(q)
        }
    }

    // MARK: - Matched Attachments (NO isDeleted, NO sorting assumptions)

    private var matchedAttachments: [Attachment] {
        guard !q.isEmpty else { return [] }

        return store.attachments.filter { a in
            let haystack = [
                a.category.rawValue,
                a.originalFileName,
                a.storedFileName
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(q)
        }
    }

    // MARK: - UI

    var body: some View {
        NavigationStack {
            List {

                if q.isEmpty {
                    ContentUnavailableView(
                        "Search all records",
                        systemImage: "magnifyingglass"
                    )
                    .foregroundStyle(.secondary)

                } else {

                    if !matchedNotes.isEmpty {
                        Section("Notes (\(matchedNotes.count))") {
                            ForEach(matchedNotes) { n in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(n.displayTitle)
                                        .font(.headline)

                                    Text(n.type.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    if !matchedAttachments.isEmpty {
                        Section("Attachments (\(matchedAttachments.count))") {
                            ForEach(matchedAttachments) { a in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(
                                        a.originalFileName.isEmpty
                                        ? a.storedFileName
                                        : a.originalFileName
                                    )
                                    .font(.headline)

                                    Text(a.category.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    if matchedNotes.isEmpty && matchedAttachments.isEmpty {
                        ContentUnavailableView(
                            "No matches",
                            systemImage: "doc.text.magnifyingglass"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search all notes & attachments")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Global Search")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
