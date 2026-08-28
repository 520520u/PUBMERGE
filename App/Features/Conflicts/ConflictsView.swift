import SwiftUI
import PubMergeCore

struct ConflictsView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        VStack(alignment: .leading, spacing: layout.isCompactWidth ? 12 : 16) {
            WorkflowHeader(step: .conflicts)
                .padding(.horizontal, layout.pagePadding)
            if let plan = session.plan {
                AdaptiveStack(spacing: 10, compactAlignment: .leading, regularAlignment: .center) {
                    Text(String(format: LanguageController.shared.localized("conflicts_count"), plan.unresolvedCount))
                        .font(.headline)
                    if !layout.prefersStackedControls {
                        Spacer()
                    }
                    Picker("merge_rule", selection: Bindable(session).selectedRule) {
                        Text("rule_newest").tag(MergeRule.newest)
                        Text("rule_primary").tag(MergeRule.primary)
                        Text("rule_secondary").tag(MergeRule.secondary)
                        Text("rule_keep_both").tag(MergeRule.keepBothNotes)
                    }
                    .frame(maxWidth: layout.prefersStackedControls ? .infinity : 260, alignment: .leading)
                    Button("apply_rule_all") {
                        session.applySelectedRule()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: layout.prefersStackedControls ? .infinity : nil)
                }
                .padding(.horizontal, layout.pagePadding)
                if plan.conflicts.isEmpty {
                    ContentUnavailableView("empty_conflicts_title", systemImage: "checkmark.seal", description: Text("empty_conflicts_body"))
                        .frame(maxHeight: .infinity)
                } else {
                    List(plan.conflicts) { conflict in
                        ConflictCard(conflict: conflict)
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: .infinity)
                }
                if !plan.decisions.isEmpty {
                    DisclosureGroup("decision_log") {
                        ForEach(plan.decisions) { decision in
                            Text(decision.summary)
                                .font(.caption.monospaced())
                                .padding(.vertical, 2)
                        }
                    }
                    .padding(.horizontal, layout.pagePadding)
                }
            } else {
                ContentUnavailableView("empty_compare_title", systemImage: "exclamationmark.triangle", description: Text("empty_compare_body"))
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.top, layout.isCompactHeight ? 8 : 16)
        .navigationTitle("step_conflicts")
    }
}

private struct ConflictCard: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.adaptiveLayout) private var layout
    let conflict: MergeConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(conflict.kind.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if conflict.isResolved {
                    Label("status_resolved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            AdaptiveStack(spacing: 12, compactAlignment: .leading, regularAlignment: .top) {
                ConflictSideView(title: conflict.left.sourceName, side: conflict.left)
                ConflictSideView(title: conflict.right.sourceName, side: conflict.right)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.isCompactWidth ? 120 : 140), spacing: 8)], spacing: 8) {
                Button("choose_left") { session.resolve(conflictID: conflict.id, as: .left) }
                Button("choose_right") { session.resolve(conflictID: conflict.id, as: .right) }
                Button("choose_newest") { session.resolve(conflictID: conflict.id, as: .newest) }
                if conflict.kind == .note {
                    Button("choose_both") { session.resolve(conflictID: conflict.id, as: .keepBoth) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}

private struct ConflictSideView: View {
    let title: String
    let side: ConflictSide

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(side.payload.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(side.payload.detail)
                .font(.body)
                .textSelection(.enabled)
            if let modified = side.modified {
                Text(modified)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
