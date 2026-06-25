import Foundation

/// A use-case preset: seeds the Context-notes field and tailors the AI panes via persona guidance.
public struct Preset: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// Seed text placed into the Context-notes field (editable afterward).
    public let notesTemplate: String
    /// Short instruction appended to the AI panes' system prompts to set role/tone/focus.
    public let personaGuidance: String
    public init(id: String, name: String, notesTemplate: String, personaGuidance: String) {
        self.id = id
        self.name = name
        self.notesTemplate = notesTemplate
        self.personaGuidance = personaGuidance
    }
}

/// The built-in preset catalog. Pure and testable.
public enum PresetCatalog {
    public static let none = Preset(id: "none", name: "None", notesTemplate: "", personaGuidance: "")

    public static let all: [Preset] = [
        none,
        Preset(id: "meeting", name: "Meeting",
               notesTemplate: "Meeting topic:\nAttendees:\nMy role:\nGoals/decisions needed:",
               personaGuidance: "This is a work meeting. Help the user contribute: surface decisions, "
                + "action items, and crisp talking points they can say next."),
        Preset(id: "one-on-one", name: "1:1",
               notesTemplate: "With (name/role):\nTopics to cover:\nMy goals:",
               personaGuidance: "This is a 1:1 conversation. Favor thoughtful, candid, supportive "
                + "responses and good follow-up questions."),
        Preset(id: "standup", name: "Standup",
               notesTemplate: "Team:\nMy current work:\nBlockers:",
               personaGuidance: "This is a standup. Keep suggestions to brief status-style updates "
                + "and concrete blockers/next steps."),
        Preset(id: "sales-call", name: "Sales call",
               notesTemplate: "Prospect/company:\nProduct:\nDeal stage:\nObjections expected:",
               personaGuidance: "This is a sales call. Help the user handle objections, qualify needs, "
                + "and propose next steps persuasively but honestly."),
        Preset(id: "interview-candidate", name: "Interview (candidate)",
               notesTemplate: "Role:\nCompany:\nKey JD points:\nMy relevant experience:",
               personaGuidance: "The user is the candidate in a job interview. Quick: suggest concise "
                + "first-person answers they can say aloud. Deep: give structured answers "
                + "(e.g. STAR) with reasoning."),
        Preset(id: "interview-interviewer", name: "Interview (interviewer)",
               notesTemplate: "Role being filled:\nCandidate:\nSignals to assess:",
               personaGuidance: "The user is the interviewer. Suggest probing follow-up questions "
                + "and note signals about the candidate's answers."),
        Preset(id: "technical-interview", name: "Technical interview",
               notesTemplate: "Role/stack:\nProblem area:\nMy approach:",
               personaGuidance: "This is a technical/coding interview where the user is the candidate. "
                + "Deep: provide correct, well-explained solutions with complexity analysis and code. "
                + "Quick: concise hints the user can voice while thinking aloud."),
        Preset(id: "lecture", name: "Lecture / study",
               notesTemplate: "Subject:\nTopic:\nWhat I want to understand:",
               personaGuidance: "This is a lecture or study session. Summarize key concepts, define "
                + "terms, and surface questions worth asking."),
        Preset(id: "support", name: "Customer support",
               notesTemplate: "Product:\nCustomer issue:\nKnown fixes:",
               personaGuidance: "This is a customer support call. Help the user diagnose the issue "
                + "and give clear, empathetic step-by-step guidance."),
        Preset(id: "medical", name: "Medical consult",
               notesTemplate: "Context (clinician/patient):\nConcern:\nHistory notes:",
               personaGuidance: "This is a medical consultation. Help organize symptoms, questions, "
                + "and next steps. Be factual and cautious; do not give definitive diagnoses — "
                + "defer to a professional."),
        Preset(id: "legal", name: "Legal consult",
               notesTemplate: "Matter:\nParties:\nKey facts:",
               personaGuidance: "This is a legal consultation. Help organize facts, issues, and "
                + "questions. Be factual and cautious; this is not legal advice — defer to a "
                + "qualified professional."),
        Preset(id: "brainstorm", name: "Brainstorm",
               notesTemplate: "Topic:\nConstraints:\nGoal:",
               personaGuidance: "This is a brainstorming session. Offer divergent ideas, build on "
                + "what's said, and ask generative questions.")
    ]

    /// The preset with this id, or `none` if unknown.
    public static func preset(id: String) -> Preset {
        all.first { $0.id == id } ?? none
    }
}
