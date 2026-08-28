import SwiftUI
import UniformTypeIdentifiers
import PubMergeCore

struct ImportView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.adaptiveLayout) private var layout
    @State private var isImporterPresented = false
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.isCompactWidth ? 16 : 20) {
                WorkflowHeader(step: .importCopies)
                header
                dropZone
                if session.backups.isEmpty {
                    ContentUnavailableView("empty_import_title", systemImage: "externaldrive.badge.plus", description: Text("empty_import_body"))
                } else {
                    backupList
                    summary
                }
                if let error = session.errorMessage {
                    Banner(kind: .error, text: error)
                }
                ForEach(session.warningMessages, id: \.self) { warning in
                    Banner(kind: .warning, text: warning)
                }
            }
            .readablePage()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("step_import")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporterPresented = true
                } label: {
                    if layout.isCompactWidth {
                        Image(systemName: "plus")
                    } else {
                        Label("import_copies", systemImage: "plus")
                    }
                }
                .accessibilityLabel(Text("import_copies"))
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.jwlibrary, .data, .zip],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await session.importFiles(at: urls) }
            }
        }
        .onDrop(of: [.fileURL, .item], isTargeted: $isDropTargeted) { providers in
            Task { await handleDrop(providers) }
            return true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("import_headline")
                .adaptiveHeadline()
            Text("import_subtitle")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.largeTitle)
            Text("drop_title")
                .font(.headline)
            Text("drop_body")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("import_copies") {
                isImporterPresented = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(layout.isCompactWidth ? 18 : 28)
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary.opacity(0.4))
        }
    }

    private var backupList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("imported_copies")
                .font(.title3.weight(.semibold))
            ForEach(backupsWithRole, id: \.backup.id) { item in
                BackupRow(backup: item.backup, role: item.role) {
                    session.removeBackup(item.backup.id)
                }
            }
        }
    }

    private var backupsWithRole: [(backup: ImportedBackup, role: String)] {
        session.backups.enumerated().map { index, backup in
            (backup, index == 0 ? LanguageController.shared.localized("role_primary") : LanguageController.shared.localized("role_secondary"))
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.statMinimum), spacing: 12)], spacing: 12) {
                StatCard(title: "stat_notes", value: session.backups.reduce(0) { $0 + $1.statistics.notes }, symbol: "note.text")
                StatCard(title: "stat_marks", value: session.backups.reduce(0) { $0 + $1.statistics.userMarks }, symbol: "pencil.tip")
                StatCard(title: "stat_bookmarks", value: session.backups.reduce(0) { $0 + $1.statistics.bookmarks }, symbol: "bookmark")
                StatCard(title: "stat_tags", value: session.backups.reduce(0) { $0 + $1.statistics.tags }, symbol: "tag")
            }
            MergeScopeEditor(scope: Bindable(session).mergeScope)
            Button {
                session.step = .compare
                Task { await session.compareAndMerge() }
            } label: {
                Label("compare_and_merge", systemImage: "arrow.triangle.merge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(layout.prominentControlSize)
            .disabled(!session.canCompare || session.isWorking)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadURL(from: provider) {
                urls.append(url)
            }
        }
        if !urls.isEmpty {
            await session.importFiles(at: urls)
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let nsurl = item as? NSURL {
                    continuation.resume(returning: nsurl as URL)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private struct BackupRow: View {
    let backup: ImportedBackup
    let role: String
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(backup.displayName)
                        .font(.headline)
                        .lineLimit(2)
                    Text("\(role) · \(backup.originalFileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("remove_backup"))
            }
            Text("\(backup.deviceName) · \(backup.creationDate) · \(ByteCountFormatter.string(fromByteCount: backup.fileSize, countStyle: .file))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(backup.statistics.notes) \(LanguageController.shared.localized("stat_notes")) · \(backup.statistics.userMarks) \(LanguageController.shared.localized("stat_marks")) · \(backup.statistics.tags) \(LanguageController.shared.localized("stat_tags"))")
                .font(.caption)
            if !backup.canMerge {
                Text("schema_blocked")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
