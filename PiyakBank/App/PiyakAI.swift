import Foundation
import SwiftData
import SwiftUI
import Combine

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - 채팅 메시지

struct PiyakChatMessage: Identifiable, Equatable {
    enum Role { case user, piyak }
    let id = UUID()
    let role: Role
    var text: String
}

// MARK: - 삐약이에게 주입할 현재 상황 스냅샷

struct PiyakContextSnapshot {
    let balance: Int
    let todayEarned: Int
    let wearing: [String]

    @MainActor
    static func capture(context: ModelContext) -> PiyakContextSnapshot {
        let store = EconomyStore(context: context)
        let wearingNames: [String] = DecorSlot.allCases
            .filter { !$0.isRoom }
            .compactMap { slot in
                guard let id = store.equippedId(for: slot) else { return nil }
                return store.catalog(id)?.displayName
            }
        return .init(balance: store.balance,
                     todayEarned: store.dailyAccrued(on: .now),
                     wearing: wearingNames)
    }
}

// MARK: - 응답기 추상화 (AI / 폴백 공용 인터페이스)

@MainActor
protocol PiyakResponder {
    func reply(to text: String) async -> String
}

// MARK: - 채팅 엔진 (UI가 바라보는 단일 진입점)

@MainActor
final class PiyakChatEngine: ObservableObject {
    @Published var messages: [PiyakChatMessage] = []
    @Published var isThinking = false

    /// 온디바이스 AI 사용 가능 여부 (false면 규칙 기반 폴백으로 동작)
    let isOnDeviceAI: Bool
    private let responder: PiyakResponder

    init(container: ModelContainer, snapshot: PiyakContextSnapshot) {
        var picked: PiyakResponder? = nil
        var ai = false
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           case .available = SystemLanguageModel.default.availability {
            picked = PiyakAIResponder(container: container, snapshot: snapshot)
            ai = true
        }
        #endif
        self.responder = picked ?? PiyakFallbackResponder(container: container)
        self.isOnDeviceAI = ai
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        messages.append(.init(role: .user, text: text))
        isThinking = true
        Task {
            let answer = await responder.reply(to: text)
            isThinking = false
            await revealWithTyping(answer)
        }
    }

    /// 글자 단위 타이핑 연출 (전체 노출이 3초를 넘지 않게 속도 자동 조절)
    private func revealWithTyping(_ full: String) async {
        messages.append(.init(role: .piyak, text: ""))
        let idx = messages.count - 1
        let perChar = min(22, 3000 / max(full.count, 1))
        for ch in full {
            messages[idx].text.append(ch)
            try? await Task.sleep(for: .milliseconds(perChar))
        }
    }
}

// MARK: - 온디바이스 AI 응답기 (Apple Foundation Models)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@MainActor
final class PiyakAIResponder: PiyakResponder {
    private let session: LanguageModelSession

    init(container: ModelContainer, snapshot: PiyakContextSnapshot) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let wf = DateFormatter()
        wf.locale = Locale(identifier: "ko_KR")
        wf.dateFormat = "EEEE"

        let wearing = snapshot.wearing.isEmpty ? "아직 없음" : snapshot.wearing.joined(separator: ", ")
        let instructions = """
        너는 '삐약이'. 사용자가 알바해서 번 돈(포인트)으로 키우고 꾸며주는 아기 병아리 펫이야.

        [오늘] \(df.string(from: .now)) \(wf.string(from: .now))
        [지금 상황]
        - 보유 포인트: \(snapshot.balance)P
        - 오늘 적립: \(snapshot.todayEarned)P
        - 네가 착용 중인 아이템: \(wearing)

        [규칙]
        1. 반말로, 1~3문장으로 짧고 귀엽게 답해. 가끔 문장 끝에 "삐약!"을 붙여.
        2. 돈·적립·기록에 대한 질문에는 반드시 도구를 호출해서 받은 숫자로만 답해. 숫자를 추측하거나 지어내지 마.
        3. "지난주", "이번 달" 같은 표현은 위의 오늘 날짜를 기준으로 yyyy-MM-dd 기간으로 바꿔 도구에 전달해.
        4. 1P = 1원이야. 금액은 "12,000원"처럼 콤마를 넣어 읽기 좋게 말해.
        5. 사용자를 응원하고 고마워하는 펫의 마음을 항상 유지해.
        """

