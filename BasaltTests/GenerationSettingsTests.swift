import XCTest
@testable import Basalt

final class GenerationSettingsTests: XCTestCase {
    func testPresetsApplyExpectedSamplingValues() {
        var settings = GenerationSettings.default
        settings.apply(.precise)
        XCTAssertEqual(settings.temperature, 0.2)
        XCTAssertEqual(settings.topP, 0.8)

        settings.apply(.creative)
        XCTAssertEqual(settings.temperature, 1.0)
        XCTAssertEqual(settings.topK, 64)
    }

    func testQuantizationDetectionUsesLongestSpecificNamesFirst() {
        let model = ModelRecord(
            id: UUID(),
            name: "Test",
            fileName: "model-Q5_K_M.gguf",
            byteCount: 1,
            importedAt: Date(),
            lastUsedAt: nil,
            origin: .files,
            sourceURL: nil
        )
        XCTAssertEqual(model.quantization, "Q5_K_M")
    }

    func testConversationDecodesWithoutNewOptionalMediaFields() throws {
        let json = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "role":"user",
          "text":"Hello",
          "createdAt":0
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let message = try decoder.decode(ChatMessage.self, from: json)
        XCTAssertNil(message.attachments)
        XCTAssertNil(message.reasoning)
        XCTAssertNil(message.sources)
    }
}

