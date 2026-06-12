import SwiftUI
import SwiftData
import UserNotifications
import Combine
import StoreKit

@main
struct PiyakBankApp: App {
    @StateObject private var router = AppRouter()
    @State private var container: ModelContainer = {
        let schema = Schema([CatalogItem.self, OwnedItem.self,
                             PointTransaction.self, WorkSession.self])
        return try! ModelContainer(for: schema)
    }()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .modelContainer(container)
                .tint(PB.C.coral)
                .onOpenURL { router.handle(url: $0) }
        }
    }
}

// MARK: 딥링크 라우터

final class AppRouter: ObservableObject {
    enum Tab: Hashable { case home, decorate, settings }
    @Published var tab: Tab = .home
    
    /// piyakbank://home 등
    func handle(url: URL) {
        switch url.host {
        case "home": tab = .home
        case "decorate": tab = .decorate
        case "settings": tab = .settings
        default: break
        }
    }
}

struct RootView: View {
    @EnvironmentObject var router: AppRouter
    @Environment(\.modelContext) private var context
    
    @StateObject private var sessionHolder = ServiceHolder()
    @State private var showSplash = true
    
    var body: some View {
        ZStack {
            if let session = sessionHolder.session {
                TabView(selection: $router.tab) {
                    HomeView()
                        .environmentObject(session)
                        .tabItem { Label("홈", systemImage: "house.fill") }
                        .tag(AppRouter.Tab.home)
                    
                    DecorateView()
                        .environmentObject(sessionHolder.store)
                        .tabItem { Label("꾸미기", systemImage: "paintbrush.fill") }
                        .tag(AppRouter.Tab.decorate)
                    
                    SettingsView()
                        .environmentObject(session)
                        .tabItem { Label("설정", systemImage: "gearshape.fill") }
                        .tag(AppRouter.Tab.settings)
                }
            }
            
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            sessionHolder.bootstrap(context: context)
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
        }
    }
}

/// 서비스 lifetime 보관 (EconomyStore / Scheduler / SessionController / Watch / Store)
final class ServiceHolder: ObservableObject {
    @Published var session: SessionController!
    private var economy: EconomyStore!
    private var scheduler: NotificationScheduler!
    private var watch: WatchSync!
    @Published var store: StoreManager!
    private var bridge: WatchBridge!
    private var didBoot = false
    
    @MainActor
    func bootstrap(context: ModelContext) {
        guard !didBoot else { return }
        didBoot = true
        economy = EconomyStore(context: context)
        economy.seedIfNeeded()
        scheduler = NotificationScheduler()
        session = SessionController(context: context, economy: economy, scheduler: scheduler)
        
        watch = WatchSync()
        watch.onRemoteCommand = { [weak self] cmd, wage in
            self?.session.handleRemoteCommand(cmd, wage: wage)
        }
        watch.activate()
        bridge = WatchBridge(watch: watch)
        session.syncDelegate = bridge
        
        store = StoreManager()
        store.onPurchased = { [weak self] catalogId in self?.economy.grantIAP(catalogId) }
        
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        Task { _ = await scheduler.requestAuth(); await store.loadProducts() }
        NotificationCenter.default.addObserver(
            forName: .piyakEquippedChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.watch.send(equipped: self.economy.equippedMap())
            }
        }
        watch.send(equipped: economy.equippedMap())   // 부팅 시 1회 초기 전송
        session.recoverIfNeeded()
    }
}

/// SessionSyncing → WatchSync 어댑터
final class WatchBridge: SessionSyncing {
    let watch: WatchSync
    init(watch: WatchSync) { self.watch = watch }
    func didUpdateSession(_ snapshot: SessionSnapshot) {
        Task { @MainActor in watch.send(snapshot: snapshot) }
    }
}

