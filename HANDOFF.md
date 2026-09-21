# 인수인계 — 출시 전 수정·개선 작업

## 인수 상태 (2026-09-21)

아래 패치 2개는 이미 `94801b9`, `011f809`로 적용되어 있습니다. **`git am`을 다시 실행하지 마세요.** 후속 작업에서는 구조·캐시·리소스 정리를 유지하고 저장소 이전, 알림 재시도, 워치 이미지 복구를 보완했습니다. 현재 진행 상황과 남은 검증은 [출시 검증 기록](docs/RELEASE_VALIDATION.md)에 기록합니다.

출시 안정화 코드는 PR #3까지 `main`에 병합했습니다(앱 코드 기준 `8ea2a10`). 테스트 115개·초기 SwiftData 스키마 이전·iPhone/Watch/위젯 Release 빌드는 [병합 후 CI](https://github.com/eric91405/piyak-bank-ios/actions/runs/35569409466)에서 통과했습니다. iPhone 시뮬레이터 주요 흐름은 확인했지만 전체 출시 검증 완료 상태는 아닙니다. 다음 작업은 [남은 검증 체크리스트](docs/RELEASE_VALIDATION.md#제출-전-남은-검증)의 iPad 다중 창·접근성·최소 OS 실행과 실기기 시험입니다. Apple Developer Program 미가입으로 배포 서명 Archive·TestFlight·심사 제출은 진행하지 않았습니다.

GitHub Pages는 `main` 병합 전에도 `codex/app-store-launch`의 `/docs`를 소스로 게시할 수 있습니다. [게시 절차](docs/PUBLISHING.md)를 따릅니다. 네이티브 Xcode 테스트 타깃 추가는 개발 편의 개선이며 App Store 제출 필수 조건은 아닙니다. 기존 Swift Package 테스트와 CI를 유지합니다. 아래 기능 추가 목록은 별도 로드맵이며 이번 안정화 범위에 포함되지 않습니다.

## Android · Wear OS 병행 개발 (2026-09-21)

사용자 요청으로 Android 휴대폰·태블릿·홈 화면 위젯과 **Wear OS 동반 앱까지** 포함해 `android/`에 독립 Gradle 프로젝트를 추가했습니다. 기존 iOS 코드·검증 상태를 Android 완료 상태로 대체하지 않습니다. 새 Android 앱과 iOS 앱 사이의 계정·기록 동기화는 구현 범위에 없습니다.

현재 구현은 Compose 온보딩·4개 탭·큰 화면 배치, 시간 기록·급여·보상, 81종 아이템·OpenGL 방, SQLite 저장·revision 충돌 방지, 알림·위젯·CSV·설정, Android 휴대폰 원본을 제어하는 Wear OS 앱입니다. AI·광고·인앱 결제·앱 계정은 추가하지 않았습니다.

확인된 중간 결과:

- Kotlin 코어 테스트 45개와 앱 JVM 테스트 15개 통과.
- API 35에서 SQLite instrumentation 테스트 8개 통과.
- 휴대폰·Wear OS Debug APK와 휴대폰 instrumentation 테스트 APK 빌드 성공.
- **Release·Lint 최종 결과, 실제 3D GPU 화면과 전체 UI·접근성·최소 OS, 실물 시계 연결·알림·위젯·배터리는 아직 완료로 기록하지 않습니다.**
- Play Console 가입·유형·권한은 아직 확인되지 않았습니다. Play 업로드·배포 설치·심사 완료를 주장하지 않습니다.

후속 작업은 [Android 개발 문서](android/README.md), [UI 테스트 계획](android/docs/UI_TEST_PLAN.md), [Play 출시 체크리스트](android/docs/PLAY_STORE.md)의 미확인 항목을 실제 증거로 갱신하는 것입니다. 테스트 개수만으로 화면·실기기·배포 시험까지 통과했다고 표현하지 마세요.

### 구조와 실행

- `android/core/`: 순수 Kotlin 도메인·금액·보상·기록·시계 명령 정책.
- `android/app/`: Compose 휴대폰·태블릿 화면, SQLite, OpenGL 장면, 알림·위젯·시계 통신.
- `android/wear/`: 연결된 Wear OS 앱. `app`의 장면과 에셋을 공유합니다.
- `android/scripts/`: iOS SceneKit 원본 기하를 Android 메시로 내보내고 검사합니다.

`android/`에서 실행:

```sh
nice -n 15 ./gradlew --no-daemon --max-workers=1 :core:test :app:testDebugUnitTest
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:assembleDebug :wear:assembleDebug
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:connectedDebugAndroidTest
```

