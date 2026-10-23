import XCTest
@testable import ListenToMeCore

/// Which Apple Watch command the iPhone accepts (issue #181). The phone never starts its microphone
/// unless the app is in the foreground.
final class RemoteRecorderPolicyTests: XCTestCase {
    private let states: [PhoneRecorderState] = [.idle, .preparing, .recording, .stopping]

    /// The table in the plan, cell by cell.
    private func expected(_ command: WatchCommand, _ state: PhoneRecorderState, active: Bool,
                          summarizing: Bool) -> RemoteRecorderDecision {
        switch command {
        case .status:
            return .report
        case .stop:
            return state == .recording || state == .preparing ? .stop : .report
        case .start:
            guard active else { return .reply(.openPhoneApp) }
            switch state {
            case .idle: return summarizing ? .reply(.busy("Generating a summary on iPhone")) : .start
            case .preparing, .recording: return .report
            case .stopping: return .reply(.busy("Stopping on iPhone"))
            }
        }
    }

    func testEveryCommandStateAndForegroundCell() {
        for command in WatchCommand.allCases {
            for state in states {
                for active in [true, false] {
                    for summarizing in [true, false] {
                        XCTAssertEqual(RemoteRecorderPolicy.decide(command, state: state, isActive: active,
                                                                   isSummarizing: summarizing),
                                       expected(command, state, active: active, summarizing: summarizing),
                                       "\(command) \(state) active=\(active) summarizing=\(summarizing)")
                    }
                }
            }
        }
    }

    func testTheNamedCells() {
        XCTAssertEqual(RemoteRecorderPolicy.decide(.start, state: .idle, isActive: true, isSummarizing: false), .start)
        XCTAssertEqual(RemoteRecorderPolicy.decide(.start, state: .idle, isActive: false, isSummarizing: false),
                       .reply(.openPhoneApp))
        XCTAssertEqual(RemoteRecorderPolicy.decide(.start, state: .idle, isActive: true, isSummarizing: true),
                       .reply(.busy("Generating a summary on iPhone")))
        XCTAssertEqual(RemoteRecorderPolicy.decide(.start, state: .stopping, isActive: true, isSummarizing: false),
                       .reply(.busy("Stopping on iPhone")))
        XCTAssertEqual(RemoteRecorderPolicy.decide(.start, state: .recording, isActive: true, isSummarizing: false),
                       .report)
        XCTAssertEqual(RemoteRecorderPolicy.decide(.stop, state: .recording, isActive: false, isSummarizing: false),
                       .stop)
        XCTAssertEqual(RemoteRecorderPolicy.decide(.stop, state: .preparing, isActive: true, isSummarizing: true),
                       .stop)
        XCTAssertEqual(RemoteRecorderPolicy.decide(.stop, state: .idle, isActive: true, isSummarizing: false), .report)
        XCTAssertEqual(RemoteRecorderPolicy.decide(.status, state: .recording, isActive: true, isSummarizing: false),
                       .report)
    }

    func testInactiveStartNeverStarts() {
        for command in WatchCommand.allCases {
            for state in states {
                for summarizing in [true, false] {
                    XCTAssertNotEqual(RemoteRecorderPolicy.decide(command, state: state, isActive: false,
                                                                  isSummarizing: summarizing), .start)
                }
            }
        }
    }
}
