import Foundation
import Testing
@testable import PiyakCore

@Test func repeatedGreetingsAndRepeatedQuestionsDoNotCauseExtraGeneration() {
    #expect(!PiyakConversation.isUnrequestedRepeat("안녕!", of: "안녕!", request: "또 왔어"))
    #expect(!PiyakConversation.isUnrequestedRepeat("안녕, 반가워!", of: "안녕, 반가워!", request: "하이"))
    #expect(!PiyakConversation.isUnrequestedRepeat("나는 삐약이야.", of: "나는 삐약이야.",
                                                  request: "네 이름은 뭐야?", previousRequest: "네 이름은 뭐야?"))
    #expect(PiyakConversation.isUnrequestedRepeat("산책을 추천해.", of: "산책을 추천해.",
                                                 request: "산책 말고 실내 활동 알려줘", previousRequest: "뭐 할까?"))
}

@Test func routesOnlyExplicitMoneyQuestions() {
    #expect(PiyakConversation.intent("오늘 얼마 벌었어?") == .earnings(.today))
    #expect(PiyakConversation.intent("이번 주 정산해줘") == .earnings(.thisWeek))
    #expect(PiyakConversation.intent("지난달 수익") == .earnings(.lastMonth))
    #expect(PiyakConversation.intent("내 포인트 얼마나 남았어?") == .balance)
    #expect(PiyakConversation.intent("내 시급 얼마야?") == .wage)
    #expect(PiyakConversation.intent("수익 알려줘") == .choosePeriod)
    for text in ["벌써 퇴근하고 싶어", "오늘 수익이 적어서 속상해", "얼마나 힘든 하루였는지 몰라",
                 "오늘 힘들어", "오늘 수익 슬퍼", "내 일상을 기록하고 싶어", "취미를 추천해줘",
                 "포인트로 뭘 살 수 있어?", "수익이 얼마나 적은지 속상해"] {
        #expect(PiyakConversation.intent(text) == .conversation, "Should remain conversation: \(text)")
    }
}

@Test func recordFollowUpUsesOnlyImmediateRecordContext() {
    #expect(PiyakConversation.intent("그럼 어제는?", previous: .earnings(.today)) == .earnings(.yesterday))
    #expect(PiyakConversation.intent("이번 달은?", previous: .earnings(.thisWeek)) == .earnings(.thisMonth))
    #expect(PiyakConversation.intent("어제", previous: .choosePeriod) == .earnings(.yesterday))
    #expect(PiyakConversation.intent("어제는?", previous: .conversation) == .conversation)
    #expect(PiyakConversation.intent("어제는 정말 힘들었어", previous: .earnings(.today)) == .conversation)
    #expect(PiyakConversation.intent("오늘 너무 슬퍼", previous: .earnings(.yesterday)) == .conversation)
}

@Test func boundedContextPreservesWholeRecentExchangesBeyondSixTurns() {
    let history = (0..<8).flatMap { number in
        [PiyakChatMessage(role: .user, text: "질문\(number)"),
         PiyakChatMessage(role: .piyak, text: "답변\(number)")]
    }
    let full = PiyakConversation.context(history)
    #expect(full == history)
    let bounded = PiyakConversation.context(history, characterBudget: 12)
    #expect(bounded == Array(history.suffix(4)))
    #expect(bounded.first?.role == .user)
    #expect(bounded.last?.role == .piyak)
}

@Test func canceledAndFailedRepliesAreNotRememberedAsFacts() {
    let complete = [PiyakChatMessage(role: .user, text: "나는 민서야"),
                    PiyakChatMessage(role: .piyak, text: "반가워 민서!")]
    let interrupted = [PiyakChatMessage(role: .user, text: "긴 질문"),
                       PiyakChatMessage(role: .piyak, text: "틀린 미완성 답변", isComplete: false),
                       PiyakChatMessage(role: .user, text: "실패한 질문")]
    #expect(PiyakConversation.context(complete + interrupted) == complete)
    #expect(PiyakConversation.context(complete, characterBudget: 1).isEmpty)
}

@Test func markdownRendersBoldWithoutDisplayingDelimiters() {
    let result = PiyakChatFormatting.attributed("오늘은 **기분 좋은 날**이야!\n함께 쉬자.")
    #expect(String(result.characters) == "오늘은 기분 좋은 날이야!\n함께 쉬자.")
    #expect(result.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    #expect(PiyakChatFormatting.plain(#"\*\*수고했어\*\*"#) == "수고했어")
}

