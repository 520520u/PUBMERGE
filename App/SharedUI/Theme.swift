import SwiftUI
import PubMergeCore

enum PubMergeTheme {
    static let accent = Color.indigo
}

struct WorkflowHeader: View {
    let step: WorkflowStep
    @Environment(LibrarySession.self) private var session

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorkflowStep.allCases) { item in
                    let active = item == step
                    Button {
                        session.step = item
                    } label: {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(active ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
                            .foregroundStyle(active ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("workflow_steps"))
    }
}

extension WorkflowStep {
    var title: LocalizedStringKey {
        switch self {
        case .importCopies: return "step_import"
        case .compare: return "step_compare"
        case .conflicts: return "step_conflicts"
        case .export: return "step_export"
        }
    }

    var symbol: String {
        switch self {
        case .importCopies: return "tray.and.arrow.down"
        case .compare: return "rectangle.split.2x1"
        case .conflicts: return "exclamationmark.triangle"
        case .export: return "square.and.arrow.up"
        }
    }
}

struct StatCard: View {
    let title: LocalizedStringKey
    let value: Int
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct WorkProgressOverlay: View {
    let fraction: Double
    let message: String
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: layout.isCompactWidth ? 240 : 280)
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("progress_keep_open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(layout.isCompactWidth ? 20 : 28)
            .frame(maxWidth: layout.isCompactWidth ? 320 : 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(layout.pagePadding)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

struct MergeScopeEditor: View {
    @Binding var scope: MergeScope
    var compact: Bool = false
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveStack(spacing: 8, regularAlignment: .center) {
                Text("merge_scope_title")
                    .font(compact || layout.isCompactWidth ? .headline : .title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("merge_scope_all") { scope.selectAll() }
                        .disabled(scope.isAll)
                    Button("merge_scope_none") { scope.selectNone() }
                        .disabled(scope.isEmpty)
                }
            }
            if !compact {
                Text("merge_scope_subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.scopeMinimum), spacing: 10)], spacing: 10) {
                ForEach(MergeScope.Category.allCases) { category in
                    Toggle(isOn: binding(for: category)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(category.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: category.symbol)
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(10)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHint(Text(category.detail))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("merge_scope_title"))
    }

    private func binding(for category: MergeScope.Category) -> Binding<Bool> {
        Binding(
            get: { scope[category] },
            set: { scope[category] = $0 }
        )
    }
}

struct MergeScopeSummary: View {
    let scope: MergeScope

    var body: some View {
        Text(scope.isAll ? LanguageController.shared.localized("merge_scope_all_selected") : LanguageController.shared.localized("merge_scope_partial_selected"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

extension MergeScope.Category {
    var title: LocalizedStringKey {
        switch self {
        case .notes: return "scope_notes"
        case .highlights: return "scope_highlights"
        case .bookmarks: return "scope_bookmarks"
        case .tags: return "scope_tags"
        case .inputFields: return "scope_fields"
        case .videos: return "scope_videos"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .notes: return "scope_notes_detail"
        case .highlights: return "scope_highlights_detail"
        case .bookmarks: return "scope_bookmarks_detail"
        case .tags: return "scope_tags_detail"
        case .inputFields: return "scope_fields_detail"
        case .videos: return "scope_videos_detail"
        }
    }

    var symbol: String {
        switch self {
        case .notes: return "note.text"
        case .highlights: return "pencil.tip"
        case .bookmarks: return "bookmark"
        case .tags: return "tag"
        case .inputFields: return "text.cursor"
        case .videos: return "film"
        }
    }
}

struct Banner: View {
    enum Kind { case error, warning, info }
    let kind: Kind
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
            Text(text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch kind {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
