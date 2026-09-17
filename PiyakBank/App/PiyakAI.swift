import Foundation
import SwiftData
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

struct PiyakChatMessage: Identifiable, Equatable {
    enum Role { case user, piyak }
    let id = UUID()
    let role: Role
    var text: String
}

@MainActor
final class PiyakChatEngine: ObservableObject {
    @Published var messages: [PiyakChatMessage] = []
    @Published private(set) var isThinking = false
    let isOnDeviceAI: Bool
    private let container: ModelContainer
    private var task: Task<Void, Never>?
    private let smallTalk: (any PiyakSmallTalk)?

    init(container: ModelContainer) {
        self.container = container
        var responder: (any PiyakSmallTalk)?
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.availability == .available {
            responder = FoundationSmallTalk()
        }
        #endif
        smallTalk = responder
        isOnDeviceAI = responder != nil
    }

    func send(_ raw: String) {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !text.isEmpty, !isThinking else { return }
        messages.append(.init(role: .user, text: text))
        if messages.count > 40 { messages.removeFirst(messages.count - 40) }
        isThinking = true
        task = Task { [weak self] in
            guard let self else { return }
            let answer = await self.reply(text)
            guard !Task.isCancelled else { return }
            self.messages.append(.init(role: .piyak, text: answer))
            self.isThinking = false
        }
    }
    func cancel() { task?.cancel(); task = nil; isThinking = false }

    private func reply(_ text: String) async -> String {
        do {
            if let answer = try recordAnswer(text) { return answer }
        } catch { return "기록을 읽지 못했어. 숫자를 확인할 수 없으니 기록 탭에서 다시 확인해 줘, 삐약." }
        if let smallTalk {
            do { return try await smallTalk.reply(text) }
            catch { /* Offline basic mode is always available. */ }
        }
        return ["오늘도 만나서 반가워! 네 하루에 작은 응원이 될게, 삐약!",
                "잠깐 기지개 켜 볼까? 쉬어 가도 괜찮아, 삐약!",
                "우리 방에 어울릴 소품을 구경해 볼까? 조금씩 꾸미는 게 재밌어!"] .randomElement() ?? "오늘도 응원할게, 삐약!"
    }

    /// Financial answers are formatted directly from the database, never generated.
    private func recordAnswer(_ text: String) throws -> String? {
        let store = EconomyStore(context: container.mainContext)
        if ["잔액", "포인트", "얼마나 있", "보유"].contains(where: text.contains) {
            return "지금 쓸 수 있는 포인트는 \(try store.balance().points)야! 진행 중인 근무는 마친 뒤에 포인트로 받아, 삐약."
        }
        let dataWords = ["얼마", "벌", "수익", "정산", "시급", "급여", "기록"]
        guard dataWords.contains(where: text.contains) else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var from = today
        var to = today
        var label = "오늘"
        if text.contains("어제") {
            from = cal.date(byAdding: .day, value: -1, to: today) ?? today; to = from; label = "어제"
        } else if text.contains("지난주") || text.contains("지난 주") {
            let prior = cal.date(byAdding: .day, value: -7, to: today) ?? today
            if let range = cal.dateInterval(of: .weekOfYear, for: prior) {
                from = range.start; to = cal.date(byAdding: .day, value: -1, to: range.end) ?? prior
            }
            label = "지난주"
        } else if text.contains("이번 주") || text.contains("이번주") {
            from = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today; label = "이번 주"
        } else if text.contains("이번 달") || text.contains("이번달") {
            from = cal.dateInterval(of: .month, for: today)?.start ?? today; label = "이번 달"
        } else if text.contains("지난달") || text.contains("지난 달") {
            let prior = cal.date(byAdding: .month, value: -1, to: today) ?? today
            if let range = cal.dateInterval(of: .month, for: prior) {
                from = range.start; to = cal.date(byAdding: .day, value: -1, to: range.end) ?? prior
            }
            label = "지난달"
        } else if !text.contains("오늘") {
            return "오늘·어제·이번 주·지난주·이번 달·지난달의 예상 수익이나 보유 포인트를 물어봐 줘! 다른 날짜와 시급은 기록 탭에서 확인할 수 있어, 삐약."
        }
        let now = Date()
        var day = from
        var total = 0
        for _ in 0..<32 {
            guard day <= to else { break }
            total += try store.dailyAccrued(on: day, includingActive: true, now: now)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return "\(label) 예상 수익은 \(total.won)이야! 휴식은 빼고, 진행 중인 근무도 포함했어. 실제 급여와는 다를 수 있어, 삐약."
    }
}

@MainActor
private protocol PiyakSmallTalk {
    func reply(_ text: String) async throws -> String
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@MainActor
private final class FoundationSmallTalk: PiyakSmallTalk {
    private var session: LanguageModelSession?
    private var turns = 0
    func reply(_ text: String) async throws -> String {
        if session == nil || turns >= 6 {
            session = LanguageModelSession(instructions: """
            너는 근무 기록 앱 '삐약뱅크'의 작은 병아리 친구 '삐약이'야.
            한국어로 1~3문장, 다정하고 경쾌하게 대화해. 무리한 근무를 권하지 마.
            네 역할은 짧은 응원과 일상 대화야. 사용자의 기록이나 포인트를 조회할 수 없어.
            금액, 시급, 날짜별 기록, 투자, 세금, 법률 상담은 답을 만들지 말고 앱의 기록 탭에서 확인하도록 안내해.
            포인트는 꾸미기 전용이고 현금 가치, 입출금, 실제 은행 기능은 없어.
            """)
            turns = 0
        }
        do {
            let answer = try await session!.respond(to: text).content
            turns += 1
            return answer
        } catch { session = nil; throw error }
    }
}
#endif
