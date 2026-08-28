import SwiftUI

struct AdaptiveLayout: Equatable {
    var horizontal: UserInterfaceSizeClass?
    var vertical: UserInterfaceSizeClass?
    var dynamicType: DynamicTypeSize = .large

    var isCompactWidth: Bool { horizontal != .regular }
    var isRegularWidth: Bool { horizontal == .regular }
    var isCompactHeight: Bool { vertical == .compact }
    var prefersStackedControls: Bool { isCompactWidth || dynamicType.isAccessibilitySize }

    var pagePadding: CGFloat {
        if isCompactHeight { return 12 }
        return isCompactWidth ? 16 : 24
    }

    var readableWidth: CGFloat { 780 }

    var statMinimum: CGFloat { isCompactWidth ? 148 : 168 }

    var scopeMinimum: CGFloat { isCompactWidth ? 156 : 240 }

    var prominentControlSize: ControlSize {
        isCompactWidth ? .large : .extraLarge
    }

    var usesSplitNavigation: Bool { isRegularWidth }
}

private struct AdaptiveLayoutKey: EnvironmentKey {
    static let defaultValue = AdaptiveLayout(horizontal: .regular, vertical: .regular)
}

extension EnvironmentValues {
    var adaptiveLayout: AdaptiveLayout {
        get { self[AdaptiveLayoutKey.self] }
        set { self[AdaptiveLayoutKey.self] = newValue }
    }
}

struct AdaptiveLayoutBridge: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.environment(
            \.adaptiveLayout,
            AdaptiveLayout(
                horizontal: horizontalSizeClass,
                vertical: verticalSizeClass,
                dynamicType: dynamicTypeSize
            )
        )
    }
}

struct ReadablePageModifier: ViewModifier {
    @Environment(\.adaptiveLayout) private var layout

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: layout.readableWidth, alignment: .leading)
            .padding(layout.pagePadding)
            .frame(maxWidth: .infinity)
    }
}

struct AdaptiveStack<Content: View>: View {
    @Environment(\.adaptiveLayout) private var layout
    var spacing: CGFloat = 12
    var compactAlignment: HorizontalAlignment = .leading
    var regularAlignment: VerticalAlignment = .center
    @ViewBuilder var content: Content

    var body: some View {
        if layout.prefersStackedControls {
            VStack(alignment: compactAlignment, spacing: spacing) {
                content
            }
        } else {
            HStack(alignment: regularAlignment, spacing: spacing) {
                content
            }
        }
    }
}

extension View {
    func adaptiveLayoutBridge() -> some View {
        modifier(AdaptiveLayoutBridge())
    }

    func readablePage() -> some View {
        modifier(ReadablePageModifier())
    }

    func adaptiveHeadline() -> some View {
        modifier(AdaptiveHeadlineModifier())
    }
}

private struct AdaptiveHeadlineModifier: ViewModifier {
    @Environment(\.adaptiveLayout) private var layout

    func body(content: Content) -> some View {
        content
            .font(layout.isCompactWidth ? .title.bold() : .largeTitle.bold())
            .minimumScaleFactor(0.8)
            .lineLimit(layout.isCompactHeight ? 2 : 3)
    }
}
