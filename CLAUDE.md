# CLAUDE.md

삐약뱅크(PiyakBank) — 근무 시간을 기록하고 병아리의 방을 꾸미는 iOS · watchOS 및 Android · Wear OS 앱. 같은 저장소에 Xcode 프로젝트와 `android/` Gradle 프로젝트가 있으며 무료 출시 준비 중이다. 광고·앱 계정·인앱결제·AI 대화 기능은 없다.

## 빌드와 검증

다음은 저장소 루트에서 실행하는 iOS 검증이다.

```sh
swift test --jobs 1                       # 계산·저장 회귀 테스트 (SPM 타깃 PiyakCore)
python3 scripts/check_release_assets.py   # 에셋·개인정보 매니페스트 검사
xcodebuild -project PiyakBank.xcodeproj -scheme PiyakBank \
  -configuration Release -jobs 1 -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/PiyakBank CODE_SIGNING_ALLOWED=NO build
```

발열을 줄이려면 `nice -n 15`와 `--jobs 1`을 쓰고, 빌드 중에는 시뮬레이터를 종료한다.

Android는 `android/`를 Android Studio로 열고 JDK 17 이상·SDK 36을 사용한다. **아래는 `android/` 폴더에서 실행한다.**

```sh
nice -n 15 ./gradlew --no-daemon --max-workers=1 :core:test :app:testDebugUnitTest :wear:testDebugUnitTest
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:assembleDebug :wear:assembleDebug
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:connectedDebugAndroidTest
```

기기 테스트는 합성 데이터용 QA 기기에만 실행한다. Gradle은 worker 1·병렬 끄기·JVM 최대 2GB로 제한했다. MacBook Air M4 16GB에서 빌드와 에뮬레이터를 겹치지 말고, 사용하지 않는 에뮬레이터를 종료한다. Debug·JVM·기기 테스트·Release·실기기·스토어 설치 결과를 서로 대체하지 말 것. Android 설정·배포 서명·체크리스트는 [android/README.md](android/README.md)와 [PLAY_STORE.md](android/docs/PLAY_STORE.md)에 있다.

Compose·설정 경쟁·CSV·알림 예외 테스트는 별도 `.uitest` 패키지로 격리한다. `-PpiyakUiTest=true`로 `:app:assembleUiTest :app:assembleUiTestAndroidTest`를 먼저 빌드하고, 같은 속성으로 QA 기기에서 `:app:connectedUiTestAndroidTest`를 실행한다. 실제 ContentResolver 시험용 제공자는 `src/uiTest`에만 넣고 일반 Debug·Release에 노출하지 않는다. 실제 앱 데이터로 fixture를 만들거나 초기화하지 말 것. 일반 Debug에서 건너뛴 UI 테스트를 통과로 세지 않는다. 정확한 개수·커밋·환경·결과는 [Android 검증 기록](android/docs/VALIDATION.md)을 갱신하며, 테스트 추가만으로 통과 개수를 늘리지 않는다.

