# 삐약뱅크 · PiyakBank

**일하는 나에게, 작은 친구 하나.**

시급과 근무 시간으로 예상 수익을 기록하고, 타이머로 쌓은 시간 보상으로 병아리의 방을 꾸미는 앱입니다. iOS · Apple Watch 버전과 Android 휴대폰·태블릿 · Wear OS 버전을 같은 저장소에서 개발합니다. 시급과 꾸미기 포인트를 분리해 시간 기록에 작은 성장과 수집의 재미를 더했습니다.

<img src="PiyakBank/Assets.xcassets/AppMascot.imageset/image.png" width="180" alt="입체 병아리 삐약이">

첫 출시 방향은 **무료·광고 없음·회원가입 없음**입니다. 포인트는 앱 꾸미기 전용이며 현금 가치나 송금·인출 기능은 없습니다. 표시 수익은 세금과 수당을 제외한 단순 추정치입니다.

## 현재 진행 상황 · 2026-09-21

### iOS · Apple Watch

iOS 출시 안정화 수정은 [PR #3](https://github.com/eric91405/piyak-bank-ios/pull/3)까지 `main`에 반영했습니다. **핵심 로직과 주요 iPhone 사용 흐름은 검증했으며, 전체 출시 검증과 TestFlight 배포는 아직 완료하지 않았습니다.**

| 범위 | 상태 |
|---|---|
| 자동 검증 | 테스트 115개, 초기 SwiftData 스키마 이전, 리소스·개인정보 매니페스트 검사 통과 |
| 통합 빌드 | iPhone·Watch·위젯 Release 빌드 통과 — [병합 후 CI](https://github.com/eric91405/piyak-bank-ios/actions/runs/35569409466) |
| iPhone 시뮬레이터 | 온보딩, 근무·휴식·정산, 기록 수정, 포인트 분리, 설정·재실행 보존 확인 |
| 남은 화면·호환성 검증 | iPad 다중 창 실제 조작, VoiceOver·최대 글씨·가로 화면 전체 흐름, 최소 지원 OS 실행 |
| 남은 실기기 검증 | Watch 통신, 알림·위젯 갱신, 배터리·발열, 배포 빌드의 데이터 업그레이드 |
| 배포 | Apple Developer Program 미가입으로 배포 서명 Archive·TestFlight 업로드·심사 제출 미진행 |

재현 방법과 후속 체크리스트는 [출시 검증 기록](docs/RELEASE_VALIDATION.md)에 정리했습니다.

### Android · Wear OS

`android/`에 별도 Gradle 프로젝트를 추가해 네이티브 Compose 화면, 81종 아이템의 OpenGL 3D 방, SQLite 저장, 알림·위젯과 Wear OS 앱을 구현하고 있습니다. **개발 빌드와 일부 자동 테스트를 통과한 상태이며 Play 출시 준비 완료 상태는 아닙니다.**

| 범위 | 확인된 상태 |
|---|---|
| JVM 테스트 | 코어 45개 + 앱 15개 통과 |
| Android 기기 저장소 테스트 | API 35에서 SQLite instrumentation 8개 통과 |
| 개발 빌드 | 휴대폰·Wear OS Debug APK 및 휴대폰 테스트 APK 빌드 성공 |
| 남은 검증 | Release·Lint 최종 결과, 3D GPU 화면, 전체 UI·접근성, 최소 OS, 실제 시계 연결·알림·위젯·발열 |
| 배포 | Play 업로드·실제 배포 설치·심사 미진행, 개발자 계정 상태 미확인 |

설정과 모듈 구조는 [Android README](android/README.md), 시나리오는 [Android UI 테스트 계획](android/docs/UI_TEST_PLAN.md), 외부 배포 절차는 [Play Store 체크리스트](android/docs/PLAY_STORE.md)를 참고하세요. Android의 결과는 iOS 테스트 115개와 별개입니다.

## 실제 iOS 앱 화면

<img src="docs/screenshots/iphone-home.jpg" width="240" alt="방 안에서 생활하는 입체 병아리와 예상 수익"> <img src="docs/screenshots/iphone-decorate.jpg" width="240" alt="옷과 가구를 미리 보는 꾸미기 상점"> <img src="docs/screenshots/iphone-item-preview.jpg" width="240" alt="회전과 확대 버튼으로 살펴보는 입체 의상">

iPhone 17 Pro Max 시뮬레이터에서 직접 캡처했습니다. 홈의 시간 보상 안내와 새 상점·미리보기 가격을 반영한 최신 화면입니다. 이전 출시 후보의 레이아웃 검증 자료: [iPad 화면](docs/screenshots/ipad-home.jpg) · [다크 모드와 큰 글씨](docs/screenshots/iphone-accessibility-dark.jpg). 두 참고 화면은 모델 개선 이전 모습입니다.

## 주요 기능

| 기능 | 구현 |
|---|---|
| 근무 기록 | 시작·휴식·재개·종료, 마지막 저장 상태 복구 |
| 수익 계산 | 유급 시간만 계산, 자정 분할, 날짜별 합계와 전체 금액 일치 |
| 시간 보상 | 시급과 무관하게 타이머 근무 10분당 100P, 한국 시간 하루 최대 4,800P |
| 작은 방 꾸미기 | 곡면 의상·안경·가구 등 81개 입체 아이템, 회전·확대 착용 미리보기 |
| 삐약이와 놀기 | 삐약이를 누르거나 ‘놀아주기’ 버튼으로 인사하고 장착한 가구와 상호작용 |
| 삐약이의 하루 | 바닥을 걷고, 장착한 화분·책·피아노·소파·강아지와 상호작용 |
| 성장 | 새 정책으로 적립한 근무 보상 4,800P마다 레벨 상승, 아이템 구매로 레벨 감소 없음 |
| 기록 관리 | 달력, 완료 기록 수정·삭제, 누락 근무 추가, CSV 내보내기 |
| Apple Watch | iPhone 시급 동기화, 연결 상태 표시, 확인 응답을 받는 근무 제어 |
| iPhone/iPad 위젯 | 5분 단위 예상 수익, 상태 변경 시 갱신 요청 |
| 접근성과 개인정보 | Dynamic Type, VoiceOver 레이블, Reduce Motion, 다크 모드, 선택 알림 |
| Android 휴대폰·태블릿 | 네이티브 Compose 4개 탭·넓은 화면 탐색 레일, 근무·꾸미기·달력·설정, 로컬 저장 |
| Android 위젯·Wear OS | 시스템 주기의 위젯 갱신, 연결된 Android 휴대폰의 저장 확인을 받는 시계 근무 제어 |

## 설계에서 집중한 점

아래 상세 설명의 SwiftData·SceneKit·WatchConnectivity는 iOS 구현입니다. Android는 같은 제품 규칙을 순수 Kotlin 코어, SQLite 트랜잭션, OpenGL, Wear Data Layer로 구현합니다. 두 플랫폼의 저장소나 런타임 코드가 자동으로 공유·동기화되는 구조는 아닙니다.

### 한 가지 계산 규칙

iPhone, Watch, 위젯이 `EarningsCalculator`를 공유합니다. 시급을 먼저 3,600으로 나누면 반복 소수 오차가 발생하므로, **밀리초 × 시급**의 분자를 유지한 뒤 마지막에 정수 원 단위로 절삭합니다. 날짜별 배분에도 누적 잔여값을 넘겨 전체 금액이 보존됩니다.

휴식은 시급 0원 구간으로 표현합니다. 오늘 수익은 완료 기록과 진행 중인 근무의 **오늘 구간만** 합산합니다. 꾸미기 포인트는 수익 계산과 별도의 `RewardPolicy`로 계산합니다.

### 시급과 분리한 시간 보상

휴식을 제외한 타이머 근무는 **6초당 1P, 10분당 100P**입니다. 같은 날의 짧은 근무도 합산하며 하루 최대 4,800P를 적립합니다. 날짜는 기기의 시간대 변경에 영향받지 않도록 한국 시간(KST) 자정을 기준으로 나눕니다. 한 근무에서 보상에 반영할 수 있는 측정 시간은 최대 24시간이며, 한도를 넘겨도 근무 기록과 예상 수익 계산은 계속됩니다.

측정 구간을 별도 보상 내역으로 보관하고 겹치는 시간은 한 번만 계산합니다. 시계 시간과 연속 경과 시간을 함께 확인해 기기 시각을 앞당긴 만큼 보상이 늘어나지 않도록 제한합니다. 수동으로 추가한 기록은 포인트를 만들지 않으며, 완료 기록의 시급·시간 수정이나 삭제도 이미 확정된 보상을 바꾸지 않습니다. 레벨은 새 정책에서 얻은 근무 보상 4,800P, 즉 보상 대상 시간 8시간마다 오릅니다. 구매·이전 정책 잔액 전환은 성장에 영향을 주지 않습니다.

기존 아이템 가격은 1/20로 조정해 기본 제공 외 아이템을 450~4,000P로 구성합니다. 업데이트 시 기존 잔액도 1/20로 내림 환산하되 0~4,800P 범위에서 한 번만 전환합니다. 근무 기록과 보유 아이템을 유지하며, 이전 정책 거래는 포인트 원장 CSV 안에 `legacy`로 구분해 보관하며 현재 잔액에 합산하지 않습니다. 업데이트 당시 진행 중이던 근무는 업데이트 이후 측정한 시간부터 새 보상을 받습니다.

이 규칙은 시급 부풀리기와 기록 편집에 따른 추가 적립을 막기 위한 장치입니다. 계정과 서버가 없는 오프라인 앱이므로 실제 근무 여부를 증명하거나 기기 저장소 변조까지 차단하지는 않습니다.

### 저장이 성공해야 상태가 바뀜

근무 종료와 포인트 적립을 하나의 저장 단위로 처리합니다. 실패 시 새 원장 항목을 취소하고 화면에 연결된 SwiftData 모델 값도 복원합니다. 강제 종료 복구는 UserDefaults의 보조 키가 아닌 SwiftData의 활성 근무를 기준으로 합니다.

### 늦게 도착한 워치 명령 방지

명령에는 ID, 대상 근무 ID, 생성 시각을 넣습니다. 중복·만료·다른 근무에 대한 명령을 거부하며, 오프라인 명령을 예약하지 않습니다. iPhone의 저장 확인 응답을 받아야 워치 상태를 바꿉니다.

### 같은 모델로 만드는 디자인

캐릭터, 옷, 방과 가구를 코드로 구성한 SceneKit 기하 모델로 렌더링합니다. 앱 아이콘과 상점의 81개 미리보기도 같은 모델에서 생성하므로 미리보기와 실제 착용이 일치합니다. 제3자 3D 모델이나 다운로드 자산은 없습니다.

의상과 봉제선은 몸 곡면을 따라 구성하고, 얇은 물체의 모서리 반경을 두께에 맞춰 제한합니다. 미리보기는 실제 모델 범위에 맞춰 카메라를 조정하며 생성 원본의 지문을 검사해 오래된 이미지가 남지 않게 합니다.

방 안 행동은 가구 앞쪽 통로를 따라 이동하도록 설계했고 캐릭터 관절을 사용합니다. 삐약이를 누르거나 ‘놀아주기’ 버튼을 누르면 인사하거나 장착한 가구와 상호작용합니다. 홈이 화면에 보일 때만 최대 24fps로 움직이며, 다른 탭·백그라운드·저전력·발열 경고·Reduce Motion에서는 멈춥니다. 홈에서 직접 움직임을 멈출 수도 있습니다.

[행동 프레임](docs/quality/room-activities.jpg)과 [착용 조합](docs/quality/room-combinations.jpg)에서 실제 엔진의 렌더링 결과를 확인할 수 있습니다. 오늘 예상 수익과 보유 포인트는 홈에서, 날짜별 근무 기록은 기록 탭에서 확인합니다.

## 기술 구성

- iOS: SwiftUI · SwiftData · SceneKit · WatchConnectivity · WidgetKit · UserNotifications
- Android: Kotlin · Jetpack Compose · SQLite · OpenGL ES 2.0 · AppWidget · Google Play services Wear Data Layer

```text
PiyakBank/
  App/         앱 시작, 서비스 연결
  Shared/      공통 계산, 스냅샷, 포인트 원장, 디자인 토큰
  Services/    근무 수명주기, 저장, 알림, 워치 통신
  Views/       홈, 입체 방, 꾸미기, 기록, 설정, 개인정보
  Watch/       Watch 동반 앱
  Widget/      iPhone/iPad 위젯
Tests/         계산 및 실제 SwiftData 회귀 테스트
scripts/       원본 모델에서 이미지 생성, 배포 리소스 검사
docs/          지원·개인정보·심사 자료·검증 기록
android/
  core/        순수 Kotlin 계산·보상·기록·아이템·시계 명령 규칙
  app/         휴대폰·태블릿 UI, 저장소, 3D 방, 알림, 위젯, 시계 통신
  wear/        연결된 Wear OS 앱, Android 공용 장면·에셋 사용
  scripts/     iOS 원본 기하를 Android 모델로 변환·검사
  docs/        Android UI 검증 계획과 Play 출시 체크리스트
```

## iOS 실행과 검증

- **빌드:** Xcode 26 이상, iOS/watchOS SDK 26 이상
- **실행:** iOS 17.0 이상, watchOS 10.0 이상
- **실기기 서명:** 본인의 Team 및 `group.com.minseo.piyakbank` App Group 설정 필요

`PiyakBank.xcodeproj`를 열고 `PiyakBank` scheme을 실행합니다. 의존 패키지, API 키, 서버 설정은 없습니다.

```sh
swift test --jobs 1
python3 scripts/check_release_assets.py
python3 scripts/verify_legacy_schema_migration.py
xcodebuild -project PiyakBank.xcodeproj -scheme PiyakBank \
  -configuration Release -jobs 1 -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/PiyakBank CODE_SIGNING_ALLOWED=NO build
```

이미지 재생성:

```sh
xcrun swiftc PiyakBank/Views/PiyakScene.swift scripts/GenerateAssets.swift -o /tmp/piyak-assets
/tmp/piyak-assets "$PWD"
```

GitHub Actions에서 계산·저장 회귀 테스트, 초기 SwiftData 스키마의 업그레이드·재실행 검증, iOS/Watch/위젯 Release 빌드를 수행합니다. 상세 결과와 남은 화면·호환성·실기기 검증은 [검증 기록](docs/RELEASE_VALIDATION.md)을 참고하세요.

## Android 실행과 검증

Android Studio에서 `android/` 폴더를 엽니다. JDK 17 이상과 Android SDK 36을 사용하며, 휴대폰은 Android 8.0(API 26) 이상, Wear OS 앱은 API 30 이상을 대상으로 합니다. 기기 간 시계 통신에는 같은 패키지 이름·서명과 연결된 Android 휴대폰이 필요합니다.

다음 명령은 **`android/` 폴더 안에서** 실행합니다. Gradle은 worker 1개·병렬 빌드 끄기·JVM 최대 2GB를 기본으로 사용합니다.

```sh
nice -n 15 ./gradlew --no-daemon --max-workers=1 :core:test :app:testDebugUnitTest
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:assembleDebug :wear:assembleDebug
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:connectedDebugAndroidTest
```

마지막 명령은 합성 데이터용 QA 기기 또는 에뮬레이터를 연결한 뒤 실행합니다. 빌드와 에뮬레이터 부하를 겹치지 않고 사용하지 않는 기기를 종료합니다. Release 검증과 서명 환경 변수는 [Android 개발 문서](android/README.md)에 정리했으며, unsigned 산출물을 스토어 업로드 준비 완료로 취급하지 않습니다.

## 데이터와 배포

기록은 기기에 저장하며 개발자 서버로 전송하지 않습니다. CSV는 열람·보관용이고 가져오기 및 계정 기반 클라우드 동기화는 지원하지 않습니다. 위젯은 각 OS의 갱신 정책을 따르는 예상치이며 watchOS 컴플리케이션은 포함하지 않습니다.

Android의 연결된 Wear OS에는 근무 상태·오늘 예상 수익·잔액·장착 정보를 전달합니다. Google Play services의 Data Layer는 Google 클라우드를 통한 종단 간 암호화 중계를 사용할 수 있으므로 모든 정보가 기기 밖으로 나가지 않는다고 설명하지 않습니다. [공식 Data Layer 안내](https://developer.android.com/training/wearables/data/overview)

공개 페이지: [개인정보 처리방침](https://eric91405.github.io/piyak-bank-ios/privacy/) · [지원 안내](https://eric91405.github.io/piyak-bank-ios/support/)

저장소 문서: [개인정보 처리방침](docs/PRIVACY.md) · [지원 안내](docs/SUPPORT.md) · [App Store 제출 자료](docs/APP_STORE.md)

Android 전용: [개발·검증 안내](android/README.md) · [Play Store 체크리스트](android/docs/PLAY_STORE.md) · [공개 개인정보처리방침 예정 주소](https://eric91405.github.io/piyak-bank-ios/privacy-android/) — 제출 전에 실제 게시 상태를 확인합니다.

개발: **김민서** · [eric91405@gmail.com](mailto:eric91405@gmail.com)