// MARK: 알림 탭 → 딥링크

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    func userNotificationCenter(_ c: UNUserNotificationCenter,
                                willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter,
                                didReceive r: UNNotificationResponse) async {
        if let link = r.notification.request.content.userInfo["deeplink"] as? String,
           let url = URL(string: link) {
            await MainActor.run { UIApplication.shared.open(url) }
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var session: SessionController
    @Query private var transactions: [PointTransaction]
    @State private var showRestoreDone = false
    
    // MARK: 원장 기반 통계
    private var accruals: [PointTransaction] {
        transactions.filter { $0.kind == .accrual }
    }
    private var totalEarned: Int {
        accruals.reduce(0) { $0 + $1.amount }
    }
    private var daysTogether: Int {
        guard let first = accruals.map(\.date).min() else { return 1 }
        return (Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 0) + 1
    }
    private var workedDays: Int {
        Set(accruals.map { Calendar.current.startOfDay(for: $0.date) }).count
    }
    private var bestDay: Int {
        Dictionary(grouping: accruals) { Calendar.current.startOfDay(for: $0.date) }
            .values.map { $0.reduce(0) { $0 + $1.amount } }.max() ?? 0
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    profileCard
                    statRow
                    settingsCard(title: "알림") {
                        HStack {
                            Text("주기 알림 간격").font(PB.F.body(15))
                                .foregroundStyle(PB.C.textBrown)
                            Spacer()
                            Picker("", selection: $session.interval) {
                                ForEach(NotificationScheduler.Interval.allCases, id: \.self) { iv in
                                    Text("\(iv.rawValue)분").tag(iv)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 180)
                        }
                    }
                    settingsCard(title: "구매") {
                        Button {
                            Task {
                                try? await AppStore.sync()
                                showRestoreDone = true
                            }
                        } label: {
                            HStack {
                                Text("구매 복원").font(PB.F.body(15))
                                    .foregroundStyle(PB.C.textBrown)
                                Spacer()
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(PB.C.coral)
                            }
                        }
                    }
                    settingsCard(title: "정보") {
                        VStack(spacing: 12) {
                            infoRow("버전", value: "1.0.0")
                            Divider()
                            Link(destination: URL(string: "https://github.com/eric91405/piyak-bank-ios")!) {
                                HStack {
                                    Text("GitHub").font(PB.F.body(15))
                                        .foregroundStyle(PB.C.textBrown)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(PB.C.textBrown.opacity(0.4))
                                }
                            }
                            Divider()
                            infoRow("만든 사람", value: "김민서")
                        }
                    }
                }
                .padding(16)
            }
            .background(PB.C.bg.ignoresSafeArea())
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .alert("구매 복원", isPresented: $showRestoreDone) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("구매 내역 복원을 요청했어요.")
            }
        }
    }
    
    // MARK: 프로필 카드
    private var profileCard: some View {
        VStack(spacing: 10) {
            Image("piyak_base")
                .resizable().scaledToFit()
                .frame(height: 88)
                .padding(10)
                .background(PB.C.brandYellow.opacity(0.22), in: Circle())
            Text("삐약이와 함께한 지 \(daysTogether)일")
                .font(PB.F.body(15)).bold()
                .foregroundStyle(PB.C.textBrown)
            HStack(spacing: 5) {
                Text("통산 적립")
                    .font(PB.F.body(12))
                    .foregroundStyle(PB.C.textBrown.opacity(0.5))
                Text(totalEarned.won)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(PB.C.coral)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(.white, in: RoundedRectangle(cornerRadius: PB.R.xl))
        .shadow(color: PB.C.textBrown.opacity(0.07), radius: 12, y: 4)
    }
    
    private var statRow: some View {
        HStack(spacing: 10) {
            statCell("calendar", title: "적립일", value: "\(workedDays)일")
            statCell("crown.fill", title: "최고 하루", value: bestDay.won)
            statCell("bell.badge.fill", title: "알림 간격", value: "\(session.interval.rawValue)분")
        }
    }
    private func statCell(_ icon: String, title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PB.C.coral)
            Text(title).font(PB.F.body(11))
                .foregroundStyle(PB.C.textBrown.opacity(0.5))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PB.C.textBrown)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: PB.R.lg))
        .shadow(color: PB.C.textBrown.opacity(0.05), radius: 8, y: 3)
    }
    
    // MARK: 카드 컨테이너
    private func settingsCard<Content: View>(title: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(PB.F.body(12)).bold()
                .foregroundStyle(PB.C.textBrown.opacity(0.45))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: PB.R.lg))
        .shadow(color: PB.C.textBrown.opacity(0.05), radius: 8, y: 3)
    }
    
    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(PB.F.body(15)).foregroundStyle(PB.C.textBrown)
            Spacer()
            Text(value).font(PB.F.body(15))
                .foregroundStyle(PB.C.textBrown.opacity(0.5))
        }
    }
}

// MARK: 스플래시

struct SplashView: View {
    @State private var appear = false
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 1.0, green: 0.98, blue: 0.93), PB.C.bg],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // 앱 아이콘 타일
                Image("splash_logo")
                    .resizable().scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: PB.C.textBrown.opacity(0.18), radius: 18, y: 8)
                    .scaleEffect(appear ? 1.0 : 0.7)
                    .opacity(appear ? 1 : 0)
                
                // 워드마크
                Text("삐약뱅크")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(PB.C.textBrown)
                    .padding(.top, 22)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)
                
                Text("내 시간이 돈이 되는 순간")
                    .font(PB.F.body(14))
                    .foregroundStyle(PB.C.textBrown.opacity(0.45))
                    .padding(.top, 8)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)
                
                Spacer()
                
                // 로딩 점
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(PB.C.coral)
                                .frame(width: 8, height: 8)
                                .opacity(0.3 + 0.7 * abs(sin((t - Double(i) * 0.22) * 2.8)))
                        }
                    }
                }
                .padding(.bottom, 24)
                
                Text("PiyakBank")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PB.C.textBrown.opacity(0.3))
                    .padding(.bottom, 28)
                    .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.35)) { appear = true }
        }
    }
}
