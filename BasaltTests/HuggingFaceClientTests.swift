import XCTest
@testable import Basalt

final class HuggingFaceClientTests: XCTestCase {
    func testBlobURLBecomesResolveURL() throws {
        let url = try HuggingFaceClient.normalizedModelURL(
            from: "https://huggingface.co/owner/repo/blob/main/models/model-q4_k_m.gguf"
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://huggingface.co/owner/repo/resolve/main/models/model-q4_k_m.gguf"
        )
    }

    func testResolveURLPreservesQuery() throws {
        let url = try HuggingFaceClient.normalizedModelURL(
            from: "https://huggingface.co/owner/repo/resolve/main/model.gguf?download=true"
        )
        XCTAssertEqual(url.query, "download=true")
    }

    func testRejectsRepositoryURL() {
        XCTAssertThrowsError(
            try HuggingFaceClient.normalizedModelURL(from: "https://huggingface.co/owner/repo")
        )
    }

    func testRejectsNonHuggingFaceHost() {
        XCTAssertThrowsError(
            try HuggingFaceClient.normalizedModelURL(from: "https://example.com/model.gguf")
        )
    }
}

