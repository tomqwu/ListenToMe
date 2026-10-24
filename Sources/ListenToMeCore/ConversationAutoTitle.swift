import Foundation
import NaturalLanguage

/// Names a conversation that still has its default name once it is saved (#221). The title comes
/// from, in order: the summary the conversation already has (no model call); the summary provider
/// the user already chose, with a tiny bounded prompt; on-device NaturalLanguage keywords.
public enum ConversationAutoTitle {
    /// Final-transcript words before a conversation is worth naming.
    public static let minimumWords = 30
    public static let maximumWords = 6
    public static let maximumCharacters = 60
    /// Scripts written without spaces (Chinese, Japanese, Thai) are limited by characters instead.
    static let maximumUnspacedCharacters = 20
    /// How much of the transcript's start the model sees.
    public static let headCharacters = 2_000
    /// The model's answer is cut off here; a title is a few words.
    static let maximumResponseCharacters = 400
    /// A later save refines an automatic title once the transcript has grown this much.
    static let refineFactor = 3
    static let refineMinimumGrowth = 150

    public enum Origin: String, Sendable, Equatable { case summary, model, keywords }

    // MARK: When

    /// The replace rule. A typed or calendar title is never replaced. A default name is replaced
    /// once there are enough words. An automatic title is refined at most once, after the
    /// conversation has grown several times over.
    public static func shouldName(state: ConversationTitleState, title: String, words: Int) -> Bool {
        guard words >= minimumWords else { return false }
        switch state.source {
        case .user, .calendar: return false
        case .placeholder:
            if let tried = state.attemptedWords, words < tried * 2, words - tried < retryMinimumGrowth { return false }
            return ConversationTitle.isPlaceholder(title)
        case .automatic:
            guard state.refined != true, let before = state.automaticWords else { return false }
            return words >= before * refineFactor && words - before >= refineMinimumGrowth
        }
    }

    /// After naming produced nothing, it is tried again only once the transcript has doubled or
    /// grown by this many words, not on every Save and return to the app.
    static let retryMinimumGrowth = 100

    /// The state to save with a title just named automatically.
    public static func namedState(after state: ConversationTitleState, words: Int) -> ConversationTitleState {
        .automatic(words: words, refined: state.source == .automatic)
    }

    /// The state to save when naming produced nothing: a default name remembers how long the
    /// transcript was, and a refinement that failed is not tried again.
    public static func attemptedState(after state: ConversationTitleState, words: Int) -> ConversationTitleState {
        var next = state
        if state.source == .automatic { next.refined = true } else { next.attemptedWords = words }
        return next
    }

    /// Whether Load/Import from Calendar may name the conversation after its meeting: over a
    /// default name or an automatic one, never over a title the user typed.
    public static func calendarMayReplace(state: ConversationTitleState, title: String) -> Bool {
        switch state.source {
        case .automatic: return true
        case .placeholder: return ConversationTitle.isPlaceholder(title)
        case .user, .calendar: return false
        }
    }

    /// Whether naming may ask the summary model without a request from the user: only when it runs
    /// on this device or on the user's own Ollama. With Ollama Cloud, a cloud AI service or an
    /// OpenAI-compatible server, a conversation without a summary is named from on-device
    /// keywords, so Stop sends nothing for a title.
    public static func mayAskModel(_ mode: AIProcessingMode) -> Bool {
        mode == .apple || mode == .local
    }

