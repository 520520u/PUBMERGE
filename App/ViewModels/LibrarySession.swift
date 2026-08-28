import Foundation
import Observation
import PubMergeCore
import UniformTypeIdentifiers

public enum WorkflowStep: String, CaseIterable, Identifiable, Sendable {
    case importCopies
    case compare
    case conflicts
    case export

    public var id: String { rawValue }
}

@MainActor
@Observable
final class LibrarySession {
    var backups: [ImportedBackup] = []
    var plan: MergePlan?
    var comparison: ComparisonSnapshot?
    var selectedRule: MergeRule = .newest
    var step: WorkflowStep = .importCopies
    var isWorking = false
    var progressMessage = ""
    var progressFraction = 0.0
    var errorMessage: String?
    var warningMessages: [String] = []
    var lastExport: ExportResult?
    var selectedConflictID: UUID?
    var exportName = "PubMerge-\(JWTimestamps.todayDateOnly()).jwlibrary"
    var encryptTemporaries = false
    var searchText = ""
    var kindFilter: ItemKind?
    var statusFilter: ConflictStatus?
    var sourceFilter: Int?
    var showSettings = false
    var mergeScope = MergeScope.all

    var needsRescope: Bool {
        guard let plan else { return false }
        return plan.scope != mergeScope
    }

    private let engine = MergeEngine()
    private(set) var workspace: WorkspaceStore

