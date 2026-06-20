import XCTest
@testable import ListenToMeCore

final class QuestionDetectorTests: XCTestCase {
    func testQuestionMarkIsQuestion() {
        XCTAssertTrue(QuestionDetector.isQuestion("So what is the timeline?"))
    }

    func testLeadingInterrogativeIsQuestion() {
        XCTAssertTrue(QuestionDetector.isQuestion("How should we handle retries"))
        XCTAssertTrue(QuestionDetector.isQuestion("can you walk me through it"))
    }

    func testEmbeddedCueIsQuestion() {
        XCTAssertTrue(QuestionDetector.isQuestion("Tom, what do you think about that"))
    }

    func testStatementIsNotQuestion() {
        XCTAssertFalse(QuestionDetector.isQuestion("We shipped the release yesterday."))
    }

    func testEmptyIsNotQuestion() {
        XCTAssertFalse(QuestionDetector.isQuestion("   "))
    }

    func testCuePrefixInsideWordIsNotQuestion() {
        XCTAssertFalse(QuestionDetector.isQuestion("However, the release is ready"))
        XCTAssertFalse(QuestionDetector.isQuestion("I tried whatever worked"))
    }

    func testInterrogativeWordMidSentenceIsNotQuestion() {
        XCTAssertFalse(QuestionDetector.isQuestion("I know what happened"))
        XCTAssertFalse(QuestionDetector.isQuestion("They explained why it failed"))
    }
}
