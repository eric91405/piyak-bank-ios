import Foundation

struct PiyakChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable { case user, piyak }
    enum Source: Sendable { case conversation, groundedConversation, memory, records, help }
    let id: UUID
    let role: Role
    var text: String
    var source: Source
    var isComplete: Bool

    init(id: UUID = UUID(), role: Role, text: String,
         source: Source = .conversation, isComplete: Bool = true) {
        self.id = id
        self.role = role
        self.text = text
        self.source = source
        self.isComplete = isComplete
    }

    var generatedText: String {
        source == .groundedConversation
            ? text.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
            : text
    }
}

/// Small, explicit user statements only. Assistant prose is never a source of facts.
/// This is retrieval for names/preferences, not a generated summary or an AI substitute.
struct PiyakUserMemory: Equatable, Sendable {
    var name: String?
    var likes: [String] = []

    static func extract(from messages: [PiyakChatMessage]) -> Self {
        var memory = Self()
        let namePattern = #"(?:내|제)\s*이름(?:은|이)\s*([가-힣A-Za-z]{1,12}?)(?:이고|이야|입니다|이에요|예요|야|고|[.!]|$)"#
        let preferencePattern = #"(?:^|[.!?,\n]|고\s+|그리고\s+)\s*(?:나는\s+|난\s+|저는\s+|전\s+)?([가-힣A-Za-z][가-힣A-Za-z0-9 ]{0,20}?)(?:을|를)\s*(좋아해(?:요)?|좋아합니다|좋아하지\s*않아(?:요)?|싫어해(?:요)?|(?:이제\s*)?안\s*좋아해(?:요)?)"#
        let englishNamePattern = #"(?i)\bmy name is\s+([A-Za-z][A-Za-z -]{0,25}?)(?=[.!?,\n]|$)"#
        let englishPreferencePattern = #"(?i)(?:^|[.!?\n]\s*)I\s+(like|love|enjoy|don't like|do not like)\s+([A-Za-z][A-Za-z -]{0,40}?)(?=[.!?,\n]|$)"#
        for message in messages where message.role == .user {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Do not turn quoted examples, hypothetical instructions, or questions into facts.
            guard !["만약", "가정", "예시", "예를", "라고 말", "라고말", "라고 해", "라고해", "인 척", "인척", "\"", "“", "”", "‘", "’",
                    "if my name", "suppose", "for example", "pretend", "say that"]
                .contains(where: text.lowercased().contains), !text.hasSuffix("?"),
                  !(text.hasPrefix("'") && text.hasSuffix("'")) else { continue }
            let names = captures(namePattern, in: text)
            if let name = names.last?.first, !name.contains("아니") { memory.name = name }
            let withoutName = text.replacingOccurrences(of: namePattern, with: "", options: .regularExpression)
            for parts in captures(preferencePattern, in: withoutName) where parts.count == 2 {
                let preference = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preference.isEmpty, !preference.contains("이름"), !preference.contains("너는") else { continue }
                if ["않아", "싫어", "안"].contains(where: parts[1].contains) { memory.likes.removeAll { $0 == preference } }
                else if !memory.likes.contains(preference) { memory.likes.append(preference) }
            }
            if let name = captures(englishNamePattern, in: text).last?.first,
               !name.lowercased().hasPrefix("not ") { memory.name = name }
            for parts in captures(englishPreferencePattern, in: text) where parts.count == 2 {
                let preference = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if parts[0].lowercased().contains("not") || parts[0].lowercased().contains("n't") {
                    memory.likes.removeAll { $0.caseInsensitiveCompare(preference) == .orderedSame }
                } else if !memory.likes.contains(where: { $0.caseInsensitiveCompare(preference) == .orderedSame }) {
                    memory.likes.append(preference)
                }
            }
        }
        memory.likes = Array(memory.likes.suffix(3))
        return memory
    }

