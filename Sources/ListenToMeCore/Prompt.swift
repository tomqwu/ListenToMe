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
    public init(messages: [TranscriptSegment], notes: String?) {
        self.messages = messages
        self.notes = notes
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

    public static func build(context: PromptContext, action: ResponseAction) -> LLMRequest {
        let transcript = context.messages.map { seg in
            "\(seg.source == .you ? "You" : "Others"): \(seg.text)"
        }.joined(separator: "\n")

        var user = "Transcript so far:\n\(transcript)\n\n"
        if let notes = context.notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty {
            user += "Context notes from the user:\n\(notes)\n\n"
        }
        user += instruction(for: action)

        return LLMRequest(
            system: systemPrompt,
            messages: [ChatMessage(role: "user", content: user)]
        )
    }
}
