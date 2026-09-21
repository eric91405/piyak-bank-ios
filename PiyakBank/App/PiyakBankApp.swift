import SwiftUI
import SwiftData
import UserNotifications
import Combine

@main
struct PiyakBankApp: App {
    @StateObject private var persistence = AppPersistence()
    @StateObject private var router = AppRouter()
    init() { UNUserNotificationCenter.current().delegate = NotificationDelegate.shared }
    var body: some Scene {
        WindowGroup {
            Group {
                if let container = persistence.container {
                    RootView().modelContainer(container).environmentObject(router)
                } else {
                    ContentUnavailableView {
                        Label("기록을 열지 못했어요", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("기존 기록은 삭제하지 않았어요. 저장 공간을 확인하고 다시 시도해 주세요. 문제가 계속되면 지원팀에 문의해 주세요.")
                    } actions: {
                        Button("다시 시도") { persistence.load() }.buttonStyle(.borderedProminent)
                        Link("지원 문의", destination: URL(string: "mailto:\(AppConfig.supportEmail)")!)
                    }
                }
            }
            .modifier(DevelopmentDisplayOptions())
            .tint(PB.C.accent)
            .environment(\.locale, Locale(identifier: "ko_KR"))
            .onOpenURL { router.handle(url: $0) }
        }
    }
}

@MainActor
final class AppPersistence: ObservableObject {
    @Published var container: ModelContainer?
    init() { load() }
    func load() {
        let schema = Schema([CatalogItem.self, OwnedItem.self, PointTransaction.self, WorkSession.self, RewardReceipt.self])
        do {
            // An unavailable group or failed migration must show the recovery UI,
            // never open a blank database or resume writes to an obsolete copy.
            guard let shared = Self.sharedStoreURL() else { throw StoreMigration.Failure.incompleteStore }
            try StoreMigration.prepare(legacyCandidates: Self.legacyStoreURLs(schema: schema, destination: shared), destination: shared)
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: shared))
            container?.mainContext.autosaveEnabled = false
        } catch { container = nil }
    }

    private static func sharedStoreURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup)?
            .appending(path: "PiyakBank.store")
    }

    static func legacyStoreURLs(schema: Schema, destination: URL) -> [URL] {
        [ModelConfiguration(schema: schema).url,
         URL.applicationSupportDirectory.appending(path: "default.store"),
         destination.deletingLastPathComponent().appending(path: "default.store")]
    }

}

