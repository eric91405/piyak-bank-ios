import Foundation
import SwiftData
import Testing
@testable import PiyakCore

@MainActor private final class ControlledChatResponder: PiyakResponder {
    struct Request {
        var update: @MainActor (String) -> Void
        var continuation: CheckedContinuation<Void, Error>?
    }
    var requests: [Request] = []
    var histories: [[PiyakChatMessage]] = []
    var memories: [PiyakUserMemory] = []
    var recoveryFlags: [Bool] = []
    var resetCount = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func reset() { resetCount += 1 }

    func stream(_ text: String, history: [PiyakChatMessage],
                memory: PiyakUserMemory, recalling: Bool,
                recoveringFromRepetition: Bool,
                update: @escaping @MainActor (String) -> Void) async throws {
        histories.append(history)
        memories.append(memory)
        recoveryFlags.append(recoveringFromRepetition)
        try await withCheckedThrowingContinuation { continuation in
            requests.append(.init(update: update, continuation: continuation))
            let ready = waiters.filter { requests.count >= $0.0 }
            waiters.removeAll { requests.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForRequest(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func emit(_ text: String, request: Int) { requests[request].update(text) }
    func finish(_ request: Int, error: Error? = nil) {
        let continuation = requests[request].continuation
        requests[request].continuation = nil
        if let error { continuation?.resume(throwing: error) }
        else { continuation?.resume() }
    }
}

@MainActor private func chatContainer() throws -> ModelContainer {
    let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self, WorkSession.self])
    return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

@MainActor private func waitUntilIdle(_ engine: PiyakChatEngine) async {
    for _ in 0..<1_000 {
        if !engine.isThinking { return }
        await Task.yield()
    }
    Issue.record("Chat task did not settle after its controlled response finished.")
}

@Test @MainActor func canceledStreamCannotOverwriteRetriedResponse() async throws {
    let responder = ControlledChatResponder()
    let engine = PiyakChatEngine(container: try chatContainer(), responder: responder, availabilityProvider: { .ready })
    engine.send("안녕 삐약아")
    await responder.waitForRequest(1)
    responder.emit("첫 답변 일부", request: 0)
    engine.cancel()
    #expect(responder.resetCount == 1)
    #expect(!engine.isThinking)
    #expect(engine.messages.last?.isComplete == false)
    engine.retry()
    await responder.waitForRequest(2)
    #expect(responder.histories[1].isEmpty) // The canceled partial answer is not memory.
    responder.emit("늦게 온 이전 답변", request: 0)
    #expect(!engine.messages.contains { $0.text == "늦게 온 이전 답변" })
    responder.emit("새로운 답변", request: 1)
    responder.finish(0)
    responder.finish(1)
    await waitUntilIdle(engine)
    #expect(engine.messages.filter { $0.role == .user }.count == 1)
    #expect(engine.messages.last?.text == "새로운 답변")
    #expect(engine.messages.last?.isComplete == true)
    #expect(engine.failure == nil)
    engine.clear()
    #expect(responder.resetCount == 2)
    #expect(engine.messages.isEmpty)
}

@Test @MainActor func generationFailureIsVisibleAndRetryRetainsContext() async throws {
    struct ModelFailure: Error {}
    let responder = ControlledChatResponder()
    let engine = PiyakChatEngine(container: try chatContainer(), responder: responder, availabilityProvider: { .ready })
    engine.send("나는 민서야")
    await responder.waitForRequest(1)
    responder.emit("반가워 민서", request: 0)
    responder.finish(0)
    await waitUntilIdle(engine)
    engine.send("나에게 해 주고 싶은 말 있어?")
    await responder.waitForRequest(2)
    #expect(responder.histories[1].first?.text == "나는 민서야")
    responder.emit("잘못 시작한 미완성 답변", request: 1)
    responder.finish(1, error: ModelFailure())
    await waitUntilIdle(engine)
    #expect(engine.failure != nil)
    #expect(engine.messages.last?.isComplete == false) // No canned answer replacing the failure.
    engine.retry()
    await responder.waitForRequest(3)
    #expect(responder.histories[2] == responder.histories[1])
    responder.emit("민서라고 알려줬어", request: 2)
    responder.finish(2)
    await waitUntilIdle(engine)
    #expect(engine.failure == nil)
    #expect(engine.messages.filter { $0.role == .user }.count == 2)
}

@Test @MainActor func unavailableAIStillAnswersRecordsWithoutInventedConversation() throws {
    let engine = PiyakChatEngine(container: try chatContainer(), availabilityProvider: { .disabled })
    engine.send("안녕 삐약아")
    #expect(engine.messages.count == 1)
    #expect(engine.failure?.detail.contains("Apple Intelligence") == true)
    engine.send("오늘 수익 알려줘")
    #expect(engine.failure == nil)
    #expect(engine.messages.last?.source == .records)
    let answer = PiyakChatFormatting.plain(engine.messages.last?.text ?? "")
    #expect(answer.contains("0원"))
}

@Test @MainActor func explicitMemoryRecallDoesNotAskModelToGuessPersonalFacts() throws {
    let engine = PiyakChatEngine(container: try chatContainer(), availabilityProvider: { .disabled })
    engine.send("내 이름은 민서고 산책을 좋아해. 오늘 퇴근했어.")
    engine.send("내 이름과 좋아하는 활동 기억해?")
    let answer = PiyakChatFormatting.plain(engine.messages.last?.text ?? "")
    #expect(engine.failure == nil)
    #expect(engine.messages.last?.source == .memory)
    #expect(answer.contains("민서"))
    #expect(answer.contains("산책"))
    #expect(!answer.contains("커피"))
}

@Test @MainActor func punctuationOnlyMessageShowsInputGuidanceWithoutModelCall() throws {
    let responder = ControlledChatResponder()
    let engine = PiyakChatEngine(container: try chatContainer(), responder: responder, availabilityProvider: { .ready })
    engine.send(". .")
    #expect(engine.failure?.canRetry == false)
    #expect(!engine.isThinking)
    #expect(responder.requests.isEmpty)
    #expect(engine.messages.count == 1)
}

@Test @MainActor func repeatedAnswerRetriesOnceWithUserOnlyContextAndPreservedFacts() async throws {
    let responder = ControlledChatResponder()
    let engine = PiyakChatEngine(container: try chatContainer(), responder: responder, availabilityProvider: { .ready })
    engine.send("내 이름은 민서고 산책을 좋아해.")
    await responder.waitForRequest(1)
    responder.emit("산책을 추천해.", request: 0)
    responder.finish(0)
    await waitUntilIdle(engine)
    engine.send("I cannot go outside. Suggest one quiet indoor activity instead.")
    await responder.waitForRequest(2)
    responder.emit("**산책을 추천해!**", request: 1)
    responder.finish(1)
    await responder.waitForRequest(3)
    #expect(responder.recoveryFlags == [false, false, true])
    #expect(responder.histories[2].allSatisfy { $0.role == .user })
    #expect(responder.memories[2].name == "민서")
    #expect(responder.memories[2].likes == ["산책"])
    responder.emit("집에서 조용히 책 한 쪽을 읽어 봐.", request: 2)
    responder.finish(2)
    await waitUntilIdle(engine)
    #expect(engine.failure == nil)
    #expect(engine.messages.last?.text == "집에서 조용히 책 한 쪽을 읽어 봐.")
    #expect(responder.requests.count == 3)
}

@Test @MainActor func aSecondRepeatedAnswerStopsWithAnHonestFailure() async throws {
    let responder = ControlledChatResponder()
    let engine = PiyakChatEngine(container: try chatContainer(), responder: responder, availabilityProvider: { .ready })
    engine.send("퇴근했어. 뭐 할까?")
    await responder.waitForRequest(1)
    responder.emit("산책을 추천해.", request: 0)
    responder.finish(0)
    await waitUntilIdle(engine)
    engine.send("다른 실내 활동을 하나 알려줘")
    await responder.waitForRequest(2)
    responder.emit("산책을 추천해.", request: 1)
    responder.finish(1)
    await responder.waitForRequest(3)
    responder.emit("산책을 추천해.", request: 2)
    responder.finish(2)
    await waitUntilIdle(engine)
    #expect(engine.failure?.detail.contains("이전 답변을 반복") == true)
    #expect(engine.messages.last?.role == .user)
    #expect(responder.requests.count == 3)
}

@Test(arguments: [String(repeating: "가", count: 800), String(repeating: "똑같은 문장을 계속 써. ", count: 3),
                  String(repeating: "집에서 할 만한 조용한 활동은 ", count: 3)])
@MainActor func runawayAnswerHasOnlyOneRecoveryAttempt(_ rejected: String) async throws {
    let responder = ControlledChatResponder()
    let engine = PiyakChatEngine(container: try chatContainer(), responder: responder, availabilityProvider: { .ready })
    engine.send("조용한 실내 활동 하나 알려줘")
    await responder.waitForRequest(1)
    responder.emit(rejected, request: 0)
    responder.finish(0)
    await responder.waitForRequest(2)
    #expect(responder.recoveryFlags == [false, true])
    responder.emit(rejected, request: 1)
    responder.finish(1)
    await waitUntilIdle(engine)
    #expect(engine.failure != nil)
    #expect(engine.messages.last?.role == .user)
    #expect(responder.requests.count == 2)
}

@Test @MainActor func recordHelpAnswersNeverEnterActualModelRequests() async throws {
    let responder = ControlledChatResponder()
    let engine = PiyakChatEngine(container: try chatContainer(), responder: responder, availabilityProvider: { .ready })
    engine.send("오늘 수익 알려줘")
    engine.send("사용법 알려줘")
    engine.send("My name is Mina. I like walks. Suggest one thing for tonight.")
    await responder.waitForRequest(1)
    #expect(responder.histories[0].isEmpty)
    responder.emit("가볍게 산책하는 건 어때?", request: 0)
    responder.finish(0)
    await waitUntilIdle(engine)
    engine.send("I cannot go outside. Suggest one quiet indoor activity instead.")
    await responder.waitForRequest(2)
    #expect(responder.histories[1].count == 2)
    #expect(!responder.histories[1].contains { $0.text.contains("수익") || $0.text.contains("사용법") })
    responder.emit("집에서 책 한 쪽을 조용히 읽어 봐.", request: 1)
    responder.finish(1)
    await waitUntilIdle(engine)
}