    init() {
        do {
            workspace = try WorkspaceStore()
        } catch {
            workspace = try! WorkspaceStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("PubMerge", isDirectory: true))
        }
    }

    var canCompare: Bool {
        backups.count >= 2 && backups.allSatisfy(\.canMerge)
    }

    var canExportMerged: Bool {
        guard let plan else { return false }
        return plan.canExport && !needsRescope && !isWorking
    }

    var unresolvedConflicts: Int {
        plan?.unresolvedCount ?? 0
    }

    var filteredItems: [ComparableItem] {
        guard let comparison else { return [] }
        return comparison.items.filter { item in
            if let kindFilter, item.kind != kindFilter { return false }
            if let statusFilter, item.status != statusFilter { return false }
            if let sourceFilter, item.sourceIndex != sourceFilter { return false }
            let tokens = searchText.lowercased().split { $0.isWhitespace || $0.isNewline }.map(String.init)
            if tokens.isEmpty { return true }
            let haystack = [item.title, item.detail, item.publication, item.sourceName, item.kind.rawValue]
                .joined(separator: " ")
                .lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    func importFiles(at urls: [URL]) async {
        await runWork(initial: WorkProgress(fraction: 0, stage: .importCopies)) { reporter in
            let workspace = try WorkspaceStore(encryptTemporaryFiles: self.encryptTemporaries)
            self.workspace = workspace
            let startIndex = self.backups.count
            let imported = try await Task.detached(priority: .userInitiated) {
                var results: [ImportedBackup] = []
                for (offset, url) in urls.enumerated() {
                    let backup = try JWLibraryArchive.importBackup(
                        from: url,
                        workspace: workspace,
                        sourceIndex: startIndex + offset,
                        progress: { progress in
                            let overall = (Double(offset) + progress.fraction) / Double(max(urls.count, 1))
                            reporter(WorkProgress(fraction: overall, stage: progress.stage, detail: progress.detail))
                        }
                    )
                    results.append(backup)
                }
                return results
            }.value
            backups.append(contentsOf: imported)
            for backup in imported {
                if let warning = backup.hashWarning {
                    warningMessages.append(warning)
                }
                if case .upgradable(let from, let to) = backup.schema {
                    warningMessages.append(String(format: localized("warning_schema_upgrade"), from, to))
                }
            }
        }
    }

    func removeBackup(_ id: UUID) {
        backups.removeAll { $0.id == id }
        for index in backups.indices {
            backups[index].sourceIndex = index
        }
        plan = nil
        comparison = nil
        lastExport = nil
        step = .importCopies
    }

    func compareAndMerge() async {
        guard canCompare else {
            errorMessage = PubMergeError.emptyMerge.localizedDescription
            return
        }
        let backups = self.backups
        let scope = mergeScope
        await runWork(initial: WorkProgress(fraction: 0, stage: .compare)) { reporter in
            let preview = try await Task.detached(priority: .userInitiated) {
                try MergeEngine().preview(backups: backups, scope: scope, progress: reporter)
            }.value
            let snapshot = await Task.detached(priority: .userInitiated) {
                MergeEngine().compare(backups: backups, plan: preview, progress: reporter)
            }.value
            plan = preview
            comparison = snapshot
            warningMessages.append(contentsOf: preview.warnings.map(\.message))
            let videoWarning = localized("warning_videos_excluded")
            if !scope.videos, !warningMessages.contains(videoWarning) {
                warningMessages.append(videoWarning)
            }
            step = .compare
        }
    }

    func applySelectedRule() {
        guard let plan else { return }
        let updated = engine.apply(rule: selectedRule, to: plan)
        self.plan = updated
        comparison = engine.compare(backups: backups, plan: updated)
        step = updated.unresolvedCount == 0 ? .compare : .conflicts
    }

    func resolve(conflictID: UUID, as resolution: ConflictResolution) {
        guard let plan else { return }
        let updated = engine.resolve(conflictID: conflictID, as: resolution, in: plan)
        self.plan = updated
        comparison = engine.compare(backups: backups, plan: updated)
        if updated.unresolvedCount == 0 {
            step = .compare
        }
    }

    func exportMerged() async {
        guard var plan else { return }
        if plan.unresolvedCount > 0 {
            plan = engine.apply(rule: selectedRule, to: plan)
            self.plan = plan
        }
        guard plan.canExport else {
            errorMessage = PubMergeError.unresolvedConflicts(plan.unresolvedCount).localizedDescription
            step = .conflicts
            return
        }
        let workspace = self.workspace
        let exportName = self.exportName
        let mergedDatabase = plan.merged
        let media = plan.mediaFiles
        let includeMedia = plan.scope.videos
        await runWork(initial: WorkProgress(fraction: 0, stage: .export)) { reporter in
            lastExport = try await Task.detached(priority: .userInitiated) {
                try JWLibraryExporter.export(
                    ExportRequest(
                        fileName: exportName,
                        deviceName: "PubMerge",
                        database: mergedDatabase,
                        mediaFiles: media,
                        includeMedia: includeMedia
                    ),
                    workspace: workspace,
                    progress: reporter
                )
            }.value
            step = .export
        }
    }

    func clearTemporaryFiles() {
        do {
            try workspace.secureDeleteTemporaries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        backups = []
        plan = nil
        comparison = nil
        lastExport = nil
        warningMessages = []
        errorMessage = nil
        mergeScope = .all
        searchText = ""
        kindFilter = nil
        statusFilter = nil
        sourceFilter = nil
        showSettings = false
        step = .importCopies
    }

    func returnToHome() {
        step = .importCopies
        showSettings = false
    }

    func goToExport() {
        guard canExportMerged else {
            if unresolvedConflicts > 0 {
                step = .conflicts
            }
            return
        }
        step = .export
    }

    func noteRecord(guid: String, sourceIndex: Int) -> NoteRecord? {
        backups.first(where: { $0.sourceIndex == sourceIndex })?.database.notes.first(where: { $0.guid == guid })
    }

    func updateNote(guid: String, sourceIndex: Int, title: String, content: String) {
        let now = JWTimestamps.nowISO()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTitle = trimmedTitle.isEmpty ? nil : trimmedTitle
        let nextContent = content
        for index in backups.indices where backups[index].sourceIndex == sourceIndex {
            _ = backups[index].database.updateNote(guid: guid, title: nextTitle, content: nextContent, modified: now)
        }
        if var plan {
            plan.updateNote(guid: guid, title: nextTitle, content: nextContent, modified: now, sourceIndex: sourceIndex)
            self.plan = plan
            comparison = engine.compare(backups: backups, plan: plan)
        } else if var comparison {
            if let itemIndex = comparison.items.firstIndex(where: { $0.noteGuid == guid && $0.sourceIndex == sourceIndex }) {
                comparison.items[itemIndex].title = nextTitle ?? String(nextContent.prefix(40))
                comparison.items[itemIndex].detail = nextContent
                comparison.items[itemIndex].modified = now
            }
            self.comparison = comparison
        }
        lastExport = nil
    }

    func deleteNoteFromMergedList(guid: String) {
        for index in backups.indices {
            _ = backups[index].database.deleteNote(guid: guid)
        }
        if var plan {
            plan.deleteNote(guid: guid)
            self.plan = plan
            comparison = engine.compare(backups: backups, plan: plan)
        } else if var comparison {
            comparison.items.removeAll { $0.noteGuid == guid }
            self.comparison = comparison
        }
        lastExport = nil
    }

    private func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), locale: LanguageController.shared.locale)
    }

    private func applyProgress(_ progress: WorkProgress) {
        progressFraction = progress.fraction
        var message = localized(progress.stage.localizationKey)
        if let detail = progress.detail, !detail.isEmpty {
            message = "\(message) \(detail)"
        }
        progressMessage = message
    }

    private func runWork(initial: WorkProgress, operation: (@escaping WorkProgressHandler) async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        applyProgress(initial)
        let (stream, continuation) = AsyncStream<WorkProgress>.makeStream()
        let consume = Task { @MainActor in
            for await progress in stream {
                applyProgress(progress)
            }
        }
        let reporter: WorkProgressHandler = { progress in
            continuation.yield(progress)
        }
        defer {
            continuation.finish()
            isWorking = false
            progressMessage = ""
            progressFraction = 0
        }
        do {
            try await operation(reporter)
        } catch {
            errorMessage = error.localizedDescription
        }
        continuation.finish()
        await consume.value
    }
}

extension UTType {
    static let jwlibrary = UTType(filenameExtension: "jwlibrary") ?? .data
}