@Test func markdownHandlesBlocksStreamingAndUntrustedLinks() {
    #expect(PiyakChatFormatting.plain("### 추천\n- 산책\n- 음악 듣기") == "추천\n• 산책\n• 음악 듣기")
    let streaming = PiyakChatFormatting.attributed("오늘은 **행복", streaming: true)
    #expect(String(streaming.characters) == "오늘은 행복")
    #expect(PiyakChatFormatting.plain("오늘은 **행복") == "오늘은 행복")
    let link = PiyakChatFormatting.attributed("[여기](https://untrusted.example)에서 **보기**")
    #expect(String(link.characters) == "여기에서 보기")
    #expect(link.runs.allSatisfy { $0.link == nil })
    #expect(PiyakChatFormatting.plain("2 * 3 = 6, 2 < 3") == "2 * 3 = 6, 2 < 3")
}

@Test func chatPeriodsRespectCalendarMonthAndDaylightSavings() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let date = try #require(ISO8601DateFormatter().date(from: "2026-04-03T12:00:00Z"))
    let days = PiyakRecordPeriod.lastMonth.days(at: date, calendar: calendar)
    #expect(days.count == 31)
    #expect(calendar.component(.day, from: try #require(days.last)) == 31)
    #expect(Set(days.map { calendar.component(.month, from: $0) }) == [3])
    #expect(PiyakRecordPeriod.thisMonth.days(at: date, calendar: calendar).count == 3)
    #expect(zip(days, days.dropFirst()).contains { $1.timeIntervalSince($0) == 23 * 3600 })
}

@Test func userMemoryUsesExplicitUserStatementsNeverAssistantHallucinations() {
    let memory = PiyakUserMemory.extract(from: [
        .init(role: .user, text: "내 이름은 민서고 산책을 좋아해. 오늘 퇴근했어."),
        .init(role: .piyak, text: "네 이름은 철수고 커피를 좋아해."),
        .init(role: .user, text: "내 이름과 좋아하는 활동 기억해?")
    ])
    #expect(memory.name == "민서")
    #expect(memory.likes == ["산책"])
    #expect(!memory.reference.contains("커피"))
    #expect(PiyakChatFormatting.plain(memory.recallText).contains("민서"))
}

@Test func userMemoryAcceptsExplicitCorrectionsAndRejectsHypotheticalExamples() {
    let memory = PiyakUserMemory.extract(from: [
        .init(role: .user, text: "내 이름은 민서야. 산책을 좋아해."),
        .init(role: .user, text: "만약 내 이름은 철수고 커피를 좋아해라고 가정해 봐"),
        .init(role: .user, text: "내 이름은 지우야. 산책을 좋아하지 않아. 독서를 좋아해.")
    ])
    #expect(memory.name == "지우")
    #expect(memory.likes == ["독서"])
    #expect(memory.recommendationFocus(for: "좋아하는 활동으로 하나만 추천해") == "독서")
    #expect(memory.recommendationFocus(for: "독서 말고 다른 걸 추천해") == nil)
    #expect(PiyakUserMemory.extract(from: [.init(role: .user, text: "내 이름은 철수야?")]).name == nil)
}

@Test func explicitRecallCanBeSeparatedFromGenerativeRecommendation() {
    let compound = "내 이름과 좋아하는 활동 기억해? 그럼 오늘 저녁에 할 만한 일을 하나만 추천해 줘."
    #expect(PiyakUserMemory.asksForRecall(compound))
    #expect(PiyakUserMemory.alsoAsksForSuggestion(compound))
    #expect(PiyakUserMemory.asksForRecall("내 이름 기억해?"))
    #expect(!PiyakUserMemory.alsoAsksForSuggestion("내 이름 기억해?"))
    #expect(!PiyakUserMemory.asksForRecall("오늘 기억에 남는 일이 있어"))
}

