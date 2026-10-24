import Foundation

extension MeetingSession {
    /// One-line notes a pane shows under its title, in order: which part of the conversation the
    /// answer read when it could not read all of it (issue #114), then whether the answer stopped at
    /// the model's output limit (issue #215). Empty when there is nothing to say.
    public func roleNotices(_ role: CopilotRole) -> [String] {
        var notices: [String] = []
        if let grounding = groundingNotices[role] { notices.append(grounding) }
        if outputLimitRoles.contains(role) { notices.append(LLMOutputLimit.notice) }
        return notices
    }

    /// An automatic review replaced `role`'s text: the previous answer's grounding line no longer
    /// describes it, and the cut-off mark follows the review that was just applied.
    func recordAutomaticReview(_ role: CopilotRole, cutOff: Bool) {
        groundingNotices[role] = nil
        if cutOff { outputLimitRoles.insert(role) } else { outputLimitRoles.remove(role) }
    }

    /// Every pane's text was cleared (a speaker rename), so nothing they said still applies.
    func clearRoleNotices() {
        groundingNotices = [:]
        outputLimitRoles = []
    }
}