마지막 명령은 합성 데이터용 QA 기기가 필요합니다. AGP 8.13.1·Kotlin 2.2.20·Gradle 8.14·JDK 17 이상, compileSdk 36을 사용합니다. 휴대폰 minSdk 26/targetSdk 36, Wear OS minSdk 30/targetSdk 35입니다. 두 앱의 applicationId는 `com.minseo.piyakbank`이며 동일 서명을 사용해야 통신합니다. versionCode는 휴대폰 1, Wear OS 1000001부터 분리했습니다.

MacBook Air M4 16GB의 발열 관리 요청을 유지합니다. Gradle worker 1개·병렬 끄기·JVM 최대 2GB를 지키고 빌드와 에뮬레이터를 순차 실행합니다. 사용하지 않는 시뮬레이터·에뮬레이터는 종료합니다. Release 서명에는 소유자가 관리하는 `PIYAK_KEYSTORE`, `PIYAK_STORE_PASSWORD`, `PIYAK_KEY_ALIAS`, `PIYAK_KEY_PASSWORD`가 필요하며 키를 저장소에 넣지 않습니다.

### 개인정보와 공개 문서

Wear OS 동기화는 Google Play services Data Layer를 사용해 연결된 기기 사이에 근무 상태·오늘 수익·잔액·장착 정보를 전달합니다. Google 클라우드의 종단 간 암호화 중계 가능성을 Android 앱 내 안내에 명시했습니다. 개발자 서버가 없거나 `INTERNET` 권한이 없다는 이유로 모든 데이터가 기기 밖으로 나가지 않는다고 설명하지 마세요.

Android 공개 정책 주소는 `/privacy-android/`로 준비하며 실제 Pages 게시와 앱 링크 접근을 제출 전에 확인합니다. 기존 iOS 공개 정책·지원 문서를 Android에 무조건 적용하지 않고, 위젯 주기·시계 연결·권한·구버전 포인트 이전 설명을 플랫폼별로 구분해야 합니다.

---

## 최초 인수 메모 (기록용)

아래는 최초 인수 당시의 기록이며 현재 작업 지시나 남은 항목 목록이 아닙니다. 최신 완료 여부는 위 인수 상태와 출시 검증 기록을 따릅니다.

claude.ai에서 레포 전체를 리뷰하고 정리한 결과다. 이 문서는 일회성 작업 지시이며, 끝나면 지워도 된다. 항구적인 프로젝트 규칙은 `CLAUDE.md`에 있다.

## 배경