        session = LanguageModelSession(
            tools: [
                BalanceTool(container: container),
                EarningsTool(container: container),
            ],
            instructions: instructions
        )
    }

    func reply(to text: String) async -> String {
        do {
            return try await session.respond(to: text).content
        } catch {
            return "어... 잠깐 멍해졌어 삐약. 한 번만 다시 말해줄래?"
        }
    }
}

// MARK: - Tools (LLM이 SwiftData 원장을 직접 조회 — 숫자 환각 방지)

/// 현재 잔액 + 오늘 적립 조회
@available(iOS 26.0, *)
struct BalanceTool: Tool {
    let name = "getBalance"
    let description = "사용자의 현재 보유 포인트(잔액)와 오늘 적립한 포인트를 조회한다."
    let container: ModelContainer

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let text = await MainActor.run {
            let store = EconomyStore(context: container.mainContext)
            return "보유 포인트 \(store.balance)P / 오늘 적립 \(store.dailyAccrued(on: .now))P"
        }
        return text
    }
}

/// 기간별 적립 통계 조회 (합계 · 일한 날 수 · 최고 수입일)
@available(iOS 26.0, *)
struct EarningsTool: Tool {
    let name = "getEarnings"
    let description = "특정 기간의 적립 통계를 조회한다. 합계, 적립이 있었던 날 수, 가장 많이 번 날을 반환한다."
    let container: ModelContainer

    @Generable
    struct Arguments {
        @Guide(description: "조회 시작일, yyyy-MM-dd 형식")
        var from: String
        @Guide(description: "조회 종료일(포함), yyyy-MM-dd 형식")
        var to: String
    }

    func call(arguments: Arguments) async throws -> String {
        let text = await MainActor.run {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            guard let start = df.date(from: arguments.from),
                  let end = df.date(from: arguments.to), start <= end else {
                return "기간 형식이 잘못됐다 (yyyy-MM-dd 필요)"
            }
            let store = EconomyStore(context: container.mainContext)
            let cal = Calendar.current
            var day = cal.startOfDay(for: start)
            let last = cal.startOfDay(for: end)
            var total = 0, workedDays = 0
            var best = (date: "", amount: 0)
            while day <= last {
                let earned = store.dailyAccrued(on: day)
                if earned > 0 {
                    total += earned
                    workedDays += 1
                    if earned > best.amount { best = (df.string(from: day), earned) }
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            if total == 0 { return "\(arguments.from)~\(arguments.to): 적립 기록 없음" }
            return "\(arguments.from)~\(arguments.to): 합계 \(total)P, 적립일 \(workedDays)일, 최고 \(best.date) \(best.amount)P"
        }
        return text
    }
}
#endif

// MARK: - 폴백 응답기 (Apple Intelligence 미지원 기기 · 시뮬레이터)

@MainActor
final class PiyakFallbackResponder: PiyakResponder {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func reply(to text: String) async -> String {
        // 답변 직전 잠깐 숨 고르기 (즉답이면 기계 느낌이라)
        try? await Task.sleep(for: .milliseconds(450))

        let store = EconomyStore(context: container.mainContext)
        let t = text.lowercased()

        if t.contains("주") && (t.contains("얼마") || t.contains("정산") || t.contains("벌")) {
            let cal = Calendar.current
            var total = 0
            for offset in 0..<7 {
                if let d = cal.date(byAdding: .day, value: -offset, to: .now) {
                    total += store.dailyAccrued(on: d)
                }
            }
            return "최근 7일 동안 \(total.won) 모았어! 꾸준한 게 제일 멋져 삐약!"
        }
        if t.contains("얼마") || t.contains("벌") || t.contains("적립") {
            return "오늘은 \(store.dailyAccrued(on: .now).won) 벌었어! 고생했어 삐약!"
        }
        if t.contains("포인트") || t.contains("잔액") || t.contains("얼마나 있") {
            return "지금 \(store.balance.won) 모여 있어! 뭐 사줄 거야? 삐약!"
        }
        return Self.smallTalk.randomElement()!
    }

    private static let smallTalk = [
        "오늘도 와줬구나! 보고 싶었어 삐약!",
        "방이 점점 예뻐지는 것 같지 않아? 다 네 덕분이야!",
        "일하느라 힘들었지? 그래도 네가 제일 멋져 삐약!",
        "나 오늘 방 청소했다? ...거짓말이야, 그냥 뒹굴었어 삐약!",
        "포인트 모아서 뭐 살지 같이 구경할래?",
    ]
}