@MainActor
final class AppRouter: ObservableObject {
    enum Tab: Hashable { case home, decorate, history, settings }
    @Published var tab: Tab = .home
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "piyakbank" else { return }
        switch url.host {
        case "home": tab = .home
        case "decorate": tab = .decorate
        case "history": tab = .history
        case "settings": tab = .settings
        default: break
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @AppStorage("did_onboard") private var didOnboard = false
    @StateObject private var services = ServiceHolder()
    var body: some View {
        Group {
            if let session = services.session {
                Group {
                    if didOnboard {
                        TabView(selection: $router.tab) {
                            HomeView().tabItem { Label("삐약이", systemImage: "house.fill") }.tag(AppRouter.Tab.home)
                            DecorateView().tabItem { Label("꾸미기", systemImage: "sparkles") }.tag(AppRouter.Tab.decorate)
                            HistoryView().tabItem { Label("기록", systemImage: "calendar") }.tag(AppRouter.Tab.history)
                            SettingsView().tabItem { Label("설정", systemImage: "gearshape.fill") }.tag(AppRouter.Tab.settings)
                        }
                    } else {
                        OnboardingView { didOnboard = true }
                    }
                }
                .environmentObject(session)
                .alert("변경을 완료하지 못했어요", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
                    Button("확인") { session.errorMessage = nil }
                } message: { Text(session.errorMessage ?? "다시 시도해 주세요.") }
            } else if let error = services.error {
                ContentUnavailableView {
                    Label("준비를 마치지 못했어요", systemImage: "externaldrive.badge.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("다시 시도") { services.bootstrap(context: context) }
                    Link("지원 문의", destination: URL(string: "mailto:\(AppConfig.supportEmail)")!)
                }
            } else { ProgressView("삐약이의 방을 여는 중") }
        }
        .task {
            NotificationRouting.install { [weak router] url in router?.handle(url: url) }
            services.bootstrap(context: context)
        }
        .onChange(of: phase) { _, value in
            if value == .active { services.refresh() }
            else { services.checkpointRewards() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in services.refresh() }
    }
}

@MainActor
final class ServiceHolder: ObservableObject {
    @Published var session: SessionController?
    @Published var error: String?
    private var watch: WatchSync?
    private var bridge: WatchBridge?
    private var equipmentObserver: AnyCancellable?

    func bootstrap(context: ModelContext) {
        guard session == nil else { return }
        do {
            let economy = EconomyStore(context: context)
            try economy.migrateRewardsIfNeeded()
            try economy.seedIfNeeded()
            let controller = SessionController(context: context, economy: economy, scheduler: NotificationScheduler(), beforeReset: {
                guard let storeURL = context.container.configurations.first?.url else { throw StoreMigration.Failure.incompleteStore }
                try StoreMigration.removeLegacyCopies(
                    legacyCandidates: AppPersistence.legacyStoreURLs(schema: context.container.schema, destination: storeURL),
                    destination: storeURL)
            })
            try controller.recoverIfNeeded()
            let watch = WatchSync()
            self.watch = watch
            watch.onRemoteCommand = { [weak controller] command in
                guard UserDefaults.standard.bool(forKey: "did_onboard") else { throw SetupError.onboarding }
                try controller?.handleRemoteCommand(command)
            }
            watch.onRequestSnapshot = { [weak controller] in controller?.refreshSnapshot() }
            let bridge = WatchBridge(watch: watch)
            self.bridge = bridge
            controller.syncDelegate = bridge
            self.session = controller
            self.error = nil
            equipmentObserver = NotificationCenter.default.publisher(for: .piyakEquippedChanged)
                .sink { [weak self] _ in Task { @MainActor in self?.refreshEquipment() } }
            try watch.send(equipped: economy.equippedMap())
            watch.activate()
            controller.refreshSnapshot()
        } catch {
            self.error = "기존 기록을 보존했어요. \(error.localizedDescription)"
        }
    }
    func refresh() {
        checkpointRewards()
        session?.refreshSnapshot()
        session?.updateReminders()
        refreshEquipment()
    }
    func checkpointRewards() {
        session?.perform { try session?.checkpointRewards() }
    }
    private func refreshEquipment() {
        guard let session else { return }
        do { try watch?.send(equipped: session.economy.equippedMap()) }
        catch { session.errorMessage = error.localizedDescription }
    }
    private enum SetupError: LocalizedError {
        case onboarding
        var errorDescription: String? { "iPhone 앱에서 처음 설정을 마쳐 주세요." }
    }
}

@MainActor
final class WatchBridge: SessionSyncing {
    let watch: WatchSync
    init(watch: WatchSync) { self.watch = watch }
    func didUpdateSession(_ snapshot: SessionSnapshot) { watch.send(snapshot: snapshot) }
}

/// Set by the root view once the router exists. Routing in-process beats asking
/// the system to re-open our own URL scheme just to switch tabs.
@MainActor
enum NotificationRouting {
    private static var open: ((URL) -> Void)?
    private static var pendingURL: URL?
    static func install(_ handler: @escaping (URL) -> Void) {
        open = handler
        if let pendingURL { handler(pendingURL); self.pendingURL = nil }
    }
    static func route(_ url: URL) {
        if let open { open(url) } else { pendingURL = url }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let link = response.notification.request.content.userInfo["deeplink"] as? String,
              let url = URL(string: link), url.scheme == "piyakbank" else { return }
        await MainActor.run { NotificationRouting.route(url) }
    }
}

// Launch-only visual QA overrides. They never exist in a Release build and do not
// change system preferences or the user's stored app settings.
private struct DevelopmentDisplayOptions: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--piyak-accessibility") {
            content.environment(\.dynamicTypeSize, .accessibility3)
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--piyak-dark") ? .dark : nil)
        } else {
            content.preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--piyak-dark") ? .dark : nil)
        }
        #else
        content
        #endif
    }
}
