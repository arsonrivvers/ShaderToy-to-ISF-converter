import XCTest

@MainActor
final class AssistResponseAssemblerTests: XCTestCase {
    func test_emptySuccessfulResultFallsBackToCompleteAssistant() throws {
        var subject = AssistResponseAssembler(provider: .claude)
        subject.consume(.assistantMessage(
            messageID: "m1",
            stopReason: "end_turn",
            blocks: [AssistTextBlock(index: 0, text: "/*{\"ISFVSN\":\"2.0\"}*/\nvoid main(){}")]
        ))
        subject.consume(.successfulResult(""))

        let result = try subject.resolve(processExitSucceeded: true)

        XCTAssertEqual(result.source, .assistantMessage)
        XCTAssertTrue(result.response.contains("ISFVSN"))
        XCTAssertTrue(result.observedSuccessfulResult)
    }

    func test_nonEmptySuccessfulResultWins() throws {
        var subject = AssistResponseAssembler(provider: .claude)
        subject.consume(.assistantMessage(
            messageID: "m1", stopReason: "end_turn",
            blocks: [AssistTextBlock(index: 0, text: "assistant")]
        ))
        subject.consume(.successfulResult("result"))
        XCTAssertEqual(try subject.resolve(processExitSucceeded: true).response, "result")
    }

    func test_errorResultNeverPromotesAssistantText() {
        var subject = AssistResponseAssembler(provider: .claude)
        subject.consume(.assistantMessage(
            messageID: "m1", stopReason: "end_turn",
            blocks: [AssistTextBlock(index: 0, text: "shader-looking text")]
        ))
        subject.consume(.errorResult("rate limited"))
        XCTAssertThrowsError(try subject.resolve(processExitSucceeded: false)) {
            XCTAssertEqual($0 as? AssistAssemblyError, .providerFailed("rate limited"))
        }
    }

    func test_completeSnapshotReplacesItsDeltasInsteadOfDuplicatingThem() throws {
        var subject = AssistResponseAssembler(provider: .claude)
        subject.consume(.textDelta(messageID: "m1", blockIndex: 0, text: "ABC"))
        subject.consume(.assistantMessage(
            messageID: "m1", stopReason: "end_turn",
            blocks: [AssistTextBlock(index: 0, text: "ABC")]
        ))
        subject.consume(.successfulResult(""))
        XCTAssertEqual(try subject.resolve(processExitSucceeded: true).response, "ABC")
    }
}