    /// Words in `text`, in any script.
    public static func wordCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in count += 1; return true }
        return count
    }

    // MARK: Generating

    /// The title for a conversation, or nil when it has too few words or naming was cancelled.
    /// `provider` is the one the user chose for summaries, or nil when AI is off or unavailable;
    /// a failure or an unusable answer falls back to keywords.
    public static func title(transcript: String, summary: String, language: String?,
                             provider: (any LLMProvider)?) async -> (title: String, origin: Origin)? {
        guard wordCount(transcript) >= minimumWords else { return nil }
        if let named = fromSummary(summary, language: language) { return (named, .summary) }
        if let provider, let raw = try? await ask(provider, transcript: transcript, language: language),
           let named = sanitize(raw, language: language) {
            return (named, .model)
        }
        guard !Task.isCancelled, let named = keywords(transcript, language: language) else { return nil }
        return (named, .keywords)
    }

    /// The tiny bounded request: the head of the transcript, fenced as data.
    public static func request(transcript: String, language: String?) -> LLMRequest {
        let head = String(transcript.prefix(headCharacters))
        let languageName = language.flatMap(Self.languageName) ?? "the same language as the transcript"
        let system = "You name conversations. Reply with only a title of at most \(maximumWords) words, "
            + "in \(languageName), naming the conversation's main topic. "
            + "No quotes, no emoji, no trailing punctuation, no explanation. " + PromptData.notice
        return LLMRequest(system: system, messages: [ChatMessage(role: "user", content: PromptData.block("transcript", head))])
    }

    static func ask(_ provider: any LLMProvider, transcript: String, language: String?) async throws -> String {
        var answer = ""
        for try await delta in provider.stream(request(transcript: transcript, language: language)) {
            try Task.checkCancellation()
            answer += delta
            if answer.count >= maximumResponseCharacters { break }
        }
        return answer
    }

    /// "English", "French"… for the prompt.
    static func languageName(_ identifier: String) -> String? {
        guard let code = languageCode(identifier) else { return nil }
        return Locale(identifier: "en").localizedString(forLanguageCode: code)
    }

    static func languageCode(_ identifier: String) -> String? {
        let code = Locale(identifier: identifier).language.languageCode?.identifier
        return code?.isEmpty == false ? code : nil
    }

    // MARK: Cleaning a model's answer

    static let labels = ["title", "titre", "título", "titolo", "titel", "標題", "标题", "タイトル", "제목", "название"]
    static let junk: Set<String> = ["untitled", "title", "conversation", "meeting", "new conversation", "n/a",
                                    "none", "unknown", "no title", "transcript", "summary"]
    static let refusals = ["i'm sorry", "i am sorry", "sorry,", "i can't", "i cannot", "as an ai", "i'm unable",
                           "i am unable", "unfortunately"]

    /// Words that mark a chatty opener ("Sure, here is a short title for this conversation:").
    static let openers = ["here is", "here's", "title for", "a title", "short title", "suggested title"]

    /// A model's answer as a title: the first line, without reasoning blocks, Markdown, quotes,
    /// emoji, a "Title:" label or chatty opener, or trailing punctuation, at most `maximumWords`
    /// words. When the first line is only a label, the next line is the title. Nil for an empty,
    /// generic or refusing answer, or one clearly in another language than the conversation's.
    public static func sanitize(_ raw: String, language: String?) -> String? {
        let lines = withoutReasoning(raw).components(separatedBy: .newlines).map(cleanLine).filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        if refusals.contains(where: { first.lowercased().hasPrefix($0) }) { return nil }
        var text = trimmed(stripLabel(first))
        if text.isEmpty, lines.count > 1 { text = trimmed(stripLabel(lines[1])) }
        guard let shortened = limited(text), shortened.filter(\.isLetter).count >= 2,
              !junk.contains(shortened.lowercased()), !ConversationTitle.isPlaceholder(shortened),
              !isOtherLanguage(shortened, than: language) else { return nil }
        return capitalized(shortened)
    }

    /// Without `<think>…</think>` blocks and stray reasoning tags some local models print first.
    static func withoutReasoning(_ text: String) -> String {
        text.replacingOccurrences(of: #"<think>[\s\S]*?</think>"#, with: "\n",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</?think>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
    }

    /// One line without emoji, Markdown emphasis or quotes, with single spaces.
    static func cleanLine(_ line: String) -> String {
        String(line.unicodeScalars.filter { !isEmoji($0) && !"*_`#\"“”„«»「」『』".unicodeScalars.contains($0) })
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Drops "Title:" in front of the answer, and everything up to the last colon of a chatty
    /// opener such as "Sure, here is a short title for this conversation:".
    static func stripLabel(_ text: String) -> String {
        let isColon: (Character) -> Bool = { $0 == ":" || $0 == "：" }
        if let colon = text.firstIndex(where: isColon) {
            let label = text[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            if labels.contains(where: { label == $0 || label.hasSuffix(" " + $0) }) {
                return String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        if let colon = text.lastIndex(where: isColon), openers.contains(where: { text[..<colon].lowercased().contains($0) }) {
            return String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    static func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        if properties.isEmojiPresentation { return true }
        if properties.isEmoji, scalar.value > 0x238C { return true }   // pictographs, not digits or #
        return scalar.value == 0xFE0F || scalar.value == 0x200D || (0x1F3FB...0x1F3FF).contains(scalar.value)
    }

    static let edgePunctuation = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespaces)
        .subtracting(CharacterSet(charactersIn: "&+()"))

    /// Without leading and trailing punctuation or quotes; a closing bracket stays only if opened.
    static func trimmed(_ text: String) -> String {
        var result = text.trimmingCharacters(in: edgePunctuation.union(CharacterSet(charactersIn: "'‘’")))
        if result.hasSuffix(")"), !result.contains("(") { result.removeLast() }
        if result.hasPrefix("("), !result.contains(")") { result.removeFirst() }
        return result.trimmingCharacters(in: edgePunctuation)
    }

    /// At most `maximumWords` words and `maximumCharacters`, cut only between words. A script written
    /// without spaces is measured in characters, `maximumUnspacedCharacters` overall. A single word
    /// longer than the limit is not cut in half: nil, so keywords name the conversation instead.
    static func limited(_ text: String) -> String? {
        if isUnspacedScript(text) { return trimmed(String(text.prefix(maximumUnspacedCharacters))) }
        let words = text.split(separator: " ")
        guard let first = words.first, first.count <= maximumCharacters else { return nil }
        var kept = words.prefix(maximumWords).joined(separator: " ")
        while kept.count > maximumCharacters, let space = kept.lastIndex(of: " ") { kept = String(kept[..<space]) }
        return trimmed(kept)
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// True only when the title is long enough to tell and is confidently another language.
    static func isOtherLanguage(_ text: String, than language: String?) -> Bool {
        guard let expected = language.flatMap(languageCode), text.filter(\.isLetter).count >= 12 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (detected, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.9 else { return false }
        return detected.rawValue.split(separator: "-").first.map(String.init) != expected
    }

    // MARK: From the summary

    /// The summary's first sentence when it is short enough, otherwise its key phrases. Headings
    /// ("Decisions", "Next steps") are section labels, not topics, and are skipped.
    public static func fromSummary(_ summary: String, language: String?) -> String? {
        let prose = summary.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map(plainLine)
            .filter { !$0.isEmpty }
        guard let first = prose.first else { return nil }
        if let sentence = firstSentence(first), wordCount(sentence) <= maximumWords,
           let named = sanitize(sentence, language: language) {
            return named
        }
        return keywords(prose.joined(separator: "\n"), language: language)
    }

    /// A Markdown line as plain text: no bullet, number, quote marker or emphasis.
    static func plainLine(_ line: String) -> String {
        var text = Substring(line)
        while let first = text.first, "-*+>•".contains(first) { text = text.dropFirst().drop(while: { $0 == " " }) }
        if let dot = text.firstIndex(where: { $0 == "." || $0 == ")" }), dot > text.startIndex,
           text[..<dot].allSatisfy(\.isNumber) {
            text = text[text.index(after: dot)...].drop(while: { $0 == " " })
        }
        return String(text).replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
    }

    static func firstSentence(_ text: String) -> String? {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentence: String?
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return false
        }
        return sentence
    }

}

/// On-device keywords: the fallback when there is no summary and no usable model answer.
extension ConversationAutoTitle {

    /// Nouns too general to name a conversation by, in the languages most people record in.
    static let fillerNouns: Set<String> = [
        "thing", "things", "lot", "lots", "way", "ways", "time", "times", "kind", "bit", "stuff", "guy", "guys",
        "people", "yeah", "okay", "ok", "um", "uh", "today", "tomorrow", "yesterday", "week", "day", "days",
        "something", "anything", "everything", "nothing", "question", "questions", "point", "idea", "sort",
        "part", "end", "minute", "minutes", "hour", "moment", "chose", "cosa", "cosas", "ding", "sache",
        "coisa", "vez", "fois", "mal", "speaker", "transcript", "meeting", "conversation", "call", "microphone",
    ]

    /// The text's most frequent noun phrases, or its most frequent words where the language has no
    /// part-of-speech model, as a short title. Runs on this device.
    public static func keywords(_ text: String, language: String?) -> String? {
        let phrases = nounPhrases(text, language: language)
        let picked: [String]
        if phrases.isEmpty {
            picked = Array(frequentWords(text).prefix(3))
        } else {
            var chosen: [[String]] = []
            for phrase in phrases where chosen.count < 2 {
                let words = chosen.flatMap { $0 }.count + phrase.count
                guard words <= maximumWords, !chosen.contains(where: { !Set($0).isDisjoint(with: phrase) }) else { continue }
                chosen.append(phrase)
            }
            picked = chosen.map { $0.joined(separator: " ") }
        }
        guard !picked.isEmpty else { return nil }
        let unspaced = isUnspacedScript(picked.joined())
        let joined = picked.joined(separator: unspaced ? "、" : ", ")
        return sanitize(joined, language: nil)
    }

    /// Phrases of adjectives and nouns ending in a noun, best first: scored by how often their nouns
    /// occur, so the topic the conversation keeps returning to wins.
    static func nounPhrases(_ text: String, language: String?) -> [[String]] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        if let code = language.flatMap(languageCode) {
            tagger.setLanguage(NLLanguage(rawValue: code), range: text.startIndex..<text.endIndex)
        }
        var phrases: [[String]] = []
        var current: [(word: String, isNoun: Bool)] = []
        func close() {
            while let last = current.last, !last.isNoun { current.removeLast() }
            let words = current.map(\.word)
            if !words.isEmpty, words.count <= 3 { phrases.append(words) }
            current = []
        }
        // Punctuation is kept so a phrase never runs across a comma or into the next sentence.
        let options: NLTagger.Options = [.omitWhitespace, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: options) { tag, range in
            let word = String(text[range])
            let isFiller = fillerNouns.contains(word.lowercased())
            switch tag {
            case .noun? where !isFiller && word.count > 1: current.append((word, true))
            case .adjective? where !current.contains(where: \.isNoun): current.append((word, false))
            default: close()
            }
            return true
        }
        close()
        var nounCounts: [String: Int] = [:]
        for phrase in phrases { for word in phrase { nounCounts[word.lowercased(), default: 0] += 1 } }
        var seen = Set<String>()
        let unique = phrases.filter { seen.insert($0.joined(separator: " ").lowercased()).inserted }
        func score(_ phrase: [String]) -> Int {
            phrase.map { nounCounts[$0.lowercased()] ?? 0 }.reduce(0, +) * 10 + phrase.count
        }
        let ranked = unique.enumerated().sorted { lhs, rhs in
            let left = score(lhs.element), right = score(rhs.element)
            return left != right ? left > right : lhs.offset < rhs.offset
        }.map(\.element)
        // A topic is something said more than once; if nothing repeats, the first best phrase stands alone.
        let repeated = ranked.filter { phrase in phrase.contains { (nounCounts[$0.lowercased()] ?? 0) >= 2 } }
        return repeated.isEmpty ? Array(ranked.prefix(1)) : repeated
    }

    /// Repeated content words, for languages without a part-of-speech model. Without one, short
    /// words are mostly articles and pronouns, and words written only in hiragana are particles and
    /// endings, so both are left out; longer and more frequent words rank first.
    static func frequentWords(_ text: String) -> [String] {
        let unspaced = isUnspacedScript(text)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var counts: [String: (count: Int, first: Int)] = [:]
        var index = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            let isContent = word.count >= (unspaced ? 2 : 4) && word.contains(where: \.isLetter)
                && !word.unicodeScalars.allSatisfy({ (0x3040...0x309F).contains($0.value) })
                && !fillerNouns.contains(word.lowercased())
            if isContent { counts[word, default: (0, index)].count += 1 }
            index += 1
            return true
        }
        func rank(_ entry: (key: String, value: (count: Int, first: Int))) -> Int { entry.value.count * 100 + entry.key.count }
        return counts.filter { $0.value.count > 1 }
            .sorted { rank($0) != rank($1) ? rank($0) > rank($1) : $0.value.first < $1.value.first }
            .map(\.key)
    }

    /// Mostly Chinese, Japanese, Thai, Lao, Khmer or Myanmar letters: scripts written without spaces
    /// between words, so lengths are counted in characters. Korean uses spaces and is not included.
    static func isUnspacedScript(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        guard !letters.isEmpty else { return false }
        let ranges: [ClosedRange<UInt32>] = [0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                                             0x20000...0x2FA1F, 0x0E00...0x0EFF, 0x1780...0x17FF, 0x1000...0x109F]
        let unspaced = letters.filter { scalar in ranges.contains { $0.contains(scalar.value) } }
        return unspaced.count * 3 >= letters.count
    }
}
