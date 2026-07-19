import Foundation

struct AppDirectories: Sendable {
    let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
            return
        }

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.root = applicationSupport.appendingPathComponent("Basalt", isDirectory: true)
    }

    var models: URL { root.appendingPathComponent("Models", isDirectory: true) }
    var attachments: URL { root.appendingPathComponent("Attachments", isDirectory: true) }
    var modelCatalog: URL { root.appendingPathComponent("models.json") }
    var conversations: URL { root.appendingPathComponent("conversations.json") }

    func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
    }
}