@Test func englishExplicitFactsAndRecallFollowTheSameGroundedPath() {
    let introduction = "My name is Minseo. I like walks. I finished work today."
    let followUp = "What activity did I say I like? Suggest one thing for this evening."
    let memory = PiyakUserMemory.extract(from: [
        .init(role: .user, text: introduction),
        .init(role: .piyak, text: "My name is Invented. I like coffee."),
        .init(role: .user, text: followUp)
    ])
    #expect(memory.name == "Minseo")
    #expect(memory.likes == ["walks"])
    #expect(PiyakUserMemory.asksForRecall(followUp))
    #expect(PiyakUserMemory.alsoAsksForSuggestion(followUp))
    let corrected = PiyakUserMemory.extract(from: [
        .init(role: .user, text: introduction), .init(role: .user, text: "I don't like walks. I enjoy reading.")
    ])
    #expect(corrected.likes == ["reading"])
}

@Test func punctuationOnlyInputsAreNotSentForGeneration() {
    for text in [". .", "  ", "?!...", "**", "#"] {
        #expect(!PiyakConversation.hasMeaningfulInput(text))
    }
    for text in ["안녕", "Hello", "😀", "❤️", "ㅋㅋ"] {
        #expect(PiyakConversation.hasMeaningfulInput(text))
    }
}

@Test func repeatedAnswerDetectionNormalizesFormattingButHonorsExplicitRepeatRequests() {
    #expect(PiyakConversation.isUnrequestedRepeat(" **산책을 추천해!** ", of: "산책을 추천해.", request: "실내 활동을 알려줘"))
    #expect(!PiyakConversation.isUnrequestedRepeat("독서를 추천해.", of: "산책을 추천해.", request: "실내 활동을 알려줘"))
    #expect(!PiyakConversation.isUnrequestedRepeat("산책을 추천해.", of: "산책을 추천해.", request: "다시 말해줘"))
    #expect(!PiyakConversation.isUnrequestedRepeat("산책을 추천해.", of: "산책을 추천해.", request: "Repeat that please"))
    #expect(PiyakConversation.isUnrequestedRepeat("산책을 추천해.", of: "산책을 추천해.", request: "Do not repeat that. Suggest an indoor activity."))
}

@Test func modelContextExcludesStaticRepliesAndUsesOnlyTwoShortGeneratedExchanges() {
    var messages: [PiyakChatMessage] = [
        .init(role: .user, text: "오늘 수익 알려줘"), .init(role: .piyak, text: "0원", source: .records),
        .init(role: .user, text: "사용법 알려줘"), .init(role: .piyak, text: "사용법 안내", source: .help),
        .init(role: .user, text: "내 이름 기억해?"), .init(role: .piyak, text: "민서", source: .memory)
    ]
    #expect(PiyakConversation.modelContext(messages).isEmpty)
    messages += [
        .init(role: .user, text: "오래된 대화"), .init(role: .piyak, text: "오래된 답"),
        .init(role: .user, text: String(repeating: "가", count: 600)),
        .init(role: .piyak, text: String(repeating: "나", count: 600)),
        .init(role: .user, text: "내 취향으로 추천해"),
        .init(role: .piyak, text: "정확한 기억 표시\n\n책 한 쪽을 읽어 봐.", source: .groundedConversation)
    ]
    let context = PiyakConversation.modelContext(messages)
    #expect(context.count == 4)
    #expect(context[0].text.count == 400)
    #expect(context[1].text.count == 350)
    #expect(context.last?.text == "책 한 쪽을 읽어 봐.")
    #expect(context.last?.generatedText == "책 한 쪽을 읽어 봐.")
}

@Test func runawayResponsesAreRejectedAtFixedBounds() {
    #expect(PiyakConversation.responseQualityIssue(String(repeating: "가", count: 800)) == .excessiveLength)
    #expect(PiyakConversation.responseQualityIssue(String(repeating: "가", count: 799)) == nil)
    #expect(PiyakConversation.responseQualityIssue(String(repeating: "오늘 수익은 1000포인트야. ", count: 3)) == .repeatedSentence)
    #expect(PiyakConversation.responseQualityIssue(String(repeating: "오늘 수익은 1000포인트야. ", count: 2)) == nil)
    #expect(PiyakConversation.responseQualityIssue(String(repeating: "집에서 할 만한 조용한 활동은 ", count: 3)) == .repeatedPhrase)
    #expect(PiyakConversation.responseQualityIssue(String(repeating: "집에서 할 만한 조용한 활동은 ", count: 2)) == nil)
}
