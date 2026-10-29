import Foundation
import NaturalLanguage

/// A saved conversation an answer cited, in the order the answer first cites it.
public struct HistoryCitation: Sendable, Equatable, Identifiable {
    public var id: String { recordID }
    /// The excerpt numbers ("[2]") that point at this conversation.
    public let numbers: [Int]
    public let recordID: String
    public let title: String
    public let date: Date
    public init(numbers: [Int], recordID: String, title: String, date: Date) {
        self.numbers = numbers; self.recordID = recordID; self.title = title; self.date = date
    }
}

/// "Ask your history" (issue #57): a question answered from a handful of retrieved passages.
/// Only those passages — never whole conversations — go into the request, and the answer cites
/// them by number so every claim leads back to a saved conversation.
public enum HistoryQuestion {
    public static let system = """
        You answer questions about the user's own saved conversations. Use only the numbered \
        excerpts provided. After each statement, cite the excerpt it comes from in square brackets, \
        for example [1] or [2][3]. If the excerpts do not contain the answer, say that you could not \
        find it in the saved conversations, and do not guess. Be brief.
        """

    /// The prompt size Ask aims for: within Apple Intelligence's window and within the 4,096-token
    /// default context of older or low-memory Ollama servers (about 14,000 characters including the
    /// answer), which would otherwise drop the front of a longer prompt (#230).
    public static let characterBudget = 8_000
    /// An excerpt longer than this (a very long conversation has longer passages) is shortened.
    public static let maxExcerptCharacters = 1_200

    /// The request for `question`. Passages are added best first while they fit `characterBudget`;
    /// one that does not fit is skipped, so a small context window gets fewer excerpts rather than a
    /// cut-off prompt. Returns nil when no passage fits.
    public static func request(question: String, passages: [HistoryPassage], responseLanguage: String? = nil,
                               characterBudget: Int = characterBudget)
        -> (request: LLMRequest, sent: [HistoryPassage])? {
        var system = Self.system + "\n\n" + PromptData.notice
        if let responseLanguage, !responseLanguage.isEmpty { system += "\nAnswer in \(responseLanguage)." }
        let questionBlock = "Question: \(question.trimmingCharacters(in: .whitespacesAndNewlines))"
        var used = system.count + questionBlock.count
        var blocks: [String] = []
        var sent: [HistoryPassage] = []
        for passage in passages {
            let number = sent.count + 1
            // The title is written by the user or derived from the meeting, so it sits inside the
            // data fence with the excerpt; only the number, date and part are the app's own words.
            let text = HistoryRanking.clipped(passage.text, limit: maxExcerptCharacters)
            let block = "[\(number)] \(passage.date.formatted(date: .abbreviated, time: .omitted))"
                + " (\(passage.source.label.lowercased()))\n"
                + PromptData.block(passage.source == .transcript ? "transcript" : passage.source.rawValue,
                                   "Conversation: \(passage.title)\n\(text)")
            guard used + block.count + 2 <= characterBudget else { continue }
            used += block.count + 2
            blocks.append(block)
            sent.append(passage)
        }
        guard !sent.isEmpty else { return nil }
        let user = "Excerpts from my saved conversations:\n\n" + blocks.joined(separator: "\n\n")
            + "\n\n" + questionBlock
        return (LLMRequest(system: system, messages: [ChatMessage(role: "user", content: user)]), sent)
    }

    /// The conversations `answer` cites, deduplicated, in order of first citation. Numbers outside
    /// the excerpts that were sent are ignored: a model cannot invent a source.
    public static func citations(in answer: String, sent: [HistoryPassage]) -> [HistoryCitation] {
        var order: [String] = []
        var numbers: [String: [Int]] = [:]
        var scanner = answer[...]
        while let open = scanner.firstIndex(of: "[") {
            scanner = scanner[scanner.index(after: open)...]
            guard let close = scanner.firstIndex(of: "]") else { break }
            let inside = scanner[..<close]
            scanner = scanner[scanner.index(after: close)...]
            for piece in inside.split(whereSeparator: { $0 == "," || $0 == " " }) {
                // Bounds first: subtracting from an arbitrary model-written number could overflow.
                guard let number = Int(piece), number >= 1, number <= sent.count else { continue }
                let recordID = sent[number - 1].recordID
                if numbers[recordID] == nil { order.append(recordID) }
                if !(numbers[recordID]?.contains(number) ?? false) { numbers[recordID, default: []].append(number) }
            }
        }
        return order.compactMap { id in
            guard let passage = sent.first(where: { $0.recordID == id }) else { return nil }
            return HistoryCitation(numbers: numbers[id] ?? [], recordID: id, title: passage.title, date: passage.date)
        }
    }

    /// Words of the question worth matching literally: folded, at least three characters (any
    /// length for scripts without spaces), excluding known question and generic framing words.
    public static func contentTerms(_ question: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = question
        let words = tokenizer.tokens(for: question.startIndex..<question.endIndex).filter { range in
            question[range].contains { $0.isLetter || $0.isNumber }
        }
        // An unhinted single word can mean something different in another language.
        let language = words.count > 1 ? NLLanguageRecognizer.dominantLanguage(for: question) : nil
        let localized = language.flatMap { HistoryQueryVocabulary.askStopWords[$0] } ?? []
        var terms: [String] = []
        tokenizer.enumerateTokens(in: question.startIndex..<question.endIndex) { range, _ in
            let word = SessionSearch.fold(String(question[range]))
            // CJK, kana and Hangul words are short by nature; the length rule is for spaced scripts.
            let unspaced = word.unicodeScalars.contains { $0.value >= 0x2E80 }
            if word.count >= 3 || unspaced, !stopWords.contains(word), !localized.contains(word), !terms.contains(word) {
                terms.append(word)
            }
            return true
        }
        return terms
    }

    static let stopWords: Set<String> = [
        "the", "and", "for", "are", "was", "were", "what", "when", "where", "which", "who", "whom", "why",
        "how", "did", "does", "do", "has", "have", "had", "about", "with", "that", "this", "these", "those",
        "from", "into", "our", "you", "your", "they", "them", "their", "there", "any", "all", "can", "could",
        "would", "should", "will", "said", "say", "tell", "me", "we", "us", "is", "it", "of", "in", "on",
        "next", "last", "week", "plan", "plans", "meeting", "team", "thing", "things", "time"
    ]

    /// The sentence the Ask control shows when the chosen provider runs off this device, naming the
    /// destination. Nil when the answer stays on this device.
    public static func disclosure(destination: String?) -> String? {
        guard let destination else { return nil }
        return "Asking sends the matching excerpts (not whole conversations) and your question to \(destination)."
    }

    /// macOS: where an answer is generated for each AI mode. Nil for on-device modes; `.off` never asks.
    public static func destination(for mode: AIProcessingMode, label: String) -> String? {
        switch mode {
        case .off, .local, .apple: return nil
        case .cloud, .cloudAI, .openAI: return label
        }
    }
}
