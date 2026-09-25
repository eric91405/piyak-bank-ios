# 인수인계 — 출시 전 수정·개선 작업

## 최신 배포 입력 상태 (2026-09-26)

사용자의 TestFlight 정상 동작 보고와 한국 단독 출시 결정을 받았습니다. 설명·심사 연락처·빌드 연결·수동 출시·부제·연령 등급·카테고리·타사 콘텐츠 없음·무료 가격·대한민국 단독 배포를 저장했습니다. Mac/Vision Pro 배포는 껐고 iPhone 3장·iPad 2장·Watch 2장을 등록했습니다. 사용자가 개인정보 게시 동의와 심사 제출을 승인하여 데이터 미수집 안내를 게시했습니다. 2026-09-26 01:56 KST에 1.0 (2)를 제출했고 Apple 화면에서 **심사 대기 중**을 확인했습니다. 제출 ID는 `619653b0-9aa4-4b2f-9972-0157e1b90097`입니다. 승인·공개 출시는 아직이며 수동 출시 설정을 유지합니다. 정확한 범위는 [App Store 입력 현황](docs/APP_STORE.md)을 따릅니다. 비공개 심사 연락처는 공개 저장소에 기재하지 않습니다.

같은 소스의 Release 시뮬레이터에서 iPad 홈·꾸미기 화면과 iPhone↔Watch 근무 시작·휴식·재개·종료를 확인했습니다. 종료 후 iPhone 잔액은 69P→110P, 오늘 보상은 41P였고 기존 장착이 유지됐습니다. Watch 장착 이미지 도착은 확인하지 못했으며 실제 기기 통신 시험과 구분합니다. 테스트 후 모든 시뮬레이터를 종료했습니다.

## 인수 상태 (2026-09-21)

아래 패치 2개는 이미 `94801b9`, `011f809`로 적용되어 있습니다. **`git am`을 다시 실행하지 마세요.** 후속 작업에서는 구조·캐시·리소스 정리를 유지하고 저장소 이전, 알림 재시도, 워치 이미지 복구를 보완했습니다. 현재 진행 상황과 남은 검증은 [출시 검증 기록](docs/RELEASE_VALIDATION.md)에 기록합니다.

출시 안정화 코드는 PR #3까지 `main`에 병합했습니다(앱 코드 기준 `8ea2a10`). 테스트 115개·초기 SwiftData 스키마 이전·iPhone/Watch/위젯 Release 빌드는 [병합 후 CI](https://github.com/eric91405/piyak-bank-ios/actions/runs/35569409466)에서 통과했습니다. iPhone 시뮬레이터 주요 흐름은 확인했지만 전체 출시 검증 완료 상태는 아닙니다. 다음 작업은 [남은 검증 체크리스트](docs/RELEASE_VALIDATION.md#제출-전-남은-검증)의 iPad 다중 창·접근성·최소 OS 실행과 실기기 시험입니다.

**2026-09-26 배포 상태 갱신:** Apple Developer Program 개인 등록과 개발자 팀 `G2D6ZG4SX3`을 확인했습니다. `de91f5d`의 1.0 (2)를 배포 서명하여 App Store Connect 앱 `6816129028`에 업로드했습니다. 내부 그룹 `내부 출시 검증`은 계정 소유자 1명만 포함하며 자동 배포는 껐습니다. 최초 unsigned Archive의 내보내기에서 App Group 서명 권한 누락을 발견해 원본 entitlement를 보존한 Archive 사본에서 다시 배포 서명했습니다. `scripts/verify_distribution_ipa.py`로 실제 IPA의 세 타깃 서명·프로파일·App Group을 확인하며, 누락 IPA 차단과 수정 IPA 통과를 검증했습니다. 사용자의 TestFlight 정상 동작 보고를 받았으며, 기존 데이터 업데이트 보존·세부 호환성 검증은 남아 있으며 심사 제출은 위 최신 상태를 따릅니다. Apple 처리 상태는 [검증 기록](docs/RELEASE_VALIDATION.md)을 따릅니다.

GitHub Pages의 현재 소스는 `main`의 `/docs`입니다. 2026-09-21 홈·iOS 정책·Android 정책·지원 페이지 모두 로그인 없이 HTTP 200 응답과 실제 내용을 확인했습니다. [게시 절차](docs/PUBLISHING.md)를 따릅니다. 네이티브 Xcode 테스트 타깃 추가는 개발 편의 개선이며 App Store 제출 필수 조건은 아닙니다. 기존 Swift Package 테스트와 CI를 유지합니다. 아래 기능 추가 목록은 별도 로드맵이며 이번 안정화 범위에 포함되지 않습니다.

## Android · Wear OS 병행 개발 (2026-09-25)

