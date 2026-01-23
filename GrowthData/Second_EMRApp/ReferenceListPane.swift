import SwiftUI

struct ReferenceListPane: View {

    @ObservedObject var refStore: ReferencesStore
    @Binding var selectedReferenceID: UUID?

    /// Add selected reference text into the AI "context" box
    let onAddToAIContext: (String) -> Void

    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"

    // Dynamic category chips
    private var categories: [String] {
        let cats = Set(
            refStore.items
                .map { $0.category.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return ["All", "★ Favorites"] + cats.sorted()
    }

    private var filtered: [ReferenceItem] {
        var items = refStore.items

        // Category filter
        if selectedCategory == "★ Favorites" {
            items = items.filter { $0.isFavorite }
        } else if selectedCategory != "All" {
            items = items.filter { $0.category == selectedCategory }
        }

        // Smart search (title + category + body)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let lower = q.lowercased()
            items = items.filter {
                $0.title.lowercased().contains(lower) ||
                $0.category.lowercased().contains(lower) ||
                $0.body.lowercased().contains(lower)
            }
        }

        return items
    }

    private func resetFilters() {
        searchText = ""
        selectedCategory = "All"
    }

    var body: some View {
        VStack(spacing: 0) {

            // TOP BAR (title + actions)
            HStack {
                Text("References")
                    .font(.headline)

                Spacer()

                Button {
                    resetFilters()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset filters")

                Button {
                    let new = refStore.addBlank()
                    selectedReferenceID = new.id
                } label: {
                    Image(systemName: "plus")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // ✅ Always-visible search box
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search references…", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            // Category chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        Button {
                            selectedCategory = cat
                        } label: {
                            Text(cat)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(
                                        selectedCategory == cat
                                        ? Color.secondary.opacity(0.25)
                                        : Color.secondary.opacity(0.12)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            List(selection: $selectedReferenceID) {
                ForEach(filtered) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                                .lineLimit(1)

                            if item.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(item.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(item.id)
                    .contextMenu {
                        Button("Add to AI Context") {
                            onAddToAIContext(item.body)
                        }

                        Button(item.isFavorite ? "Unfavorite" : "Favorite") {
                            refStore.toggleFavorite(item)
                        }

                        Divider()

                        Button(role: .destructive) {
                            refStore.delete(item)
                            if selectedReferenceID == item.id { selectedReferenceID = nil }
                        } label: {
                            Text("Delete")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}
