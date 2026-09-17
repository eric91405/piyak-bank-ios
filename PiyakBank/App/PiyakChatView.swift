import SwiftUI
import SwiftData

struct PiyakChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var engine: PiyakChatEngine
    @State private var input = ""
    @State private var showDetails = false
    @State private var confirmClear = false
    @FocusState private var inputFocused: Bool

    init(engine: PiyakChatEngine) { _engine = StateObject(wrappedValue: engine) }

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            quickActions
            inputBar
        }
        .background(PB.C.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { engine.prepareForConversation() }
        .onDisappear { engine.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.prepareForConversation() }
            else if phase == .background { engine.cancel() }
        }
        .confirmationDialog("이 대화를 지우고 새로 시작할까요?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("새 대화 시작", role: .destructive) { engine.clear() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("AppMascot")
                .resizable().scaledToFit().frame(width: 42, height: 42)
                .background(PB.C.brandYellow.opacity(0.25), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("삐약이와 이야기").font(PB.F.body(17).weight(.bold))
                Label(engine.isOnDeviceAI ? "온디바이스 AI" : "기록 도우미", systemImage: engine.isOnDeviceAI ? "sparkles" : "list.bullet.clipboard")
                    .font(PB.F.body(11)).foregroundStyle(PB.C.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button("AI 상태 다시 확인", systemImage: "arrow.clockwise") { engine.refreshAvailability() }
                    .disabled(engine.isThinking)
                Button("새 대화", systemImage: "square.and.pencil") { confirmClear = true }
                    .disabled(engine.messages.isEmpty)
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }.accessibilityLabel("대화 메뉴")
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    .frame(width: 44, height: 44).background(PB.C.surface, in: Circle())
            }.accessibilityLabel("대화 닫기")
        }
        .foregroundStyle(PB.C.textBrown)
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 10)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // History is capped at 60 messages. Measuring those actual heights avoids
                // lazy estimated-height corrections while the streamed bubble is growing.
                VStack(spacing: 14) {
                    availabilityCard
                    if engine.messages.isEmpty { emptyState }
                    ForEach(engine.messages) { message in
                        ChatBubble(message: message,
                                   streaming: engine.isThinking && message.id == engine.messages.last?.id)
                            .equatable()
                    }
                    if engine.isThinking && (!engine.isStreaming || engine.isSlowResponse || engine.isRecoveringResponse) {
                        HStack(spacing: 10) {
                            ProgressView().tint(PB.C.coral)
                            Text(engine.progressText).font(PB.F.body(13)).foregroundStyle(PB.C.secondary)
                            Spacer()
                        }.padding(.vertical, 8)
                    }
                    if let failure = engine.failure { failureCard(failure) }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .task(id: scrollEvent) {
                // Scroll only at message/response boundaries, never on every text snapshot.
                // Defer the command out of the state-change/layout transaction; scrolling a
                // changing LazyVStack synchronously can feed back into height estimation.
                await Task.yield()
                guard !Task.isCancelled else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollEvent: ChatScrollEvent {
        .init(lastMessageID: engine.messages.last?.id, isThinking: engine.isThinking,
              failureUserID: engine.failure?.userMessageID, inputFocused: inputFocused)
    }

    private var availabilityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if engine.isOnDeviceAI {
                DisclosureGroup(isExpanded: $showDetails) {
                    Text(engine.availability.detail).padding(.top, 6)
                } label: {
                    Label("무료 · 이 기기에서만 처리", systemImage: "iphone.gen3.radiowaves.left.and.right")
                }
            } else {
                Label("자유 대화 준비가 필요해요", systemImage: "info.circle")
                    .font(PB.F.body(14).weight(.semibold))
                Text(engine.availability.detail)
                Button("AI 상태 다시 확인", systemImage: "arrow.clockwise") { engine.refreshAvailability() }
                    .buttonStyle(.bordered).disabled(engine.isThinking)
                if let hint = engine.availability.environmentHint {
                    Text(hint).font(PB.F.body(11))
                }
            }
        }
        .font(PB.F.body(12)).foregroundStyle(PB.C.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13).background(PB.C.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("AppMascot").resizable().scaledToFit().frame(height: 135).accessibilityHidden(true)
            Text(engine.isOnDeviceAI ? "오늘은 어떤 하루였어?" : "네 기록을 함께 살펴볼까?")
                .font(PB.F.body(20).weight(.bold))
            Text(engine.isOnDeviceAI
                 ? "좋았던 일도, 마음에 걸리는 일도 들려줘.\n우리 방 이야기나 궁금한 걸 물어봐도 좋아!"
                 : "오늘 수익과 포인트는 AI 없이도\n앱의 기록으로 정확하게 확인할 수 있어.")
                .font(PB.F.body(14)).foregroundStyle(PB.C.secondary)
                .multilineTextAlignment(.center).lineSpacing(4)
            if engine.isOnDeviceAI {
                Button("퇴근 후 기분 전환할 일을 같이 골라줘") {
                    engine.send("퇴근 후 기분 전환할 일을 같이 골라줘")
                }.font(PB.F.body(13)).buttonStyle(.bordered).padding(.top, 4)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 18)
    }

    private func failureCard(_ failure: PiyakChatFailure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(failure.title, systemImage: "exclamationmark.bubble")
                .font(PB.F.body(14).weight(.semibold))
            Text(failure.detail).font(PB.F.body(13)).foregroundStyle(PB.C.secondary)
            if failure.canRetry {
                Button("다시 시도", systemImage: "arrow.clockwise") { engine.retry() }
                    .font(PB.F.body(13)).buttonStyle(.bordered).disabled(engine.isThinking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(PB.C.coral.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["오늘 수익 알려줘", "내 포인트 얼마야", "사용법 알려줘"], id: \.self) { suggestion in
                    Button { engine.send(suggestion) } label: {
                        Text(suggestion).font(PB.F.body(12))
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(PB.C.surface, in: Capsule())
                    }.disabled(engine.isThinking)
                }
            }.padding(.horizontal, 16)
        }.padding(.top, 6)
    }

    private var inputBar: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("삐약이에게 이야기하기", text: $input, axis: .vertical)
                    .font(PB.F.body(15)).lineLimit(1...5).focused($inputFocused)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(PB.C.surface, in: RoundedRectangle(cornerRadius: 22))
                    .onSubmit(submit)
                    .onChange(of: input) { _, value in
                        if value.count > PiyakConversation.maximumInput {
                            input = String(value.prefix(PiyakConversation.maximumInput))
                        }
                    }
                if engine.isThinking {
                    Button { engine.cancel() } label: {
                        Image(systemName: "stop.fill").frame(width: 44, height: 44)
                            .background(PB.C.coral.opacity(0.12), in: Circle())
                    }.accessibilityLabel("응답 생성 멈추기")
                } else {
                    Button(action: submit) {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold))
                            .foregroundStyle(PB.C.ink).frame(width: 44, height: 44)
                            .background(canSend ? PB.C.brandYellow : PB.C.secondary.opacity(0.15), in: Circle())
                    }.accessibilityLabel("메시지 보내기").disabled(!canSend)
                }
            }
            if input.count > 650 {
                Text("\(input.count) / \(PiyakConversation.maximumInput)자")
                    .font(PB.F.body(10)).foregroundStyle(PB.C.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(PB.C.bg)
    }

    private var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !engine.isThinking }
    private func submit() {
        guard canSend else { return }
        let text = input
        input = ""
        engine.send(text)
    }
}

