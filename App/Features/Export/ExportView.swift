import SwiftUI

struct ExportView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.adaptiveLayout) private var layout
#if os(iOS)
    @State private var shareItem: URL?
#endif

    var body: some View {
        if session.plan == nil {
            emptyExport
        } else {
            exportContent
        }
    }

    private var emptyExport: some View {
        VStack(alignment: .leading, spacing: layout.isCompactWidth ? 12 : 16) {
            WorkflowHeader(step: .export)
                .padding(.horizontal, layout.pagePadding)
            ContentUnavailableView("empty_compare_title", systemImage: "exclamationmark.triangle", description: Text("empty_compare_body"))
                .frame(maxHeight: .infinity)
        }
        .padding(.top, layout.isCompactHeight ? 8 : 16)
        .navigationTitle("step_export")
    }

    private var exportContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.isCompactWidth ? 14 : 18) {
                WorkflowHeader(step: .export)
                Text("export_headline")
                    .adaptiveHeadline()

                if layout.isRegularWidth {
                    exportActionButton
                }

                TextField("export_name", text: Bindable(session).exportName)
                    .textFieldStyle(.roundedBorder)

                Text("restore_warning")
                    .padding(12)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("restore_backup_hint")
                    .foregroundStyle(.secondary)

                if let plan = session.plan {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.statMinimum), spacing: 12)], spacing: 12) {
                        StatCard(title: "stat_notes", value: plan.merged.notes.count, symbol: "note.text")
                        StatCard(title: "stat_marks", value: plan.merged.userMarks.count, symbol: "pencil.tip")
                        StatCard(title: "stat_bookmarks", value: plan.merged.bookmarks.count, symbol: "bookmark")
                        StatCard(title: "stat_tags", value: plan.merged.tags.count, symbol: "tag")
                    }
                    MergeScopeSummary(scope: plan.scope)
                    if !plan.scope.videos {
                        Banner(kind: .info, text: LanguageController.shared.localized("warning_videos_excluded"))
                    }
                    if session.needsRescope {
                        Banner(kind: .warning, text: LanguageController.shared.localized("merge_scope_needs_reapply"))
                    }
                }

                if let export = session.lastExport {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("export_ready", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.headline)
                        Text(export.fileURL.lastPathComponent)
                            .lineLimit(2)
                        Text("SHA-256: \(export.hash)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
#if os(macOS)
                        Button("reveal_in_finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([export.fileURL])
                        }
#else
                        Button("share_file") {
                            shareItem = export.fileURL
                        }
#endif
                    }
                    .padding(14)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                restoreInstructions

                if let error = session.errorMessage {
                    Banner(kind: .error, text: error)
                }
            }
            .readablePage()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("step_export")
        .safeAreaInset(edge: .bottom) {
            exportActionButton
                .padding(.horizontal, layout.pagePadding)
                .padding(.vertical, layout.isCompactHeight ? 8 : 12)
                .background(.bar)
        }
#if os(iOS)
        .sheet(item: Binding(
            get: { shareItem.map(IdentifiedURL.init) },
            set: { shareItem = $0?.url }
        )) { item in
            ActivityView(url: item.url)
        }
#endif
    }

    private var exportActionButton: some View {
        Button {
            Task { await session.exportMerged() }
        } label: {
            Label("export_button", systemImage: "square.and.arrow.up")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, layout.isCompactWidth ? 4 : 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(layout.prominentControlSize)
        .disabled(session.plan == nil || session.isWorking || session.needsRescope)
    }

    private var restoreInstructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("restore_title")
                .font(.title3.weight(.semibold))
            labeled("restore_ios", "restore_ios_body")
            labeled("restore_ipad", "restore_ipad_body")
            labeled("restore_mac", "restore_mac_body")
        }
    }

    private func labeled(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#if os(iOS)
private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.popoverPresentationController?.permittedArrowDirections = []
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        if let popover = uiViewController.popoverPresentationController {
            popover.sourceView = uiViewController.view
            popover.sourceRect = CGRect(
                x: uiViewController.view.bounds.midX,
                y: uiViewController.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
    }
}
#endif
