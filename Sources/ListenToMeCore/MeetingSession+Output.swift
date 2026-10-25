extension MeetingSession {
    func output(_ role: CopilotRole) -> String {
        switch role {
        case .listener: return listenerSummary
        case .quick:    return quickSuggestion
        case .deep:     return deepAnswer
        }
    }

}