사용자 요청으로 `android/`에 휴대폰·태블릿·홈 화면 위젯과 **Wear OS 동반 앱**을 구현했습니다. AI·광고·인앱 결제·앱 계정은 없으며 iOS와 Android 사이의 기록 동기화는 범위에 없습니다. [PR #4](https://github.com/eric91405/piyak-bank-ios/pull/4)의 구현 이후 [PR #5](https://github.com/eric91405/piyak-bank-ios/pull/5)에서 최소 OS와 출시 예외 검증을 보완했습니다.

**Android 자동 검사 134개(JVM 83 + API 36 휴대폰 46 + API 30 Wear 5)가 통과**했습니다. 최소 API 26 원격 실행도 45개 통과했습니다. 코드 `8fe25b7`의 [Android CI](https://github.com/eric91405/piyak-bank-ios/actions/runs/36113766276)와 [iOS CI](https://github.com/eric91405/piyak-bank-ios/actions/runs/36113766453)가 성공했습니다. Swift 115개는 별도입니다.

- API 26 계산 크래시, 회전 중 CSV, 알림 채널·예약 예외, 큰 글꼴/창 변경 대화상자, 실제 TalkBack의 방 설명 누락, 오래된 Wear 종료 대상, 3D 곡선 이음새를 수정했습니다.
- 81종·방 9조합·의상 9조합 production GLES와 컨텍스트 복구를 확인하고 iOS/Android/Watch 생성 리소스를 갱신했습니다. 모든 조합·물리 GPU 검증은 아닙니다.
- 최종 R8·Lint·16 KB 정렬, API 26 CSV·채널 조작, API 36 권한 거부/재허용·TalkBack·최대 글꼴/표시 크기·실제 분할 화면을 확인했습니다. QA 업데이트·재시작·재부팅 후 101원·6P를 보존했습니다.
- **스위치 접근은 환경 차단**입니다. 에뮬레이터 가상 키가 스위치로 등록되지 않아 실제 조작은 통과 처리하지 않았습니다. 물리 보조 입력에서 확인해야 합니다.
- 실제 물리 휴대폰–Wear 연결·GPU·알림·위젯·장시간 전력·태블릿·최종 배포 설치는 남아 있습니다. 기존 개인 Google Play 계정은 있으나 Console 조건·업로드 키·Play App Signing·테스트 트랙은 미확인입니다.

정확한 실행 환경·결과는 [검증 기록](android/docs/VALIDATION.md), 남은 시나리오는 [UI 계획](android/docs/UI_TEST_PLAN.md)과 [Play 체크리스트](android/docs/PLAY_STORE.md)를 따릅니다. 테스트 개수만으로 모든 화면·기기·배포 검증이 끝났다고 표현하지 마세요. QA 후 에뮬레이터를 종료하고, 로컬 빌드와 에뮬레이터를 겹치지 않습니다. `piyakbank-fixes.patch`는 사용자 파일이므로 변경·스테이징·삭제하지 않습니다.

### 구조와 실행

- `android/core/`: 순수 Kotlin 도메인·금액·보상·기록·시계 명령 정책.
- `android/app/`: Compose 휴대폰·태블릿 화면, SQLite, OpenGL 장면, 알림·위젯·시계 통신.
- `android/wear/`: 연결된 Wear OS 앱. `app`의 장면과 에셋을 공유합니다.
- `android/scripts/`: iOS SceneKit 원본 기하를 Android 메시로 내보내고 검사합니다.

`android/`에서 실행:

```sh
nice -n 15 ./gradlew --no-daemon --max-workers=1 :core:test :app:testDebugUnitTest :wear:testDebugUnitTest
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:assembleDebug :wear:assembleDebug
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:connectedDebugAndroidTest
```

마지막 명령은 합성 데이터용 QA 기기가 필요합니다. AGP 8.13.1·Kotlin 2.2.20·Gradle 8.14·JDK 17 이상, compileSdk 36을 사용합니다. 휴대폰 minSdk 26/targetSdk 36, Wear OS minSdk 30/targetSdk 35입니다. 두 앱의 applicationId는 `com.minseo.piyakbank`이며 동일 서명을 사용해야 통신합니다. versionCode는 휴대폰 1, Wear OS 1000001부터 분리했습니다.

Compose·설정 경쟁·CSV·알림 예외 시험은 `-PpiyakUiTest=true`로 선택한 `com.minseo.piyakbank.uitest` 전용 설치본에서 실행합니다. 같은 속성으로 `:app:assembleUiTest :app:assembleUiTestAndroidTest`를 먼저 빌드한 뒤 QA 기기를 켜고 `:app:connectedUiTestAndroidTest`를 실행합니다. CSV 제공자는 `src/uiTest`에만 있으며 일반 Debug·Release에 넣지 않습니다. 신규 API 26 CI도 빌드 후 에뮬레이터를 켜고 원시 instrumentation 결과를 별도로 검증합니다. 일반 Debug의 skip을 통과로 세거나 실제 사용자 저장소를 fixture로 초기화하지 않습니다.

MacBook Air M4 16GB의 발열 관리 요청을 유지합니다. Gradle worker 1개·병렬 끄기·JVM 최대 2GB를 지키고 빌드와 에뮬레이터를 순차 실행합니다. 사용하지 않는 시뮬레이터·에뮬레이터는 종료합니다. Release 서명에는 소유자가 관리하는 `PIYAK_KEYSTORE`, `PIYAK_STORE_PASSWORD`, `PIYAK_KEY_ALIAS`, `PIYAK_KEY_PASSWORD`가 필요하며 키를 저장소에 넣지 않습니다.

### 개인정보와 공개 문서

Wear OS 동기화는 Google Play services Data Layer를 사용해 연결된 기기 사이에 근무 상태·오늘 수익·잔액·장착 정보를 전달합니다. Google 클라우드의 종단 간 암호화 중계 가능성을 Android 앱 내 안내에 명시했습니다. 개발자 서버가 없거나 `INTERNET` 권한이 없다는 이유로 모든 데이터가 기기 밖으로 나가지 않는다고 설명하지 마세요.

Android 공개 정책 `/privacy-android/`의 Pages 게시와 HTTP 200 응답을 확인했습니다. 제출 때도 앱 링크와 최종 정책 내용이 일치하는지 다시 확인합니다. 기존 iOS 공개 정책·지원 문서를 Android에 무조건 적용하지 않고, 위젯 주기·시계 연결·권한·구버전 포인트 이전 설명을 플랫폼별로 구분해야 합니다.

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
