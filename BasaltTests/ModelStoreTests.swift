import Foundation
import XCTest
@testable import Basalt

final class ModelStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BasaltTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsAndCatalogsGGUF() async throws {
        let source = root.appendingPathComponent("tiny-q4_k_m.gguf")
        var data = Data([0x47, 0x47, 0x55, 0x46])
        data.append(Data(repeating: 0, count: 64))
        try data.write(to: source)

        let store = ModelStore(root: root.appendingPathComponent("Library"))
        let model = try await store.importModel(from: source, origin: .files)

        XCTAssertEqual(model.quantization, "Q4_K_M")
        XCTAssertEqual(model.byteCount, 68)
        let catalog = try await store.models()
        XCTAssertEqual(catalog.map(\.id), [model.id])
        let copiedURL = await store.modelURL(for: model)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedURL.path))
    }

    func testRejectsWrongMagic() async throws {
        let source = root.appendingPathComponent("not-a-model.gguf")
        try Data("nope".utf8).write(to: source)
        let store = ModelStore(root: root.appendingPathComponent("Library"))

        do {
            _ = try await store.importModel(from: source, origin: .files)
            XCTFail("Expected a GGUF validation error")
        } catch let error as ModelStoreError {
            XCTAssertEqual(error, .notGGUF)
        }
    }

    func testProjectorIsAttachedInsteadOfCatalogedAsModel() async throws {
        let modelSource = root.appendingPathComponent("model.gguf")
        let projectorSource = root.appendingPathComponent("mmproj-model.gguf")
        let bytes = Data([0x47, 0x47, 0x55, 0x46, 0, 0, 0, 0])
        try bytes.write(to: modelSource)
        try bytes.write(to: projectorSource)
        let store = ModelStore(root: root.appendingPathComponent("Library"))
        let model = try await store.importModel(from: modelSource, origin: .files)

        let updated = try await store.attachProjector(from: projectorSource, to: model)
        XCTAssertNotNil(updated.projectorFileName)
        let projectorURL = await store.projectorURL(for: updated)
        let catalog = try await store.models()
        XCTAssertNotNil(projectorURL)
        XCTAssertEqual(catalog.count, 1)
    }
}
