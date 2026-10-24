import XCTest
@testable import ListenToMeCore

/// A glossary term never lets a correction add or remove a number or a negation (#222 review).
final class CorrectionGuardTests: XCTestCase {
    private func allowed(_ original: String, _ corrected: String, _ glossary: [String]) -> Bool {
        CorrectionGuard.preservesProtectedTerms(original: original, corrected: corrected, glossary: glossary)
    }

    func testATermCannotAddANegation() {
        XCTAssertFalse(allowed("our show rate dropped", "our no-show rate dropped", ["no-show rate"]))
        XCTAssertFalse(allowed("the case was dismissed with prejudice", "the case was dismissed without prejudice",
                               ["without prejudice", "dismissal with prejudice"]))
        XCTAssertFalse(allowed("we did approve it", "we did not approve it", ["not"]))
    }

    func testATermCannotDropANumberOutsideItsOwnSpan() {
        let glossary = ["SOC 2", "SOC 2 report"]
        XCTAssertFalse(allowed("SOC 2 audit for 2 vendors", "SOC 2 audit for vendors", glossary))
        XCTAssertFalse(allowed("SOC 2 audit for 2 vendors", "audit for vendors", glossary))
        XCTAssertFalse(allowed("move 3 nodes to e c2", "move 4 nodes to EC2", ["EC2"]))
    }

    func testATermsOwnTokensAreExemptWhenTheOriginalSaidThem() {
        XCTAssertTrue(allowed("deploy the e c2 instance", "deploy the EC2 instance", ["EC2"]))
        XCTAssertTrue(allowed("we need the sock 2 report", "we need the SOC 2 report", ["SOC 2 report", "SOC 2"]))
        XCTAssertTrue(allowed("dismissed without predjudice", "dismissed without prejudice", ["without prejudice"]))
        XCTAssertTrue(allowed("the iso 9001 audit for 2 sites", "the ISO 9001 audit for 2 sites", ["ISO 9001"]))
    }

    func testWithoutAGlossaryEveryNumberAndNegationMustSurvive() {
        XCTAssertTrue(allowed("please send the meeting goats", "please send the meeting notes", []))
        XCTAssertFalse(allowed("deploy the easy instance", "deploy the EC2 instance", []))
        XCTAssertFalse(allowed("deploy the easy instance", "deploy the EC2 instance", ["EC2"]),
                       "nothing in the original carried the 2")
        XCTAssertFalse(allowed("不要提交这个报告", "要提交这个报告", []))
        XCTAssertEqual(CorrectionGuard.protectedTerms("Don’t pay 1,500 or 2.5 — never"), ["don't", "1,500", "2.5", "never"])
    }
}
