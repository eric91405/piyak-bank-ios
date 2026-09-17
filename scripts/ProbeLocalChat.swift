// Compile from the repository root (do not overlap with simulator/build work):
// xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macosx26.0 \
//   PiyakBank/Shared/AppConfig.swift PiyakBank/Shared/EarningsCalculator.swift \
//   PiyakBank/Shared/Economy.swift PiyakBank/Shared/PiyakConversation.swift \
//   PiyakBank/Services/WorkSession.swift PiyakBank/App/PiyakAI.swift \
//   scripts/ProbeLocalChat.swift -o /tmp/piyak-local-chat-probe
// Run: /tmp/piyak-local-chat-probe
// UI regression: /tmp/piyak-local-chat-probe --ui-repro
// Short conversational latency: /tmp/piyak-local-chat-probe --latency
// This uses the real app engine and the Mac's local Apple Intelligence model.
// It verifies neither iPhone performance nor iPhone model availability.
// Only synthetic prompts and an empty, in-memory database are used.

import Foundation
import SwiftData
import Darwin

@main
struct ProbeLocalChat {
    @MainActor static func main() async {
        do {
            let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self, WorkSession.self])
            let container = try ModelContainer(for: schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let engine = PiyakChatEngine(container: container)
            print("Environment: macOS; real PiyakChatEngine; in-memory records")
            print("Mode:", String(describing: engine.availability))
            print("Scope: Mac inference only. iPhone quality and performance are not verified.")
            guard engine.isOnDeviceAI else {
                print("Failure:", engine.availability.detail)
                exit(3)
            }
            let uiReproduction = CommandLine.arguments.contains("--ui-repro")
            let latencyProbe = CommandLine.arguments.contains("--latency")
            let prompts = latencyProbe ? [
                "안녕!", "오늘 일이 많아서 조금 지쳤어. 짧게 응원해 줘.",
                "실내에서 5분 안에 할 수 있는 기분 전환 하나만 알려줘.",
                "그 활동의 첫 단계만 한 문장으로 알려줘."
            ] : uiReproduction ? [
                "오늘 수익 알려줘", "내 포인트 얼마야", "사용법 알려줘", "오늘 수익 알려줘",
                "My name is Mina. I like walks. Suggest one thing for tonight.",
                "I cannot go outside. Suggest one quiet indoor activity instead."
            ] : [
                "내 이름은 민서고 산책을 좋아해. 오늘 퇴근했어.",
                "내 이름과 좋아하는 활동 기억해? 그럼 오늘 저녁에 할 만한 일을 하나만 추천해 줘.",
                "추천한 활동이 싫으면 다른 조용한 실내 활동을 하나만 알려줘."
            ]
            let clock = ContinuousClock()
            if latencyProbe {
                engine.prepareForConversation()
                // Match time spent opening the chat/typing; never prewarm in a loop.
                try await Task.sleep(for: .milliseconds(1_100))
            }
            var previousAnswer: String?
            for (index, prompt) in prompts.enumerated() {
                guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
                    print("Deferred: thermal pressure is high; let the computer cool before probing.")
                    exit(75)
                }
                let start = clock.now
                print("\nTurn \(index + 1) prompt:", prompt)
                engine.send(prompt)
                while engine.isThinking {
                    if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                        engine.cancel()
                        print("Deferred: thermal pressure increased; generation canceled.")
                        exit(75)
                    }
                    if start.duration(to: clock.now) >= .seconds(45) {
                        engine.cancel()
                        print("Failure: 45-second probe safeguard; the app watchdog did not settle.")
                        exit(2)
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
                print("Duration:", start.duration(to: clock.now))
                if let metrics = engine.lastResponseMetrics {
                    print("Metrics: first-token=\(metrics.firstTokenSeconds ?? -1)s total=\(metrics.totalSeconds)s attempts=\(metrics.attempts) outcome=\(metrics.outcome)")
                }
                if let failure = engine.failure {
                    print("Failure:", failure.title, failure.detail)
                    exit(1)
                }
                guard let answer = engine.messages.last,
                      answer.role == .piyak, answer.isComplete, !answer.text.isEmpty else {
                    print("Failure: no complete assistant response.")
                    exit(1)
                }
                let plain = PiyakChatFormatting.plain(answer.text).trimmingCharacters(in: .whitespacesAndNewlines)
                print("Answer:", plain)
                // Compare the generated part too: the app's truthful memory prefix must
                // not disguise a repeated model recommendation in the following turn.
                if answer.source == .conversation || answer.source == .groundedConversation {
                    let comparable = PiyakChatFormatting.plain(answer.generatedText).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let issue = PiyakConversation.responseQualityIssue(comparable) {
                        print("Failure: runaway response reached probe:", String(describing: issue))
                        exit(5)
                    }
                    if let previousAnswer, comparable == previousAnswer {
                        print("Failure: the new question received an exact repeat of the previous answer.")
                        exit(4)
                    }
                    let lower = comparable.lowercased()
                    if ["수익", "포인트", "급여", "시급", "잔액"].contains(where: lower.contains) {
                        print("Failure: this fixed leisure-only scenario received unrelated financial claims.")
                        exit(6)
                    }
                    if !latencyProbe && index == prompts.count - 1 {
                        let outdoor = ["산책", "밖에서", "밖으로", "야외", "공원", "카페", "walk", "outside"]
                        let indoor = ["독서", "책", "읽", "명상", "호흡", "스트레칭", "그림", "퍼즐", "일기", "음악", "정리", "글쓰기", "요가", "뜨개", "색칠"]
                        guard !outdoor.contains(where: lower.contains), indoor.contains(where: lower.contains) else {
                            print("Failure: fixed indoor-only scenario did not pass the conservative activity check.")
                            exit(7)
                        }
                    }
                    previousAnswer = comparable
                }
                try await Task.sleep(for: .seconds(2))
            }
            print("\nResult: \(prompts.count) completed responses with no exact consecutive duplicate in generated replies.")
            print("The fixed scenario also passed conservative financial checks\(latencyProbe ? "" : " and indoor keyword checks"). These are regression checks, not a general accuracy guarantee; review all answers manually.")
        } catch {
            print("Failure:", error.localizedDescription)
            exit(1)
        }
    }
}