`main`(c70a8be, 2026-06-14)은 학교 과제 제출본. `codex/app-store-launch`(5784338, 2026-09-17, PR #1)는 codex로 재작성한 무료 출시 후보다. StoreKit 인앱결제와 FoundationModels AI 채팅을 제거하고, 2D SVG를 코드 생성 SceneKit 3D로 교체했으며, 시급과 꾸미기 포인트를 분리하고 배포 타깃을 iOS 26.5에서 17.0으로 낮췄다.

## 이미 적용된 것 — `piyakbank-fixes.patch`의 커밋 2개

**컴파일 검증이 안 된 상태다.** 작성 환경에 Swift 툴체인이 없었다. 첫 작업은 이 패치를 적용하고 빌드를 통과시키는 것.

```sh
git checkout codex/app-store-launch
git am < piyakbank-fixes.patch
swift test --jobs 1
python3 scripts/check_release_assets.py
xcodebuild -project PiyakBank.xcodeproj -scheme PiyakBank -configuration Debug \
  -jobs 1 -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/PiyakBank CODE_SIGNING_ALLOWED=NO build
```

커밋 1 — 미사용 SVG 130개 삭제(코드 참조 0곳 확인, 앱 6.0M→5.1M, 워치 1.1M→524K), `docs/`를 GitHub Pages로 게시하는 설정 추가, 개인정보·지원 URL을 브랜치 blob 링크에서 Pages 고정 주소로 교체.

커밋 2 — 코드 9건:

1. `WorkSession.decodedSegments()`에 `@Transient` 캐시. 저장 blob을 키로 써서 롤백 시 자동 무효화
2. `HistoryView` 월 합계를 해당 월과 겹치는 기록으로 한정
3. `HomeView`에 KST 안내. 기기 시간대가 KST가 아니면 한도 초기화 시각을 기기 시각으로 환산해 표시
4. `WatchSync` 초상화 PNG를 상태 페이로드에서 분리. 착용 변경 시에만 `transferUserInfo`로 전송, 워치는 직전 초상화 유지
5. `NotificationScheduler` 문구를 단정형에서 조건형으로, 계획 미변경 시 재예약 생략
6. SwiftData 스토어를 App Group으로 이전 (복사 방식 + 실패 시 폴백)
7. `CharacterComposite`를 VoiceOver 요소로 노출, 착용 요약 레이블과 놀아주기 액션
8. `PB.C.coral` → `PB.C.accent` 이름 정정 (실제 값이 보라색, 8곳)
9. 알림 탭을 `UIApplication.open` 대신 `AppRouter` 직접 호출로

### 빌드 후 확인할 것

**6번이 가장 위험하다.** 기존 데이터가 있는 기기에 덮어 설치해서 기록·잔액·보유/착용 아이템이 보존되는지, 재실행 시 잔액 전환이 반복되지 않는지, App Group 컨테이너에 `PiyakBank.store`가 생겼는지 확인. 유실 경로가 없도록 복사+폴백으로 짰지만 검증 없이 출시하면 안 된다.

나머지: 워치 착용 변경 반영과 상태만 바뀔 때 캐릭터 유지(4), 포그라운드 재진입 시 알림 주기 유지(5), VoiceOver 방 설명과 두 번 탭 동작(7), 시간대를 KST 외로 바꿨을 때 안내 노출(3).

## 남은 작업 — 출시 블로커

- **Apple Watch 스크린샷.** watchOS 앱을 포함해 제출하면 App Store Connect가 별도로 요구한다. `docs/screenshots/`에 iPhone·iPad만 있다. 워치 시뮬레이터에서 적산 화면과 캐릭터 화면을 캡처해 추가할 것.
- **Xcode 테스트 타깃 추가.** 현재 네이티브 타깃 3개뿐이라 `swift test`로만 검증되고 ⌘U가 안 된다. File → New → Target → Unit Testing Bundle. 파일 시스템 동기화 그룹이라 `Tests/`가 자동으로 붙는다.
- **GitHub Pages 게시.** Settings → Pages → `main` 브랜치 `/docs`. 게시 후 `https://eric91405.github.io/piyak-bank-ios/privacy/`와 `/support/`가 열리는지 확인.
- 서명 Archive, TestFlight 업로드, 실물 iPhone+Watch 왕복 제어·재연결·알림·위젯 갱신 확인. 이건 사람 손과 Apple 계정이 필요하다.

## 남은 작업 — 기능 추가

우선순위 순. 앞의 셋은 v1에 넣을 만한 크기이고, 다중 알바부터는 스키마가 바뀌므로 1.1로 미루는 편이 낫다. **한 번에 하나씩, 각각 빌드를 통과시킨 뒤 다음으로 넘어갈 것.**

1. **Live Activity / 다이나믹 아일랜드.** 앱의 핵심 가치가 실시간 적산인데 잠금화면에는 5분 단위 추정 위젯뿐이다. `ActivityAttributes` 정의, 위젯 타깃을 `WidgetBundle`로 개편, `Info.plist`에 `NSSupportsLiveActivities`, `SessionController`의 start/pause/resume/stop에 수명주기 연결. `SessionSnapshot`이 이미 있어 데이터는 준비돼 있다.
2. **백업·복원.** CSV 내보내기는 있는데 가져오기가 없어 기기를 바꾸면 전부 소실된다. CloudKit private DB 동기화가 정석이고, 최소한 JSON 백업·복원이라도 필요하다. 개인정보 처리방침과 App Privacy 응답을 함께 수정해야 한다.
3. **watchOS 컴플리케이션.** 워치 앱이 있는데 문자판 컴플리케이션이 없다. 위젯 타깃 이름이 `PiyakComplication`이지만 실제로는 iOS 위젯이다.
4. **다중 알바.** 기본 시급이 하나뿐이라 근무 기록에 어디서 일했는지가 남지 않는다. 직장 이름 + 시급 프리셋. SwiftData 스키마 변경과 마이그레이션 필요.
5. **주휴수당 예상.** 주 15시간 이상 기준. 법적 단정이 아니라 "예상"으로 표시해야 한다. 야간·연장 가산도 같은 맥락.
6. **도감·목표·업적.** 아이템 전체가 76,750P인데 하루 한도가 4,800P라 8시간 근무 16일이면 다 산다. 그 뒤 포인트를 모을 이유가 없다.
7. **영어 로컬라이즈.** 현재 `.environment(\.locale, ko_KR)` 강제에 통화도 하드코딩. String Catalog로 빼는 작업은 지금이 가장 싸다.