    static func asksForRecall(_ text: String) -> Bool {
        let english = text.lowercased()
        let compact = text.filter { !$0.isWhitespace }
        let englishRecall = (english.contains("remember") && ["name", "like", "enjoy", "activity", "activities", "preference"].contains(where: english.contains)) ||
            ["what is my name", "what's my name", "what do i like", "what did i say i like", "what activity did i say i like"].contains(where: english.contains)
        return englishRecall ||
            (compact.contains("기억") && ["이름", "좋아", "취향", "활동"].contains(where: compact.contains)) ||
            ["내이름뭐", "내이름이뭐", "내가뭘좋아", "내가무엇을좋아"].contains(where: compact.contains)
    }

    static func alsoAsksForSuggestion(_ text: String) -> Bool {
        ["추천", "할 만", "할만", "뭘 할", "뭐 할", "어떻게", "suggest", "recommend", "what should i do"].contains(where: text.lowercased().contains)
    }

    var recallText: String {
        var lines: [String] = []
        if let name { lines.append("네 이름은 **\(name)**라고 알려줬어.") }
        if !likes.isEmpty { lines.append("**\(likes.joined(separator: ", "))**을 좋아한다고 했지.") }
        if lines.isEmpty {
            return "아직 직접 알려 준 이름이나 좋아하는 활동을 찾지 못했어. ‘내 이름은 …야’, ‘…을 좋아해’처럼 알려 주면 이 대화에서 기억할게."
        }
        return lines.joined(separator: " ")
    }

    var reference: String {
        "사용자가 직접 말한 이름: \(name ?? "확인된 정보 없음").\n사용자가 좋아한다고 말한 활동: \(likes.isEmpty ? "확인된 정보 없음" : likes.joined(separator: ", "))."
    }

    func recommendationFocus(for text: String) -> String? {
        guard !["말고", "제외", "다른", "instead", "other", "except"].contains(where: text.lowercased().contains) else { return nil }
        return likes.last
    }

    private static func captures(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }
}

enum PiyakRecordPeriod: String, CaseIterable, Sendable {
    case today = "오늘", yesterday = "어제", thisWeek = "이번 주"
    case lastWeek = "지난주", thisMonth = "이번 달", lastMonth = "지난달"

    func days(at now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let interval: DateInterval?
        switch self {
        case .today: return [today]
        case .yesterday:
            return calendar.date(byAdding: .day, value: -1, to: today).map { [$0] } ?? []
        case .thisWeek: interval = calendar.dateInterval(of: .weekOfYear, for: today)
        case .thisMonth: interval = calendar.dateInterval(of: .month, for: today)
        case .lastWeek:
            interval = calendar.date(byAdding: .day, value: -7, to: today)
                .flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }
        case .lastMonth:
            interval = calendar.date(byAdding: .month, value: -1, to: today)
                .flatMap { calendar.dateInterval(of: .month, for: $0) }
        }
        guard let interval else { return [] }
        var day = interval.start
        var days: [Date] = []
        while day < interval.end, day <= today, days.count < 32 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return days
    }
}

enum PiyakChatIntent: Equatable, Sendable {
    case conversation
    case balance
    case earnings(PiyakRecordPeriod)
    case wage
    case choosePeriod
    case help
}

enum PiyakConversation {
    static let maximumInput = 800

    enum ResponseQualityIssue: Equatable, Sendable { case excessiveLength, repeatedSentence, repeatedPhrase }

    static func responseQualityIssue(_ answer: String) -> ResponseQualityIssue? {
        guard answer.count < 800 else { return .excessiveLength }
        let sentences = PiyakChatFormatting.plain(answer)
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n。！？"))
        var counts: [String: Int] = [:]
        for sentence in sentences {
            let key = normalizedAnswer(sentence)
            guard key.count >= 4 else { continue }
            counts[key, default: 0] += 1
            if counts[key, default: 0] >= 3 { return .repeatedSentence }
        }
        // Degenerate decoding can repeat a phrase indefinitely without ending a sentence.
        // This bounded token check avoids an unbounded/backtracking regular expression.
        let words = PiyakChatFormatting.plain(answer).lowercased().split {
            $0.isWhitespace || $0.isPunctuation
        }.map(String.init)
        if words.count >= 12 {
            for width in 4...min(8, words.count / 3) {
                for start in 0...(words.count - width * 3) {
                    let first = words[start..<(start + width)]
                    if first.elementsEqual(words[(start + width)..<(start + width * 2)]),
                       first.elementsEqual(words[(start + width * 2)..<(start + width * 3)]) {
                        return .repeatedPhrase
                    }
                }
            }
        }
        return nil
    }

