import XCTest
@testable import Basalt

final class ModelCapabilityDetectorTests: XCTestCase {
    func testDetectsTemplateAndModelFamilyControls() {
        XCTAssertEqual(
            ModelCapabilityDetector.thinkingControl(
                metadata: ["general.name": "Qwen3 4B"],
                chatTemplate: ""
            ),
            .qwenSlashCommand
        )
        XCTAssertEqual(
            ModelCapabilityDetector.thinkingControl(
                metadata: ["general.name": "GLM-4.5 Air"],
                chatTemplate: ""
            ),
            .glmSlashCommand
        )
        XCTAssertEqual(
            ModelCapabilityDetector.thinkingControl(
                metadata: ["general.name": "DeepSeek-R1 Distill"],
                chatTemplate: ""
            ),
            .closingTag
        )
        XCTAssertEqual(
            ModelCapabilityDetector.thinkingControl(
                metadata: [:],
                chatTemplate: "{{ reasoning_effort }}"
            ),
            .reasoningEffort
        )
    }

    func testOrdinaryInstructModelDoesNotExposeThinkingToggle() {
        XCTAssertEqual(
            ModelCapabilityDetector.thinkingControl(
                metadata: ["general.name": "Small Instruct"],
                chatTemplate: "{{ messages }}"
            ),
            .none
        )
    }
}
