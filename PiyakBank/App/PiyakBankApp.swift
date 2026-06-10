import SwiftUI
import SwiftData
import UserNotifications
import Combine

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

// MARK: 루트 (3탭) + 서비스 와이어링

struct RootView: View {
    @EnvironmentObject var router: AppRouter
    @Environment(\.modelContext) private var context

    @StateObject private var sessionHolder = ServiceHolder()

    var body: some View {
        Group {
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
                        .tabItem { Label("설정", systemImage: "gearshape.fill") }
                        .tag(AppRouter.Tab.settings)
                }
            } else {
                ZStack {
                    PB.C.bg.ignoresSafeArea()
                    ProgressView()
                }
            }
        }
        .task { sessionHolder.bootstrap(context: context) }
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

// MARK: 설정

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("알림") {
                    Text("주기 알림 간격: 60분")   // 15/30/60 Picker 연결 예정
                }
                Section("정보") {
                    LabeledContent("버전", value: "1.0.0")
                }
            }
            .navigationTitle("설정")
            .scrollContentBackground(.hidden)
            .background(PB.C.bg.ignoresSafeArea())
        }
    }
}