    /// Only genuine conversational exchanges belong in the language-model transcript.
    /// Deterministic record/help/memory replies are UI output, not language examples.
    static func modelContext(_ messages: [PiyakChatMessage]) -> [PiyakChatMessage] {
        var exchanges: [[PiyakChatMessage]] = []
        var pending: PiyakChatMessage?
        for message in messages {
            if message.role == .user { pending = message; continue }
            defer { pending = nil }
            guard var user = pending, message.isComplete,
                  message.source == .conversation || message.source == .groundedConversation else { continue }
            var reply = message
            user.text = String(user.text.prefix(400))
            reply.text = String(message.generatedText.prefix(350))
            reply.source = .conversation
            guard !reply.text.isEmpty else { continue }
            exchanges.append([user, reply])
        }
        return exchanges.suffix(2).flatMap { $0 }
    }

    static func hasMeaningfulInput(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0) || $0.properties.isEmojiPresentation ||
                ($0.value > 0x7F && $0.properties.isEmoji)
        }
    }

    static func isUnrequestedRepeat(_ answer: String, of previous: String?, request: String) -> Bool {
        guard let previous else { return false }
        let compact = request.lowercased().filter { !$0.isWhitespace }
        let explicitlyAvoidsRepeat = ["반복하지", "다르게", "donotrepeat", "don'trepeat", "notthesame"]
            .contains(where: compact.contains)
        let requestsRepeat = ["다시말해", "다시써줘", "그대로말", "그대로보여", "반복해줘", "repeatthat", "repeatit",
                              "repeatyour", "repeatthe", "saythatagain", "sayitagain", "sameansweragain"]
            .contains(where: compact.contains)
        guard explicitlyAvoidsRepeat || !requestsRepeat else { return false }
        let candidate = normalizedAnswer(answer)
        return !candidate.isEmpty && candidate == normalizedAnswer(previous)
    }

    private static func normalizedAnswer(_ text: String) -> String {
        let plain = PiyakChatFormatting.plain(text).precomposedStringWithCanonicalMapping.lowercased()
        return String(String.UnicodeScalarView(plain.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0.properties.isEmojiPresentation
        }))
    }

    /// Match explicit record questions, not individual syllables such as 벌 in 벌써.
    static func intent(_ raw: String, previous: PiyakChatIntent? = nil) -> PiyakChatIntent {
        let text = raw.lowercased().filter { !$0.isWhitespace }
        let period = PiyakRecordPeriod.allCases.first {
            text.contains($0.rawValue.filter { !$0.isWhitespace })
        }
        let query = ["얼마벌", "얼마나벌", "얼마야", "얼마예", "얼마인", "얼만", "몇", "알려", "보여", "확인", "계산해", "정산해", "조회"]
            .contains(where: text.contains)
        if ["사용법", "도움말", "뭘할수", "어떻게써", "어떻게사용"].contains(where: text.contains) {
            return .help
        }
        let balanceQuery = ["얼마야", "얼마예", "얼마인", "얼마있", "얼마남", "얼마나있", "얼마나남", "얼마나쌓",
                            "몇포인트", "포인트몇", "남았", "쌓였", "잔액", "보유", "알려", "보여", "확인"]
            .contains(where: text.contains)
        if text == "잔액" || text == "포인트" || text == "보유포인트" ||
            ((text.contains("잔액") || text.contains("포인트")) && balanceQuery) {
            return .balance
        }
        if text == "시급" || (text.contains("시급") && query &&
            !["바꿔", "변경", "올려", "얼마나힘"].contains(where: text.contains)) {
            return .wage
        }
        let earningsWords = ["수익", "정산", "급여", "번돈", "벌었", "벌고", "벌었는", "일한돈"]
        let asksEarnings = earningsWords.contains(where: text.contains) && query
        let shortRecordLabel = period.map { period in
            let label = period.rawValue.filter { !$0.isWhitespace }
            return ["수익", "수익?", "정산", "정산?", "급여", "급여?"].contains { text == label + $0 }
        } ?? false
        if asksEarnings || shortRecordLabel {
            return period.map(PiyakChatIntent.earnings) ?? .choosePeriod
        }
        // A bare follow-up inherits only the immediately preceding successful record query.
        let followsRecord: Bool
        switch previous {
        case .earnings?, .choosePeriod?: followsRecord = true
        default: followsRecord = false
        }
        if followsRecord, let period, text.count < 18 {
            let suffixes = ["는?", "은?", "도?", "는", "은", "도", "얼마야?", "얼마야", "알려줘", "알려줘?"]
            let clean = text.replacingOccurrences(of: "그럼", with: "")
                .replacingOccurrences(of: "그러면", with: "")
            let periodText = period.rawValue.filter { !$0.isWhitespace }
            if clean == periodText || suffixes.contains(where: { clean == periodText + $0 }) {
                return .earnings(period)
            }
        }
        return .conversation
    }

    /// Keep complete recent exchanges together. Failed, canceled, and half-written replies
    /// never become the model's asserted history. Native transcript roles are preserved.
    static func context(_ messages: [PiyakChatMessage], characterBudget: Int = 1_600) -> [PiyakChatMessage] {
        var exchanges: [[PiyakChatMessage]] = []
        var pending: PiyakChatMessage?
        for message in messages {
            if message.role == .user {
                pending = message
            } else if let user = pending, message.isComplete, !message.text.isEmpty {
                exchanges.append([user, message])
                pending = nil
            }
        }
        var selected: [PiyakChatMessage] = []
        var remaining = max(0, characterBudget)
        for exchange in exchanges.reversed() {
            let size = exchange.reduce(0) { $0 + $1.text.count }
            guard size <= remaining else { break }
            selected.insert(contentsOf: exchange, at: 0)
            remaining -= size
        }
        return selected
    }
}

