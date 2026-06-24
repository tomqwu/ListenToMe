import Foundation

/// A provider-agnostic chat message.
public struct ChatMessage: Sendable, Equatable {
    public let role: String   // "system" | "user" | "assistant"
    public let content: String
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// What the listener wants from the assistant right now.
public enum ResponseAction: Sendable, Equatable {
    case answerQuestion   // hotkey / "What should I answer?"
    case recap            // "Recap so far"
    case followUp         // "Suggest a follow-up"
    case proactive        // auto-detected incoming question
}

/// The conversational context handed to the model.
public struct PromptContext: Sendable, Equatable {
    public let messages: [TranscriptSegment]
    public let notes: String?
    /// The Listener pane's rolling summary, fed into Quick/Deep prompts as condensed grounding.
    public let summary: String?
    public init(messages: [TranscriptSegment], notes: String?, summary: String? = nil) {
        self.messages = messages
        self.notes = notes
        self.summary = summary
    }
}

/// A provider-agnostic request: a system prompt plus chat messages.
public struct LLMRequest: Sendable, Equatable {
    public let system: String
    public let messages: [ChatMessage]
    public init(system: String, messages: [ChatMessage]) {
        self.system = system
        self.messages = messages
    }
}

/// Builds the system prompt and user message for a given context + action.
public enum PromptBuilder {
    public static let systemPrompt = """
    You are a real-time meeting copilot for the user, labeled "You". The transcript labels remote \
    participants as "Others". Give the user something they can say or act on immediately.
    Be concise and conversational. No preamble, no "As an AI", no restating the question, no \
    meta-commentary. Prefer 1-3 short sentences or a tight bullet list. If a question was asked, \
    answer it directly first.
    """

    public static let listenerSystemPrompt = """
    You are a real-time meeting listener. Given a conversation transcript, produce:
    (a) a 1-3 sentence rolling summary of what has been discussed so far, and
    (b) a short bulleted list of any open questions or action items identified.
    Be brief and factual. No preamble, no meta-commentary.
    """

    public static let deepSystemPrompt = """
    You are a thorough meeting copilot for the user, labeled "You". The transcript labels remote \
    participants as "Others". Provide a detailed, well-reasoned answer grounded in the transcript \
    and any notes provided. Use longer-form explanation where helpful; include code blocks when \
    relevant. Be thorough and precise — depth is valued over brevity here.
    """

    private static func instruction(for action: ResponseAction) -> String {
        switch action {
        case .answerQuestion, .proactive:
            return "Based on the transcript, give the user the best answer or response to say next."
        case .recap:
            return "Give a brief recap (summary) of the conversation so far."
        case .followUp:
            return "Suggest one good follow-up question the user could ask next."
        }
    }

    private static func deepInstruction(for action: ResponseAction) -> String {
        switch action {
        case .answerQuestion, .proactive:
            return "Based on the transcript, provide a detailed and well-reasoned answer the user can draw on."
        case .recap:
            return "Give a thorough recap of the conversation so far, covering all key points and nuances."
        case .followUp:
            return "Suggest a thoughtful follow-up question the user could ask, with reasoning for why it matters."
        }
    }

    private static func buildUserMessage(context: PromptContext, instruction: String) -> String {
        let transcript = context.messages.map { seg in
            "\(seg.source == .you ? "You" : "Others"): \(seg.text)"
        }.joined(separator: "\n")

        var user = "Transcript so far:\n\(transcript)\n\n"
        if let summary = context.summary, !summary.trimmingCharacters(in: .whitespaces).isEmpty {
            user += "Meeting summary so far (from the listener):\n\(summary)\n\n"
        }
        if let notes = context.notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
            user += "Context notes from the user:\n\(notes)\n\n"
        }
        user += instruction
        return user
    }

    public static func build(context: PromptContext, action: ResponseAction) -> LLMRequest {
        let user = buildUserMessage(context: context, instruction: instruction(for: action))
        return LLMRequest(
            system: systemPrompt,
            messages: [ChatMessage(role: "user", content: user)]
        )
    }

    /// Listener builder: rolling summary + open questions/action items.
    public static func buildListener(context: PromptContext) -> LLMRequest {
        let transcript = context.messages.map { seg in
            "\(seg.source == .you ? "You" : "Others"): \(seg.text)"
        }.joined(separator: "\n")

        var user = "Transcript so far:\n\(transcript)\n\n"
        if let notes = context.notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
            user += "Context notes from the user:\n\(notes)\n\n"
        }
        user += "Provide the rolling summary and list of open questions or action items."

        return LLMRequest(
            system: listenerSystemPrompt,
            messages: [ChatMessage(role: "user", content: user)]
        )
    }

    /// Deep builder: detailed, well-reasoned answer for complex / coding questions.
    public static func buildDeep(context: PromptContext, action: ResponseAction) -> LLMRequest {
        let user = buildUserMessage(context: context, instruction: deepInstruction(for: action))
        return LLMRequest(
            system: deepSystemPrompt,
            messages: [ChatMessage(role: "user", content: user)]
        )
    }
}
