import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RootView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(LanguageController.self) private var language
    @Environment(\.adaptiveLayout) private var layout
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    var body: some View {
        Group {
            if layout.usesSplitNavigation {
                splitView
            } else {
                compactNavigation
            }
        }
        .disabled(session.isWorking)
        .tint(.indigo)
        .overlay {
            if session.isWorking {
                WorkProgressOverlay(fraction: session.progressFraction, message: session.progressMessage)
            }
        }
        .sheet(isPresented: Bindable(session).showSettings) {
            settingsSheet
        }
        .environment(\.locale, language.locale)
    }

    private var compactNavigation: some View {
        NavigationStack {
            destination
                .toolbar {
#if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        workflowMenu
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        settingsButton
                    }
#else
                    ToolbarItem(placement: .automatic) {
                        workflowMenu
                    }
                    ToolbarItem(placement: .automatic) {
                        settingsButton
                    }
#endif
                }
#if os(iOS)
                .navigationBarTitleDisplayMode(layout.isCompactHeight ? .inline : .large)
#endif
        }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 248, max: 320)
        } detail: {
            NavigationStack {
                destination
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        List {
            Section {
                ForEach(WorkflowStep.allCases) { step in
                    Button {
                        session.step = step
                    } label: {
                        Label(step.title, systemImage: step.symbol)
                    }
                    .foregroundStyle(session.step == step ? Color.accentColor : Color.primary)
                    .accessibilityAddTraits(session.step == step ? .isSelected : [])
                }
            } header: {
                Text("nav_workflow")
            }
            Section {
                Button {
                    session.showSettings = true
                } label: {
                    Label("nav_settings", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("app_name")
    }

    private var workflowMenu: some View {
        Menu {
            Picker("nav_workflow", selection: Bindable(session).step) {
                ForEach(WorkflowStep.allCases) { step in
                    Label(step.title, systemImage: step.symbol).tag(step)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: session.step.symbol)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .accessibilityLabel(Text("nav_workflow"))
        .accessibilityValue(Text(session.step.title))
    }

    private var settingsButton: some View {
        Button {
            session.showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel(Text("nav_settings"))
    }

    private var settingsSheet: some View {
        NavigationStack {
            SettingsView()
        }
#if os(iOS)
        .presentationDragIndicator(.visible)
        .presentationDetents(layout.isCompactWidth ? [.large] : [.medium, .large])
#endif
#if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
#endif
    }

    @ViewBuilder
    private var destination: some View {
        switch session.step {
        case .importCopies:
            ImportView()
        case .compare:
            CompareView()
        case .conflicts:
            ConflictsView()
        case .export:
            ExportView()
        }
    }
}
