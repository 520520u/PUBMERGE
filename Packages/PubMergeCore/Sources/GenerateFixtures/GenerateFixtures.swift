import Foundation
import PubMergeCore

@main
struct GenerateFixtures {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Synthetic", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let workspace = try WorkspaceStore(rootURL: root.appendingPathComponent("workspace", isDirectory: true))
        let pair = try SyntheticBackupFactory.pairForMergeTests(workspace: workspace)
        for (source, name) in [(pair.primary, "PrimaryPhone.jwlibrary"), (pair.secondary, "SecondaryPad.jwlibrary")] {
            let destination = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            print(destination.path)
        }
    }
}
