#if DEBUG
import SwiftUI
import PubMergeCore

enum StoreScreenshotScene: String, CaseIterable {
    case importCopies
    case compare
    case conflicts
    case export
    case settings
}

@MainActor
enum StoreScreenshotDemo {
    static var exportDirectory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demoExportScreenshots"),
              arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static var requestedScene: StoreScreenshotScene? {
        guard ProcessInfo.processInfo.arguments.contains("-demoStoreScreenshots") else { return nil }
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-demoStep"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let scene = StoreScreenshotScene(rawValue: ProcessInfo.processInfo.arguments[index + 1]) {
            return scene
        }
        return .importCopies
    }

    static func prepare(_ session: LibrarySession, language: LanguageController, scene: StoreScreenshotScene? = requestedScene) async {
        language.language = .english
        do {
            let workspace = try WorkspaceStore()
            let pair = try SyntheticBackupFactory.pairForMergeTests(workspace: workspace)
            await session.importFiles(at: [pair.primary, pair.secondary])
            await session.compareAndMerge()
            apply(scene ?? .importCopies, to: session)
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    static func apply(_ scene: StoreScreenshotScene, to session: LibrarySession) {
        session.showSettings = false
        switch scene {
        case .importCopies:
            session.step = .importCopies
        case .compare:
            session.step = .compare
        case .conflicts:
            session.step = .conflicts
        case .export:
            session.applySelectedRule()
            session.step = .export
        case .settings:
            session.step = .importCopies
            session.showSettings = true
        }
    }

    static func exportAll(to directory: URL, session: LibrarySession, language: LanguageController) async {
        language.language = .english
        await prepare(session, language: language, scene: .importCopies)
        let fileManager = FileManager.default
        let directory = writableDirectory(directory)
        let targets: [(folder: String, width: CGFloat, height: CGFloat, scale: CGFloat, compact: Bool)] = [
            ("iPhone-6.9", 440, 956, 3, true),
            ("iPad-13", 1032, 1376, 2, false),
            ("Mac", 1440, 900, 2, false)
        ]
        for target in targets {
            let folder = directory.appendingPathComponent(target.folder, isDirectory: true)
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let scenes = StoreScreenshotScene.allCases
        print("PubMerge store screenshots → \(directory.path)")
        for (index, scene) in scenes.enumerated() {
            if scene == .export {
                session.applySelectedRule()
            }
            apply(scene == .export ? .export : scene, to: session)
            try? await Task.sleep(for: .milliseconds(200))
            let prefix = String(format: "%02d", index + 1)
            for target in targets {
                let layout = AdaptiveLayout(
                    horizontal: target.compact ? .compact : .regular,
                    vertical: .regular
                )
                let view = screenshotView(session: session, language: language, scene: scene, layout: layout)
                    .frame(width: target.width, height: target.height)
                let data = renderJPEG(view: view, scale: target.scale)
                let url = directory
                    .appendingPathComponent(target.folder, isDirectory: true)
                    .appendingPathComponent("\(prefix)-\(scene.rawValue).jpg")
                try? data?.write(to: url)
            }
        }
    }

    @ViewBuilder
    private static func screenshotView(
        session: LibrarySession,
        language: LanguageController,
        scene: StoreScreenshotScene,
        layout: AdaptiveLayout
    ) -> some View {
        Group {
            if scene == .settings {
                NavigationStack {
                    SettingsView()
                }
            } else {
                RootView()
            }
        }
        .environment(session)
        .environment(language)
        .environment(\.locale, language.locale)
        .environment(\.adaptiveLayout, layout)
        .environment(\.horizontalSizeClass, layout.horizontal)
        .environment(\.verticalSizeClass, layout.vertical)
        .environment(\.colorScheme, .light)
        .tint(.indigo)
    }

    private static func writableDirectory(_ preferred: URL) -> URL {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: preferred, withIntermediateDirectories: true)
            let probe = preferred.appendingPathComponent(".write-test")
            try Data().write(to: probe)
            try fileManager.removeItem(at: probe)
            return preferred
        } catch {
            let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PubMergeStoreScreenshots", isDirectory: true)
            try? fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
            return downloads
        }
    }

    private static func renderJPEG<V: View>(view: V, scale: CGFloat) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
#if os(macOS)
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
#else
        guard let image = renderer.uiImage, let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return data
#endif
    }
}
#endif
