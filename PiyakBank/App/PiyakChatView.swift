import SwiftUI
import SwiftData

/// 홈에서 삐약이를 탭하면 올라오는 채팅 시트.
/// 사용: .sheet { PiyakChatView(engine: PiyakChatEngine(container:snapshot:)) }
struct PiyakChatView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine: PiyakChatEngine
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    init(engine: PiyakChatEngine) {
        _engine = StateObject(wrappedValue: engine)
    }

    private let suggestions = ["오늘 얼마 벌었어?", "이번 주 정산해줘", "심심해!"]

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            inputBar
        }
        .background(PB.C.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.impact, trigger: engine.messages.count)
    }

    // MARK: 헤더

    private var header: some View {
        HStack(spacing: 10) {
            Image("piyak_base")
                .resizable().scaledToFit()
                .frame(width: 38, height: 38)
                .padding(5)
                .background(PB.C.brandYellow.opacity(0.25), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("삐약이")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(PB.C.textBrown)
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text(engine.isOnDeviceAI ? "온디바이스 AI" : "기본 모드")
                        .font(PB.F.body(11))
                        .foregroundStyle(PB.C.textBrown.opacity(0.55))
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PB.C.textBrown.opacity(0.5))
                    .padding(10)
                    .background(.white, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    // MARK: 메시지 리스트

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    if engine.messages.isEmpty {
                        emptyState
                    }
                    ForEach(engine.messages) { msg in
                        ChatBubble(message: msg)
                    }
                    if engine.isThinking {
                        ThinkingBubble()
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: engine.messages) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: engine.isThinking) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: 빈 상태 (첫 진입)

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image("piyak_base")
                .resizable().scaledToFit()
                .frame(height: 110)
                .padding(.top, 18)
            Text("궁금한 거 물어봐!\n네가 번 돈은 내가 다 기억하고 있어 삐약!")
                .font(PB.F.body(14))
                .foregroundStyle(PB.C.textBrown.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        engine.send(s)
                    } label: {
                        Text(s)
                            .font(PB.F.body(13))
                            .foregroundStyle(PB.C.textBrown)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.white, in: Capsule())
                            .overlay(Capsule().strokeBorder(PB.C.brandYellow, lineWidth: 1.5))
                    }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }

    // MARK: 입력바

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("삐약이에게 말 걸기...", text: $input, axis: .vertical)
                .font(PB.F.body(15))
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: PB.C.textBrown.opacity(0.06), radius: 6, y: 2)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(canSend ? PB.C.coral : PB.C.textBrown.opacity(0.2),
                                in: Circle())
            }
            .disabled(!canSend)
            .animation(.easeOut(duration: 0.15), value: canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PB.C.bg)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !engine.isThinking
    }

    private func submit() {
        guard canSend else { return }
        let text = input
        input = ""
        engine.send(text)
    }
}

// MARK: - 말풍선

private struct ChatBubble: View {
    let message: PiyakChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .piyak {
                Image("piyak_base")
                    .resizable().scaledToFit()
                    .frame(width: 26, height: 26)
                    .padding(4)
                    .background(PB.C.brandYellow.opacity(0.25), in: Circle())
            } else {
                Spacer(minLength: 52)
            }

            Text(message.text)
                .font(PB.F.body(15))
                .lineSpacing(3)
                .foregroundStyle(message.role == .user ? .white : PB.C.textBrown)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    message.role == .user ? PB.C.coral : .white,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 18,
                        bottomLeadingRadius: message.role == .piyak ? 6 : 18,
                        bottomTrailingRadius: message.role == .user ? 6 : 18,
                        topTrailingRadius: 18
                    )
                )
                .shadow(color: PB.C.textBrown.opacity(0.06), radius: 6, y: 2)

            if message.role == .piyak {
                Spacer(minLength: 52)
            }
        }
        .frame(maxWidth: .infinity,
               alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - 생각 중 (점 3개 바운스)

private struct ThinkingBubble: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image("piyak_base")
                .resizable().scaledToFit()
                .frame(width: 26, height: 26)
                .padding(4)
                .background(PB.C.brandYellow.opacity(0.25), in: Circle())

            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(PB.C.textBrown.opacity(0.35))
                            .frame(width: 7, height: 7)
                            .offset(y: -abs(sin((t - Double(i) * 0.18) * 3.4)) * 4)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(.white, in: UnevenRoundedRectangle(
                    topLeadingRadius: 18, bottomLeadingRadius: 6,
                    bottomTrailingRadius: 18, topTrailingRadius: 18))
                .shadow(color: PB.C.textBrown.opacity(0.06), radius: 6, y: 2)
            }
            Spacer(minLength: 52)
        }
    }
}
