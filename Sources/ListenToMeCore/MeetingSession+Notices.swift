import Foundation

/// The notices recorded for one pane's text: which part of the conversation it read when it could
/// not read all of it (issue #114) and whether it stopped at the model's output limit (issue #215).
struct RoleNoticeRecord: Equatable {
    /// The exact text the notices describe.
    let text: String
    let grounding: String?
    let cutOff: Bool
}

extension MeetingSession {
    /// One-line notes a pane shows under its title, in order: which part of the conversation the
    /// answer read when it could not read all of it, then whether it stopped at the model's output
    /// limit. While a request streams, only its own grounding line shows. Afterwards a pane shows the
    /// notices recorded for its text only while it still shows that text, so a recap, a restore, a
    /// dismissal or a rename that replaces it can never leave a stale line behind.
    public func roleNotices(_ role: CopilotRole) -> [String] {
        if streamingRoles.contains(role) { return pendingGrounding[role].map { [$0] } ?? [] }
        guard let record = roleNoticeRecords[role], !record.text.isEmpty, record.text == output(role) else { return [] }
        return [record.grounding, record.cutOff ? LLMOutputLimit.notice : nil].compactMap { $0 }
    }

    /// Panes whose current text stopped at the model's output limit.
    public var outputLimitRoles: Set<CopilotRole> {
        Set(CopilotRole.allCases.filter { roleNotices($0).contains(LLMOutputLimit.notice) })
    }

    /// An automatic review replaced `role`'s text: it read the whole speech it was given, and is
    /// marked cut off when it stopped at the output limit.
    func recordAutomaticReview(_ role: CopilotRole, cutOff: Bool) {
        roleNoticeRecords[role] = RoleNoticeRecord(text: output(role), grounding: nil, cutOff: cutOff)
    }

    /// Every pane's text was cleared (a speaker rename), so nothing they said still applies.
    func clearRoleNotices() {
        roleNoticeRecords = [:]
        pendingGrounding = [:]
    }
}
