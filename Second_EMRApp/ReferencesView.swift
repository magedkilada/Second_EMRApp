import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit

struct ReferencesView: View {
    @StateObject private var refStore = ReferencesStore()
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var searchText = ""
    @State private var selectedItemID: UUID?
    @State private var showAddSheet = false
    @State private var editingItem: ReferenceItem?
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    private var isCompact: Bool { hSize == .compact }

    private var filteredItems: [ReferenceItem] {
        let items = refStore.filteredItems
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }

        // Split query into words — ALL words must appear somewhere in the item
        let words = q.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return items }

        return items.filter { item in
            let searchable = "\(item.title) \(item.body) \(item.category.rawValue)".lowercased()
            return words.allSatisfy { searchable.contains($0) }
        }
    }

    var body: some View {
        Group {
            if isCompact {
                compactBody
            } else {
                HStack(spacing: 0) {
                    referenceList
                        .frame(minWidth: 280, maxWidth: 360)
                    Divider()
                    referenceDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ReferenceEditSheet(
                item: ReferenceItem(title: "", category: .misc, body: ""),
                onSave: { item in
                    refStore.items.insert(item, at: 0)
                    refStore.update(item) // persist
                    selectedItemID = item.id
                    showAddSheet = false
                },
                onCancel: { showAddSheet = false }
            )
        }
        .sheet(item: $editingItem) { item in
            ReferenceEditSheet(
                item: item,
                onSave: { updated in
                    refStore.update(updated)
                    editingItem = nil
                },
                onCancel: { editingItem = nil }
            )
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .plainText, .rtf, .rtfd, .text, .image, .jpeg, .png],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, newItems in
            handlePhotoImport(newItems)
        }
    }

    // MARK: - Compact (iPhone) Body

    private var compactBody: some View {
        NavigationStack {
            referenceList
                .navigationTitle("References")
                .inlineNavigationTitle()
                .navigationDestination(item: $selectedItemID) { itemID in
                    if let item = refStore.items.first(where: { $0.id == itemID }) {
                        compactDetailView(item)
                    }
                }
        }
    }

    private func compactDetailView(_ item: ReferenceItem) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.title2).bold()
                    Text(item.category.rawValue)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    var toggled = item
                    toggled.isFavorite.toggle()
                    refStore.update(toggled)
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(item.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)

                Button { editingItem = item } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3).foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                Button {
                    refStore.delete(item.id)
                    selectedItemID = nil
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.title3).foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            if let fileURL = item.fileURL,
               !["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(fileURL.pathExtension.lowercased()) {
                // PDF fills entire remaining space
                PDFKitView(url: fileURL)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let fileURL = item.fileURL {
                            filePreview(url: fileURL)
                        }

                        Text(item.body)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding()
                }
            }
        }
        .background(Color.secondarySystemGroupedBg)
        .navigationTitle(item.title)
        .inlineNavigationTitle()
    }

    // MARK: - Left Panel

    private var referenceList: some View {
        VStack(spacing: 12) {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(nil, title: "All")
                    ForEach(ReferenceItem.Category.allCases, id: \.self) { cat in
                        categoryChip(cat, title: cat.rawValue)
                    }
                }
                .padding(.horizontal, 12)
            }

            // Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search references...", text: $searchText)
                    .mobileAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.tertiarySystemGroupedBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)

            // Add button with import options
            Menu {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Type Manually", systemImage: "square.and.pencil")
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import from Files", systemImage: "doc.fill")
                }
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Import from Photos", systemImage: "photo.fill")
                }
            } label: {
                Label("Add Reference", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 12)

            // List
            List(filteredItems, selection: $selectedItemID) { item in
                Button {
                    selectedItemID = item.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.title).font(.headline).lineLimit(1)
                            Spacer()
                            if item.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption).foregroundStyle(.yellow)
                            }
                        }
                        Text(item.category.rawValue)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(item.body)
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    selectedItemID == item.id
                        ? Color.blue.opacity(0.15)
                        : Color.clear
                )
            }
            .listStyle(.plain)
        }
        .padding(.top, 8)
        .background(Color.systemGroupedBg)
    }

    private func categoryChip(_ cat: ReferenceItem.Category?, title: String) -> some View {
        let isSelected = refStore.selectedCategory == cat
        return Button {
            refStore.selectedCategory = cat
        } label: {
            Text(title)
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.secondarySystemGroupedBg)
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Panel

    private var referenceDetail: some View {
        Group {
            if let id = selectedItemID,
               let item = refStore.items.first(where: { $0.id == id }) {
                VStack(spacing: 0) {
                    // Header bar — always visible
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.title2).bold()
                            Text(item.category.rawValue)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()

                        Button {
                            var toggled = item
                            toggled.isFavorite.toggle()
                            refStore.update(toggled)
                        } label: {
                            Image(systemName: item.isFavorite ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundStyle(item.isFavorite ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)

                        Button { editingItem = item } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3).foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)

                        Button {
                            refStore.delete(item.id)
                            selectedItemID = nil
                        } label: {
                            Image(systemName: "trash.circle.fill")
                                .font(.title3).foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()

                    Divider()

                    // Content — PDF fills the panel; text uses ScrollView
                    if let fileURL = item.fileURL,
                       !["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(fileURL.pathExtension.lowercased()) {
                        // PDF: fill remaining space (PDFView has its own scroll)
                        PDFKitView(url: fileURL)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if let fileURL = item.fileURL {
                                    filePreview(url: fileURL)
                                }

                                Text(item.body)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                            .padding()
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Select a reference")
                        .font(.headline).foregroundStyle(.secondary)
                    Text("Store clinical scales, protocols, medication lists, and more.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.secondarySystemGroupedBg)
    }

    // MARK: - File Preview

    @ViewBuilder
    private func filePreview(url: URL) -> some View {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) {
            #if os(iOS)
            if let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            #elseif os(macOS)
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            #endif
        } else {
            // PDF or other document — render inline using PDFKit
            PDFKitView(url: url)
                .frame(minHeight: 500, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }

    // MARK: - Import Handlers

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }

        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let refFilesDir = docsDir.appendingPathComponent("ReferenceFiles")
        try? FileManager.default.createDirectory(at: refFilesDir, withIntermediateDirectories: true)

        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let filename = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.lowercased()

            if ext == "pdf" {
                // PDF — save to disk + extract text for search
                guard let data = try? Data(contentsOf: url) else { continue }
                let destURL = refFilesDir.appendingPathComponent(url.lastPathComponent)
                try? data.write(to: destURL, options: .atomic)

                // Extract text from PDF for searchability
                var bodyText = ""
                // Try from saved file first, fall back to in-memory data
                let pdfDoc = PDFDocument(url: destURL) ?? PDFDocument(data: data)
                if let pdfDoc = pdfDoc {
                    var pages: [String] = []
                    for i in 0..<pdfDoc.pageCount {
                        if let page = pdfDoc.page(at: i), let text = page.string,
                           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            pages.append(text)
                        }
                    }
                    bodyText = pages.joined(separator: "\n\n")
                }
                if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                    bodyText = "Imported PDF (\(sizeStr)) — scanned document (no extractable text)"
                }

                // Store RELATIVE path (survives iOS sandbox container UUID changes)
                let relativePath = "ReferenceFiles/\(url.lastPathComponent)"
                let item = ReferenceItem(
                    title: filename,
                    category: .misc,
                    body: bodyText,
                    filePath: relativePath
                )
                refStore.items.insert(item, at: 0)
                refStore.update(item)
                selectedItemID = item.id
            } else if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                // Plain text file
                let item = ReferenceItem(title: filename, category: .misc, body: text)
                refStore.items.insert(item, at: 0)
                refStore.update(item)
                selectedItemID = item.id
            } else if let data = try? Data(contentsOf: url) {
                // Other binary file — save to disk
                let destURL = refFilesDir.appendingPathComponent(url.lastPathComponent)
                try? data.write(to: destURL, options: .atomic)

                let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                // Store RELATIVE path
                let relativePath = "ReferenceFiles/\(url.lastPathComponent)"
                let item = ReferenceItem(
                    title: filename,
                    category: .misc,
                    body: "Imported \(ext.uppercased()) file (\(sizeStr))",
                    filePath: relativePath
                )
                refStore.items.insert(item, at: 0)
                refStore.update(item)
                selectedItemID = item.id
            }
        }
    }

    private func handlePhotoImport(_ items: [PhotosPickerItem]) {
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                if case .success(let data) = result, let data = data {
                    DispatchQueue.main.async {
                        let filename = "Photo_\(Date().formatted(date: .numeric, time: .shortened))"
                            .replacingOccurrences(of: "/", with: "-")
                            .replacingOccurrences(of: ":", with: "-")
                            .replacingOccurrences(of: " ", with: "_")

                        // Save to Documents for later viewing
                        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let photoDir = docsDir.appendingPathComponent("ReferencePhotos")
                        try? FileManager.default.createDirectory(at: photoDir, withIntermediateDirectories: true)
                        let photoFilename = filename + ".jpg"
                        let fileURL = photoDir.appendingPathComponent(photoFilename)
                        try? data.write(to: fileURL)

                        // Store RELATIVE path
                        let ref = ReferenceItem(
                            title: filename,
                            category: .misc,
                            body: "Imported photo",
                            filePath: "ReferencePhotos/\(photoFilename)"
                        )
                        refStore.items.insert(ref, at: 0)
                        refStore.update(ref)
                        selectedItemID = ref.id
                    }
                }
            }
        }
        selectedPhotoItems = []
    }
}

// MARK: - Edit / Add Sheet

private struct ReferenceEditSheet: View {
    @State var item: ReferenceItem
    let onSave: (ReferenceItem) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Reference title", text: $item.title)
                }

                Section("Category") {
                    Picker("Category", selection: $item.category) {
                        ForEach(ReferenceItem.Category.allCases, id: \.self) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Content") {
                    TextEditor(text: $item.body)
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle(item.title.isEmpty ? "New Reference" : "Edit Reference")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(item) }
                        .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
