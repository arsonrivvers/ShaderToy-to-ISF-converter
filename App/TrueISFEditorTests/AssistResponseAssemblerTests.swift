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
        let result = try subject.resolve(processExitSucceeded: true)
        XCTAssertEqual(result.response, "result")
        XCTAssertEqual(result.source, .result)
        XCTAssertEqual(result.receivedBytes, 9)
        XCTAssertEqual(result.eventCount, 2)
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
        let result = try subject.resolve(processExitSucceeded: true)
        XCTAssertEqual(result.response, "ABC")
        XCTAssertEqual(result.receivedBytes, 3)
        XCTAssertEqual(result.eventCount, 3)
    }

    func test_sendableLetCaptureConsumesConcurrentEventsDeterministically() async throws {
        let subject = AssistResponseAssembler(provider: .claude)
        let assistantEvent = AssistRunEvent.assistantMessage(
            messageID: "m1", stopReason: "end_turn",
            blocks: [AssistTextBlock(index: 0, text: "ABC")]
        )
        let resultEvent = AssistRunEvent.successfulResult("")
        let consumeAssistant: @Sendable () -> Void = { subject.consume(assistantEvent) }
        let consumeResult: @Sendable () -> Void = { subject.consume(resultEvent) }

        let assistantTask = Task.detached(operation: consumeAssistant)
        let resultTask = Task.detached(operation: consumeResult)
        await assistantTask.value
        await resultTask.value

        let result = try subject.resolve(processExitSucceeded: true)
        XCTAssertEqual(result.response, "ABC")
        XCTAssertEqual(result.receivedBytes, 3)
        XCTAssertEqual(result.eventCount, 2)
    }

    func test_laterCompleteSnapshotSupersedesPriorSnapshotInBlockIndexOrder() throws {
        var subject = AssistResponseAssembler(provider: .claude)
        subject.consume(.assistantMessage(
            messageID: "m1", stopReason: "end_turn",
            blocks: [AssistTextBlock(index: 0, text: "old")]
        ))
        subject.consume(.assistantMessage(
            messageID: "m2", stopReason: "end_turn",
            blocks: [
                AssistTextBlock(index: 1, text: "B"),
                AssistTextBlock(index: 0, text: "A"),
            ]
        ))
        subject.consume(.successfulResult(""))

        let result = try subject.resolve(processExitSucceeded: true)
        XCTAssertEqual(result.response, "AB")
        XCTAssertEqual(result.completeAssistantResponse, "AB")
        XCTAssertEqual(result.receivedBytes, 5)
        XCTAssertEqual(result.eventCount, 3)
    }
}
