import SwiftUI

enum UsageGuidePage: Int, CaseIterable {
    case welcome, work, watch, decorate

    var eyebrow: String {
        switch self {
        case .welcome: "반가워요, 우리는 삐약뱅크예요"
        case .work: "나의 시간을 소중하게"
        case .watch: "손목 위에서도 함께"
        case .decorate: "일하는 하루에 작은 즐거움"
        }
    }
    var title: String {
        switch self {
        case .welcome: "일하는 나에게,\n작은 친구 하나."
        case .work: "일한 시간을\n차곡차곡 기록해요"
        case .watch: "Apple Watch에서도\n삐약이와 함께해요"
        case .decorate: "차곡차곡 모아서,\n나만의 작은 방으로"
        }
    }
    var detail: String {
        switch self {
        case .welcome: "근무 시간을 기록하고 예상 수익을 확인하며, 삐약이의 작은 세상을 꾸미는 앱이에요."
        case .work: "근무를 시작하고, 쉴 때는 잠깐 휴식. 마친 근무와 예상 수익은 기록 탭에서 확인해요."
        case .watch: "손목에서 예상 수익을 확인하고, 근무 시작·휴식·재개·마침까지 할 수 있어요."
        case .decorate: "타이머로 일한 만큼 꾸미기 포인트를 모아요. 마음에 드는 옷과 가구로 삐약이의 방을 채워요."
        }
    }
    var symbol: String {
        switch self {
        case .welcome: "heart.fill"
        case .work: "clock.fill"
        case .watch: "applewatch"
        case .decorate: "sparkles"
        }
    }
    var tint: Color { self == .work || self == .decorate ? PB.C.mint : PB.C.lilac }
}

/// A presentation-only tour: it has no session, persistence or WatchConnectivity dependency.
struct UsageGuideView: View {
    enum Mode { case firstLaunch, replay }
    let mode: Mode
    let onFinish: () -> Void

    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page: UsageGuidePage = .welcome
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermal = ProcessInfo.processInfo.thermalState
    @State private var exampleBeat = 0
    @AccessibilityFocusState private var headingFocused: Bool