2026-09-25 [PR #5](https://github.com/eric91405/piyak-bank-ios/pull/5)의 Android 자동 검사 **134개(JVM 83 + 휴대폰 API 36 46 + Wear API 30 5)**와 Swift 115개가 통과했다. 최소 API 26 원격 실행은 ATF를 제외한 45개 통과다. 81종·방 9조합·의상 9조합 GLES, 최종 R8·Lint·정렬, TalkBack 주요 조작·최대 글꼴/표시 크기·실제 OS 분할 화면·알림 거부/재허용·CSV 수동 QA를 확인했다. 스위치 접근은 가상 키가 등록되지 않아 환경 차단으로 남긴다. [검증 기록](android/docs/VALIDATION.md)의 증거·제약을 따른다. 개인 Google Play 계정 보유는 확인됐으나 Console 조건·소유자 서명·Play 설치·물리 휴대폰–시계 연결 등은 미완료다. Android 결과를 iOS 또는 실기기 완료 상태로 대체하지 않는다.

모델(`PiyakScene.swift`)을 수정하면 iOS 미리보기 이미지를 반드시 재생성해야 한다. 생성기와 원본의 SHA-256 지문을 CI가 대조하므로 그러지 않으면 검사에 실패한다.

```sh
xcrun swiftc PiyakBank/Views/PiyakScene.swift scripts/GenerateAssets.swift -o /tmp/piyak-assets
/tmp/piyak-assets "$PWD"
```

Android 장면은 같은 iOS 원본에서 내보낸 메시를 사용한다. 원본 장면·행동을 바꾸면 [Android 장면 변환 절차](android/scripts/SCENE.md)에 따라 내보내기와 에셋 검사를 수행한다. 두 렌더러의 픽셀이 같다고 보장하지 않으며 CPU 에셋 검사가 실제 GPU 검증을 대신하지 않는다.

## 구조

iOS 타깃 3개(앱 / `PiyakWatch Watch App` / `PiyakWidgetExtension`)가 `PiyakBank/Shared/`를 공유한다. **Xcode 파일 시스템 동기화 그룹**을 쓰므로 폴더에 `.swift`를 넣으면 자동으로 타깃에 포함된다. `project.pbxproj`를 손으로 편집하지 말 것. 워치·위젯에만 넣을 파일은 pbxproj의 `membershipExceptions`에 추가해야 한다. Android는 `core`·`app`·`wear` Gradle 모듈로 나뉘며 Kotlin 코드와 저장소를 iOS와 공유하지 않는다.

```
PiyakBank/App/       진입점, 서비스 와이어링, 라우팅
PiyakBank/Shared/    EarningsCalculator, RewardPolicy, Economy(원장), AppConfig, DesignTokens
PiyakBank/Services/  SessionController, WorkSession, WatchSync, NotificationScheduler
PiyakBank/Views/     Home, PiyakScene(SceneKit), Decorate, History, Settings
Tests/PiyakCoreTests/  Swift Testing. Views/SceneKit은 커버 안 됨
scripts/             에셋 생성, 장면·행동 검증, 릴리스 리소스 검사
android/core/        Android 의존성이 없는 Kotlin 도메인·정책·회귀 테스트
android/app/         Compose UI, SQLite, 알림·위젯·Wear 통신, OpenGL 장면
android/wear/        연결된 Wear OS 앱, app의 scene·assets를 공유
android/scripts/     SceneKit 원본 메시 변환과 리소스 검사
android/docs/        Android UI 테스트 계획·Play 출시 체크리스트
```

## 깨뜨리면 안 되는 규칙

- **시급과 포인트는 완전히 분리된다.** 수익은 `EarningsCalculator`, 포인트는 `RewardPolicy`. 시급이 포인트에 영향을 주면 안 된다.
- **금액 계산은 밀리초 × 시급의 분자를 유지하다 마지막에 한 번만 나눈다.** 시급을 먼저 3600으로 나누면 반복 소수 오차가 난다. 날짜별 배분에도 누적 잔여값을 넘겨 총액이 보존되어야 한다.
- **포인트 하루 한도(4,800P)의 날짜 기준은 KST 고정**(iOS `RewardPolicy.calendar`, Android `RewardPolicy.zone`). 수익과 달력은 기기 현지 시간대(iOS `Calendar.current`, Android `ZoneId.systemDefault()`)다. 둘을 섞지 말 것.
- **잔액은 단일 필드가 아니라 원장의 합**이다. iOS는 `PointTransaction`의 `legacy` 종류를 현재 잔액에서 제외한다. Android는 `PointEntry` 원장과 별도 불변 보상 영수증을 사용한다. iOS의 구버전 잔액 이전 정책을 새 Android 저장소에 적용하지 말 것.
- **저장이 성공해야 상태가 바뀐다.** iOS 근무 종료와 적립은 `economy.transaction(restoring:)` 한 단위이고 실패 시 SwiftData 모델 값까지 복원한다(`autosaveEnabled = false`). Android는 `BankDatabase`의 SQLite 트랜잭션·expected revision 검사 뒤에만 새 상태를 게시한다. 읽기 실패 시 원본을 초기 상태로 덮어쓰지 않는다.
- **보상 시간은 monotonic clock과 부팅 식별자로 방어한다.** 기기 시각을 앞당겨도 보상이 늘면 안 되고, 수동 기록 추가·수정·삭제로 포인트가 생기거나 사라지면 안 된다.
- **워치 명령은 ID·대상 세션·생성 시각을 검사**하고, 연결된 휴대폰(iPhone 또는 Android)의 저장 확인 응답을 받아야 워치 상태를 바꾼다. 오프라인 명령을 예약하지 않는다.
- **Android 휴대폰 조작도 표시했던 근무 상태를 확인한다.** 확인창을 열어 둔 사이 시계나 다른 창에서 근무가 바뀌면 이전 시작·휴식·재개·종료 조작을 새 근무에 적용하지 않는다.
- **Android 설정은 변경한 필드만 저장한다.** 이전 화면의 `UserSettings` 전체 사본으로 다른 창의 최신 값을 덮어쓰지 않는다. 진행 중 시급 변경의 제한은 UI뿐 아니라 저장 직전의 최신 상태에서도 검사한다.
- **안내 배너가 근무 버튼을 덮으면 안 된다.** Android 홈의 실제 조작 영역 높이로 Snackbar 위치를 조절한다. 고정 여백으로 되돌리거나 테스트에서 배너가 사라질 때까지 기다려 실제 터치 오류를 가리지 말 것. 큰 글꼴·회전에서도 확인한다.
- **Android 최소 버전의 런타임 API를 실제로 검증한다.** 순수 JVM 코어도 Android API 26에서 실행되므로 최신 JDK 메서드의 존재를 가정하지 않는다. `BigInteger.longValueExact()` 대신 범위를 검사하는 호환 변환을 유지하고, 최소 API instrumentation 결과를 확인한다.
- **CSV 저장 중 회전으로 작업을 취소하지 않는다.** application 참조만 가진 ViewModel이 진행 작업과 완료 결과를 유지한다. Activity를 캡처하지 않으며 coroutine 취소를 일반 실패로 삼키지 않는다. 제공자 오류가 원본 저장소를 바꾸면 안 된다.

## 관례

- UI 문자열은 한국어. 현재 `ko` 단일 로컬라이즈이며 문자열이 뷰 안에 직접 박혀 있다.
- iOS는 서드파티 의존성이 없고 Android는 Jetpack·Google Play services 등을 사용한다. 개발자 서버·분석·광고 전송·API 키는 없다. Wear Data Layer는 기기 간 정보를 Google 클라우드의 종단 간 암호화 중계로 전달할 수 있으므로 “모든 데이터가 기기 안에만 있음”을 주장하지 않는다.
- iOS 색상은 `PB.C` 토큰과 `adaptive()`를 사용한다. Android는 `PiyakTheme`·Material 3 토큰과 명시적인 방 배경 색상을 사용한다. 양쪽의 다크 모드 대비를 확인한다.
- 3D의 원본은 코드로 만든 SceneKit 기하 모델이다. Android는 내보낸 메시를 OpenGL ES로 렌더링한다. 다운로드 자산이나 외부 3D 모델을 추가하지 않는다.
- 최소 지원: iOS 17.0 / watchOS 10.0, Android 휴대폰 API 26 / Wear OS API 30. Android targetSdk는 휴대폰 36 / Wear OS 35다.
- Android 두 앱의 applicationId는 `com.minseo.piyakbank`로 같고 최종 설치 서명도 일치해야 한다. Wear OS 앱은 연결된 Android 휴대폰이 필요하다. 비밀 키를 커밋하지 말 것.

## 주의

아래 SwiftData·App Group·WatchPortrait 관련 항목은 iOS 구현에 관한 것이다. Android 저장소는 별도 SQLite 파일이며 SwiftData 마이그레이션과 혼동하지 않는다.

- 포인트는 가상이며 환금·송금·인출 기능이 없다. 앱은 은행이나 급여 지급 서비스가 아니다. 이 선을 넘는 문구나 기능을 추가하면 심사 리스크가 생긴다.
- 예상 수익은 세전 단순 추정치다. 세금·수당을 반영한다고 표시하지 않는다.
- SwiftData 스토어는 App Group(`group.com.minseo.piyakbank`)에 있다. 위치를 다시 옮기면 마이그레이션이 필요하다.
- 기존 저장소는 `StoreMigration`의 SQLite backup API로 WAL까지 일관되게 백업한 뒤 최종 파일 이름으로 게시한다. 개별 store/WAL 파일 복사나 실패 후 이전 저장소 재사용은 데이터 유실·분기 위험이 있어 금지한다. 기존 자동 설정이 App Group 안의 `default.store`를 선택했을 수 있으므로 이전 후보 위치를 모두 확인한다.
- 이전 사본은 보존하되 사용자 요청의 전체 초기화에서는 `beforeReset`이 이전 사본과 중단된 staging을 정리한다. 정리 실패 시 활성 저장소를 초기화하지 않는다.
- 알림은 실제 pending 요청을 기준으로 보충한다. 권한 확인·저장 성공 전에 계획을 완료로 캐시하면 재허용/실패 복구가 막힌다.
- 워치 상태와 초상화는 분리 전송하며 `WatchStateCache`가 현재 장착 정보에 맞는 이미지만 표시한다. 렌더링이 바뀌면 `WatchPortrait.rendererVersion`을 올린다.
