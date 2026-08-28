import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct PubMergeApp: App {
    @State private var session = LibrarySession()
    @State private var language = LanguageController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(language)
                .environment(\.locale, language.locale)
                .adaptiveLayoutBridge()
                .onOpenURL { url in
                    Task { await session.importFiles(at: [url]) }
                }
#if DEBUG
                .task {
                    if let directory = StoreScreenshotDemo.exportDirectory {
                        await StoreScreenshotDemo.exportAll(to: directory, session: session, language: language)
#if os(macOS)
                        NSApplication.shared.terminate(nil)
#endif
                    } else if StoreScreenshotDemo.requestedScene != nil {
                        await StoreScreenshotDemo.prepare(session, language: language)
                    }
                }
#endif
        }
#if os(macOS)
        .defaultSize(width: 1100, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
#endif
    }
}