    private var active: Bool { visible && phase == .active }
    private var motionReduced: Bool {
        #if DEBUG
        if CommandLine.arguments.contains("--piyak-reduce-motion") { return true }
        #endif
        return reduceMotion
    }
    private var motionAllowed: Bool {
        !motionReduced && !lowPower && thermal != .serious && thermal != .critical
    }
    private var playbackKey: String { "\(page.rawValue)-\(active)-\(motionAllowed)" }
    private let exampleAmounts = [0, 1_250, 1_250, 1_250, 2_500, 2_500]
    private let exampleStates = ["근무 시작", "일하는 중", "잠깐 휴식", "계속 일하기", "일하는 중", "근무 마침"]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 22) {
                            hero(height: typeSize.isAccessibilitySize ? 210 : min(380, max(235, geometry.size.height * 0.43)))
                                .id("guide-top")
                            VStack(spacing: 12) {
                                Text(page.eyebrow).font(.subheadline.weight(.semibold)).foregroundStyle(PB.C.accent)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(page.title)
                                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityFocused($headingFocused)
                                Text(page.detail).font(.body).foregroundStyle(PB.C.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            notes.fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 24).padding(.bottom, 24)
                        .frame(maxWidth: 620).frame(maxWidth: .infinity)
                    }
                    .onChange(of: page) { _, _ in
                        proxy.scrollTo("guide-top", anchor: .top)
                        headingFocused = true
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    move(by: value.translation.width < 0 ? 1 : -1)
                })
                footer
            }
        }
        .background(PB.C.bg.ignoresSafeArea()).foregroundStyle(PB.C.textBrown)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            thermal = ProcessInfo.processInfo.thermalState
        }
        .task(id: playbackKey) {
            exampleBeat = motionAllowed ? 0 : 5
            guard page == .work, active, motionAllowed else { return }
            for beat in 1...5 {
                do { try await Task.sleep(for: .seconds(0.9)) } catch { return }
                guard !Task.isCancelled else { return }
                exampleBeat = beat
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                if typeSize.isAccessibilitySize {
                    position
                } else {
                    Text("삐약뱅크 사용 가이드").font(.caption.weight(.semibold)).foregroundStyle(PB.C.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    ForEach(UsageGuidePage.allCases, id: \.rawValue) { item in
                        Capsule().fill(item == page ? PB.C.accent : PB.C.secondary.opacity(0.18))
                            .frame(width: item == page ? 26 : 7, height: 7)
                    }
                }.accessibilityHidden(true)
            }
            Spacer(minLength: 4)
            if !typeSize.isAccessibilitySize { position }
            if mode == .replay {
                Button(action: onFinish) {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                        .background(PB.C.surface, in: Circle())
                }.accessibilityLabel("가이드 닫기")
            }
        }.padding(.horizontal, 24).padding(.vertical, 14)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
    }

    private var position: some View {
        Text("\(page.rawValue + 1) / 4").font(.subheadline.monospacedDigit().weight(.semibold)).fixedSize()
            .accessibilityLabel("전체 4장 중 \(page.rawValue + 1)번째 안내")
    }

    private func hero(height: CGFloat) -> some View {
        UsageGuideSceneView(page: page, active: active, animated: motionAllowed)
            .allowsHitTesting(false).accessibilityHidden(true)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: 36)
                    .fill(LinearGradient(colors: [page.tint.opacity(0.8), PB.C.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(alignment: .topLeading) {
                if !typeSize.isAccessibilitySize {
                    Label(page == .watch ? "iPhone + Apple Watch" : "삐약이와 함께", systemImage: page.symbol)
                        .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 9)
                        .background(PB.C.surface.opacity(0.92), in: Capsule())
                        .padding(16).accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottom) {
                if page == .work && !typeSize.isAccessibilitySize {
                    workExample.padding(14)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 36))
    }

    private var workExample: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("예상 수익 · 사용 예시").font(.caption).foregroundStyle(PB.C.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(exampleAmounts[exampleBeat].won).font(.system(.title2, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Text(exampleStates[exampleBeat]).font(.subheadline.bold()).foregroundStyle(PB.C.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).background(PB.C.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var notes: some View {
        switch page {
        case .welcome:
            Label("회원가입 없이 · 광고 없이", systemImage: "checkmark.seal.fill")
                .font(.subheadline).foregroundStyle(PB.C.secondary)
        case .work:
            VStack(spacing: 16) {
                if typeSize.isAccessibilitySize { workExample }
                Text("입력한 시급 × 휴식을 뺀 근무 시간으로 계산해요.\n예상 수익에는 세금·수당이 반영되지 않아요.")
                    .font(.footnote).foregroundStyle(PB.C.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .watch:
            VStack(alignment: .leading, spacing: 10) {
                Label("근무 제어는 iPhone 연결이 필요해요", systemImage: "iphone.radiowaves.left.and.right")
                Label("iPhone만으로도 사용할 수 있어요", systemImage: "checkmark.circle")
            }.font(.footnote).foregroundStyle(PB.C.secondary)
        case .decorate:
            VStack(spacing: 8) {
                Text("타이머 근무 10분에 100P").font(.headline).foregroundStyle(PB.C.accent)
                Text("휴식 제외 · 시급과 무관 · 근무를 마칠 때 적립\n한국 시간 날짜별 최대 4,800P")
                    .font(.footnote).foregroundStyle(PB.C.secondary)
                Text("포인트는 현금 가치가 없는 꾸미기 전용 보상이에요.")
                    .font(.caption).foregroundStyle(PB.C.secondary)
            }.multilineTextAlignment(.center).padding(18).frame(maxWidth: .infinity)
                .background(PB.C.surface, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if page != .welcome {
                Button("이전") { move(by: -1) }
                    .font(.body.weight(.semibold)).frame(minWidth: 60, minHeight: 52)
            }
            Button {
                if page == .decorate { onFinish() } else { move(by: 1) }
            } label: {
                Text(page == .decorate ? (mode == .firstLaunch ? "기본 시급 설정하기" : "가이드 마치기") : "다음")
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.buttonStyle(GameButtonStyle())
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
        .frame(maxWidth: 620).frame(maxWidth: .infinity).background(PB.C.bg)
    }

    private func move(by offset: Int) {
        guard let next = UsageGuidePage(rawValue: page.rawValue + offset) else { return }
        exampleBeat = motionAllowed ? 0 : 5
        page = next
    }
}