private struct ChatScrollEvent: Hashable {
    let lastMessageID: UUID?
    let isThinking: Bool
    let failureUserID: UUID?
    let inputFocused: Bool
}

private struct ChatBubble: View, Equatable {
    let message: PiyakChatMessage
    let streaming: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .piyak {
                Image("AppMascot").resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true)
            } else { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 6) {
                Text(message.role == .piyak
                     ? PiyakChatFormatting.attributed(message.text, streaming: !message.isComplete)
                     : AttributedString(message.text))
                    .font(PB.F.body(15)).lineSpacing(4).textSelection(.enabled)
                if message.role == .piyak {
                    if message.source == .records {
                        Label("앱 기록에서 확인", systemImage: "checkmark.shield")
                            .font(PB.F.body(10)).foregroundStyle(PB.C.secondary)
                    } else if message.source == .memory || message.source == .groundedConversation {
                        Label(message.source == .memory ? "직접 말해 준 정보" : "이름·취향은 직접 말해 준 정보", systemImage: "quote.bubble")
                            .font(PB.F.body(10)).foregroundStyle(PB.C.secondary)
                    }
                    if !message.isComplete {
                        Text(streaming ? "답변을 쓰고 있어요…" : "응답이 중단되었어요")
                            .font(PB.F.body(10)).foregroundStyle(PB.C.secondary)
                    }
                }
            }
            .foregroundStyle(PB.C.textBrown)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(message.role == .user ? PB.C.coral.opacity(0.12) : PB.C.surface,
                        in: UnevenRoundedRectangle(topLeadingRadius: message.role == .piyak ? 5 : 18,
                                                   bottomLeadingRadius: 18, bottomTrailingRadius: 18,
                                                   topTrailingRadius: message.role == .user ? 5 : 18))
            if message.role == .piyak { Spacer(minLength: 22) }
        }.frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}
