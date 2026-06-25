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
               notesTemplate: """
               Meeting: <topic>
               Date: <when>
               Attendees / roles: <who's here>
               My role: <yours>

               Agenda:
               - <item>

               Decisions needed:
               - <decision>

               Action items:
               - <owner — task>
               """,
               personaGuidance: "This is a work meeting. Help the user contribute: surface decisions, "
                + "action items, and crisp talking points they can say next."),
        Preset(id: "one-on-one", name: "1:1",
               notesTemplate: """
               1:1 with: <name / role>
               My goals for this chat:
               - <goal>

               Topics to cover:
               - <topic>

               Their recent work / context:
               - <note>
               """,
               personaGuidance: "This is a 1:1 conversation. Favor thoughtful, candid, supportive "
                + "responses and good follow-up questions."),
        Preset(id: "standup", name: "Standup",
               notesTemplate: """
               Team: <name>
               Yesterday: <what I did>
               Today: <what I'm doing>
               Blockers: <anything in my way>
               """,
               personaGuidance: "This is a standup. Keep suggestions to brief status-style updates "
                + "and concrete blockers/next steps."),
        Preset(id: "sales-call", name: "Sales call",
               notesTemplate: """
               Prospect: <person / company>
               Product / offer: <what I'm selling>
               Deal stage: <discovery / demo / negotiation>
               Their pain points: <known needs>

               Likely objections:
               - <objection>

               Desired next step: <call to action>
               """,
               personaGuidance: "This is a sales call. Help the user handle objections, qualify needs, "
                + "and propose next steps persuasively but honestly."),
        Preset(id: "interview-candidate", name: "Interview (candidate)",
               notesTemplate: """
               Role: <title>
               Company: <name>
               Interviewer: <name / role>

               Key requirements from the JD:
               - <requirement>

               My relevant experience / wins:
               - <example>

               Questions I want to ask them:
               - <question>
               """,
               personaGuidance: "The user is the candidate in a job interview. Quick: suggest concise "
                + "first-person answers they can say aloud. Deep: give structured answers "
                + "(e.g. STAR) with reasoning."),
        Preset(id: "interview-interviewer", name: "Interview (interviewer)",
               notesTemplate: """
               Role being filled: <title>
               Candidate: <name>

               Must-have signals:
               - <skill / trait>

               Areas to probe:
               - <topic>

               Notes on their answers:
               - <observation>
               """,
               personaGuidance: "The user is the interviewer. Suggest probing follow-up questions "
                + "and note signals about the candidate's answers."),
        Preset(id: "technical-interview", name: "Technical interview",
               notesTemplate: """
               Role / stack: <e.g. backend, Go>
               Problem area: <algorithms / system design / debugging>
               Constraints: <language, time limit>

               My approach / plan:
               - <step>
               """,
               personaGuidance: "This is a technical/coding interview where the user is the candidate. "
                + "Deep: provide correct, well-explained solutions with complexity analysis and code. "
                + "Quick: concise hints the user can voice while thinking aloud."),
        Preset(id: "lecture", name: "Lecture / study",
               notesTemplate: """
               Subject: <course>
               Topic: <today's topic>

               What I want to understand:
               - <question>

               Key terms to define:
               - <term>
               """,
               personaGuidance: "This is a lecture or study session. Summarize key concepts, define "
                + "terms, and surface questions worth asking."),
        Preset(id: "support", name: "Customer support",
               notesTemplate: """
               Product: <name / version>
               Customer issue: <symptom>

               Steps already tried:
               - <step>

               Known fixes / KB articles:
               - <fix>
               """,
               personaGuidance: "This is a customer support call. Help the user diagnose the issue "
                + "and give clear, empathetic step-by-step guidance."),
        Preset(id: "medical", name: "Medical consult",
               notesTemplate: """
               Context: <clinician / patient>
               Main concern: <chief complaint>

               Symptoms (onset, duration):
               - <symptom>

               Relevant history / medications:
               - <note>

               Questions to cover:
               - <question>
               """,
               personaGuidance: "This is a medical consultation. Help organize symptoms, questions, "
                + "and next steps. Be factual and cautious; do not give definitive diagnoses — "
                + "defer to a professional."),
        Preset(id: "legal", name: "Legal consult",
               notesTemplate: """
               Matter: <subject>
               Parties: <who's involved>

               Key facts / timeline:
               - <fact>

               Documents / evidence:
               - <item>

               Questions / issues to resolve:
               - <issue>
               """,
               personaGuidance: "This is a legal consultation. Help organize facts, issues, and "
                + "questions. Be factual and cautious; this is not legal advice — defer to a "
                + "qualified professional."),
        Preset(id: "brainstorm", name: "Brainstorm",
               notesTemplate: """
               Topic: <what we're exploring>
               Goal / desired outcome: <what success looks like>
               Constraints: <budget, time, scope>

               Ideas so far:
               - <idea>
               """,
               personaGuidance: "This is a brainstorming session. Offer divergent ideas, build on "
                + "what's said, and ask generative questions."),
        Preset(id: "retro", name: "Retrospective",
               notesTemplate: """
               Team / sprint: <name / number>

               What went well:
               - <highlight>

               What didn't go well:
               - <pain point>

               Action items:
               - <owner — improvement>
               """,
               personaGuidance: "This is a sprint/project retrospective. Facilitate a blameless retro: "
                + "surface themes, propose concrete improvements, and assign clear owners."),
        Preset(id: "all-hands", name: "All-hands",
               notesTemplate: """
               Presenter(s): <name / role>

               Topics / announcements:
               - <topic>

               Questions I want to ask:
               - <question>
               """,
               personaGuidance: "This is a company all-hands / town-hall. Help the user follow "
                + "announcements, summarize key updates, and draft good questions to ask."),
        Preset(id: "performance-review", name: "Performance review",
               notesTemplate: """
               Reviewee / role: <name or "me">
               Period: <timeframe>

               Wins / impact:
               - <achievement>

               Growth areas:
               - <area>

               Goals next period:
               - <goal>
               """,
               personaGuidance: "This is a performance review. Help structure balanced, specific, "
                + "evidence-based feedback and forward-looking goals. Be constructive."),
        Preset(id: "user-research", name: "User research",
               notesTemplate: """
               Participant: <name / segment>
               Product / feature: <what we're studying>

               Research goals:
               - <goal>

               Key questions:
               - <question>
               """,
               personaGuidance: "The user is the researcher in a user/customer interview. Suggest open, "
                + "non-leading follow-up questions and capture signals and quotes, not solutions."),
        Preset(id: "negotiation", name: "Negotiation",
               notesTemplate: """
               Counterparty: <person / company>

               What I want:
               - <objective>

               My limits / BATNA:
               - <walk-away point>

               Their likely position:
               - <expected stance>
               """,
               personaGuidance: "This is a deal/terms negotiation. Help the user advance their "
                + "interests, find trades, and stay calm and principled. Never advise anything deceptive."),
        Preset(id: "journal", name: "Daily journal",
               notesTemplate: """
               Date: <when>
               Focus today: <main intention>

               Wins:
               - <win>

               Challenges:
               - <challenge>

               Tomorrow:
               - <plan>
               """,
               personaGuidance: "This is a personal reflection / voice note. Help organize thoughts, "
                + "surface patterns over time, and suggest gentle next steps.")
    ]

    /// The preset with this id, or `none` if unknown.
    public static func preset(id: String) -> Preset {
        all.first { $0.id == id } ?? none
    }
}
