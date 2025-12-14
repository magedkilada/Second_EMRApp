import SwiftUI

enum NeuroReference: String, CaseIterable, Identifiable {
    case gcs = "Glasgow Coma Scale (GCS)"
    case huntHess = "Hunt & Hess Grade (SAH)"
    case fisher = "Fisher Grade (SAH)"
    case wfns = "WFNS Grade (SAH)"
    case developmental = "Developmental Chart"
    case growth = "Growth Chart"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .gcs: return "brain.head.profile"
        case .huntHess, .fisher, .wfns: return "waveform.path.ecg"
        case .developmental: return "figure.child"
        case .growth: return "chart.line.uptrend.xyaxis"
        }
    }
}

struct ReferencesInlineCard: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("References")
                    .font(.headline)
                Spacer()
                Button {
                    onOpen()
                } label: {
                    Label("Open", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }

            Text("GCS, Hunt/Hess, Fisher, Growth & Development, and more.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct ReferencesCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var selected: NeuroReference? = nil

    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(filtered) { item in
                    Label(item.rawValue, systemImage: item.symbol)
                        .tag(item as NeuroReference?)
                }
            }
            .navigationTitle("References")
            .searchable(text: $query, prompt: "Search references")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        } detail: {
            if let item = selected {
                ReferenceDetailView(item: item)
            } else {
                ContentUnavailableView(
                    "Select a reference",
                    systemImage: "book",
                    description: Text("Choose an item from the list.")
                )
            }
        }
    }

    private var filtered: [NeuroReference] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return NeuroReference.allCases }
        return NeuroReference.allCases.filter { $0.rawValue.lowercased().contains(q) }
    }
}

struct ReferenceDetailView: View {
    let item: NeuroReference

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.rawValue)
                    .font(.title2)
                    .bold()

                // Placeholders (we will replace with proper tables next)
                GroupBox {
                    Text("Reference content will be added here (tables + scoring helpers).")
                        .foregroundStyle(.secondary)
                }

                if item == .gcs {
                    GroupBox("Quick GCS Reminder") {
                        Text("Eye (1–4), Verbal (1–5), Motor (1–6). Total 3–15.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }
}