enum PiyakChatFormatting {
    /// The model is asked for prose, but may still emit Markdown. Normalize common
    /// block syntax before native inline rendering. No generated URL is made clickable.
    static func attributed(_ raw: String, streaming: Bool = false) -> AttributedString {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        text = replace(#"\\([*`_])"#, in: text, with: "$1")
        text = replace(#"(?m)^\s*```[^\n]*\n?"#, in: text, with: "")
        text = replace(#"(?m)^\s{0,3}#{1,6}\s+"#, in: text, with: "")
        text = replace(#"(?m)^\s*[-*+]\s+"#, in: text, with: "• ")
        text = replace(#"(?m)^\s*>\s?"#, in: text, with: "")
        text = replace(#"!\[([^\]]*)\]\([^\)]*\)"#, in: text, with: "$1")
        text = replace(#"\[([^\]]+)\]\([^\)]*\)"#, in: text, with: "$1")
        text = replace(#"</?[A-Za-z][^>]*>"#, in: text, with: "")
        text = replace(#"\*\*\s+\*\*"#, in: text, with: "")
        // Avoid exposing an unclosed delimiter, including truncated final responses.
        for delimiter in ["**", "__", "`"] {
            let count = text.components(separatedBy: delimiter).count - 1
            if count % 2 == 1, let range = text.range(of: delimiter, options: .backwards) {
                text.removeSubrange(range)
            }
        }
        var result = (try? AttributedString(markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                           failurePolicy: .returnPartiallyParsedIfPossible))) ?? AttributedString(text)
        result.link = nil
        return result
    }

    static func plain(_ raw: String) -> String { String(attributed(raw).characters) }

    private static func replace(_ pattern: String, in text: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
}
