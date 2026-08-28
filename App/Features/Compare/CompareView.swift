import SwiftUI
import PubMergeCore

struct CompareView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.locale) private var locale
    @Environment(\.adaptiveLayout) private var layout
    @State private var editingNote: EditableNote?
    @State private var pendingDelete: ComparableItem?

    var body: some View {
        VStack(spacing: 0) {
            WorkflowHeader(step: .compare)
                .padding(.horizontal, layout.pagePadding)
                .padding(.top, layout.isCompactHeight ? 8 : 12)
            filters
            if session.filteredItems.isEmpty {
                ContentUnavailableView("empty_compare_title", systemImage: "rectangle.split.2x1", description: Text("empty_compare_body"))
                    .frame(maxHeight: .infinity)
            } else {
                List(session.filteredItems) { item in
                    ComparableRow(item: item) {
                        beginEditing(item)
                    } onDelete: {
                        pendingDelete = item
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if item.noteGuid != nil {
                            Button("note_delete", role: .destructive) {
                                pendingDelete = item
                            }
                            Button("note_edit") {
                                beginEditing(item)
                            }
                            .tint(.indigo)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("step_compare")
        .toolbar {
            if session.unresolvedConflicts > 0 {
                ToolbarItem(placement: .primaryAction) {
                    Button("continue_conflicts") {
                        session.step = .conflicts
                    }
                    .disabled(session.plan == nil)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if session.canExportMerged {
                exportCallToAction
                    .padding(.horizontal, layout.pagePadding)
                    .padding(.vertical, layout.isCompactHeight ? 8 : 12)
                    .background(.bar)
            }
        }
        .sheet(item: $editingNote) { note in
            NavigationStack {
                NoteEditorSheet(note: note) { title, content in
                    session.updateNote(guid: note.id, sourceIndex: note.sourceIndex, title: title, content: content)
                }
            }
#if os(iOS)
            .presentationDragIndicator(.visible)
            .presentationDetents(layout.isCompactWidth ? [.medium, .large] : [.large])
#endif
#if os(macOS)
            .frame(minWidth: 480, minHeight: 420)
#endif
        }
        .confirmationDialog("note_delete_title", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("note_delete", role: .destructive) {
                if let guid = pendingDelete?.noteGuid {
                    session.deleteNoteFromMergedList(guid: guid)
                }
                pendingDelete = nil
            }
            Button("note_cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("note_delete_body")
        }
        .task {
            if session.plan == nil && session.canCompare {
                await session.compareAndMerge()
            }
        }
    }

    private var exportCallToAction: some View {
        Button {
            session.goToExport()
        } label: {
            Label("compare_export_cta", systemImage: "square.and.arrow.up")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, layout.isCompactWidth ? 4 : 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(layout.prominentControlSize)
        .accessibilityHint(Text("compare_export_hint"))
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("search_placeholder", text: Bindable(session).searchText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)

            if !session.backups.isEmpty {
                devicePicker
            }

            AdaptiveStack(spacing: 8) {
                Picker("filter_kind", selection: Bindable(session).kindFilter) {
                    Text("filter_all").tag(Optional<ItemKind>.none)
                    ForEach(ItemKind.allCases) { kind in
                        Text(kind.label).tag(Optional(kind))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Picker("filter_status", selection: Bindable(session).statusFilter) {
                    Text("filter_all").tag(Optional<ConflictStatus>.none)
                    Text("status_conflict").tag(Optional(ConflictStatus.conflict))
                    Text("status_unique").tag(Optional(ConflictStatus.unique))
                    Text("status_resolved").tag(Optional(ConflictStatus.resolved))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            AdaptiveStack(spacing: 4, compactAlignment: .leading, regularAlignment: .firstTextBaseline) {
                Text(String(format: String(localized: "compare_results_count", locale: locale), session.filteredItems.count))
                    .font(.subheadline.weight(.semibold))
                if !layout.prefersStackedControls {
                    Spacer()
                }
                Text("compare_edit_hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("compare_details_title") {
                VStack(alignment: .leading, spacing: 12) {
                    if let plan = session.plan {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.statMinimum), spacing: 10)], spacing: 10) {
                            StatCard(title: "stat_notes", value: plan.merged.notes.count, symbol: "note.text")
                            StatCard(title: "stat_marks", value: plan.merged.userMarks.count, symbol: "pencil.tip")
                            StatCard(title: "stat_bookmarks", value: plan.merged.bookmarks.count, symbol: "bookmark")
                            StatCard(title: "stat_conflicts", value: plan.conflicts.count, symbol: "exclamationmark.triangle")
                        }
                        Text("compare_marks_summary")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        MergeScopeEditor(scope: Bindable(session).mergeScope, compact: true)
                        MergeScopeSummary(scope: session.plan?.scope ?? session.mergeScope)
                        if session.needsRescope {
                            Banner(kind: .info, text: String(localized: "merge_scope_needs_reapply", locale: locale))
                            Button {
                                Task { await session.compareAndMerge() }
                            } label: {
                                Label("merge_scope_reapply", systemImage: "arrow.triangle.merge")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, layout.pagePadding)
        .padding(.vertical, layout.isCompactHeight ? 6 : 10)
    }

    @ViewBuilder
    private var devicePicker: some View {
        if layout.prefersStackedControls || session.backups.count > 2 {
            Picker("filter_device", selection: Bindable(session).sourceFilter) {
                Text("filter_all_devices").tag(Optional<Int>.none)
                ForEach(session.backups) { backup in
                    Text(backup.displayName).lineLimit(1).tag(Optional(backup.sourceIndex))
                }
            }
        } else {
            Picker("filter_device", selection: Bindable(session).sourceFilter) {
                Text("filter_all_devices").tag(Optional<Int>.none)
                ForEach(session.backups) { backup in
                    Text(backup.displayName).lineLimit(1).tag(Optional(backup.sourceIndex))
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func beginEditing(_ item: ComparableItem) {
        guard let guid = item.noteGuid else { return }
        let record = session.noteRecord(guid: guid, sourceIndex: item.sourceIndex)
        editingNote = EditableNote(
            id: guid,
            sourceIndex: item.sourceIndex,
            sourceName: item.sourceName,
            title: record?.title ?? item.title,
            content: record?.content ?? item.detail
        )
    }
}

private struct ComparableRow: View {
    let item: ComparableItem
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(item.status.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(item.status.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(item.status.color)
            }
            Text(item.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack(spacing: 0) {
                Text(item.kind.label)
                Text(" · \(item.sourceName) · \(item.publication)")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            if item.noteGuid != nil {
                AdaptiveStack(spacing: 8) {
                    Button("note_edit", action: onEdit)
                    Button("note_delete", role: .destructive, action: onDelete)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct EditableNote: Identifiable {
    let id: String
    let sourceIndex: Int
    let sourceName: String
    var title: String
    var content: String
}

private struct NoteEditorSheet: View {
    let note: EditableNote
    var onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var content: String

    init(note: EditableNote, onSave: @escaping (String, String) -> Void) {
        self.note = note
        self.onSave = onSave
        _title = State(initialValue: note.title)
        _content = State(initialValue: note.content)
    }

    var body: some View {
        Form {
            Section {
                Text(note.sourceName)
                    .foregroundStyle(.secondary)
            } header: {
                Text("filter_device")
            }
            Section("note_title") {
                TextField("note_title", text: $title)
            }
            Section("note_content") {
                TextField("note_content", text: $content, axis: .vertical)
                    .lineLimit(8, reservesSpace: true)
            }
        }
        .navigationTitle("note_edit")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("note_cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("note_save") {
                    onSave(title, content)
                    dismiss()
                }
            }
        }
    }
}

extension ItemKind {
    var label: LocalizedStringKey {
        LocalizedStringKey(labelKey)
    }

    var labelKey: String {
        switch self {
        case .note: return "stat_notes"
        case .userMark: return "stat_marks"
        case .bookmark: return "stat_bookmarks"
        case .tag: return "stat_tags"
        case .tagMap: return "stat_tagmaps"
        case .inputField: return "stat_fields"
        case .location: return "stat_locations"
        }
    }

}

extension ConflictStatus {
    var label: LocalizedStringKey {
        switch self {
        case .unique: return "status_unique"
        case .identical: return "status_identical"
        case .conflict: return "status_conflict"
        case .resolved: return "status_resolved"
        }
    }

    var color: Color {
        switch self {
        case .unique: return .blue
        case .identical: return .secondary
        case .conflict: return .orange
        case .resolved: return .green
        }
    }
}
