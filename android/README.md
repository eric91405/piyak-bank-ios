# 삐약뱅크 Android

근무 시간을 기록하고, 모은 포인트로 삐약이의 3D 방을 꾸미는 네이티브 Android 앱입니다. 휴대폰·태블릿, 홈 화면 위젯, 연결된 Wear OS 시계 앱을 함께 제공합니다. iOS 프로젝트와 같은 저장소 안에 있지만 Android 빌드는 이 폴더에서 독립적으로 실행합니다.

첫 버전은 무료이며 앱 계정, 광고, 인앱 결제, AI 대화 기능이 없습니다. 시급으로 계산한 금액은 **세전 예상 수익**이며, 실제 급여 지급이나 금융 계좌를 제공하지 않습니다.

## 기능

- **근무:** 시작·휴식·재개·종료, 프로세스 재시작 후 복구, 시급 기반 예상 수익, 근무 알림.
- **보상:** 시급과 관계없이 유급 타이머 10분에 100P, 한국 시간 하루 최대 4,800P. 한 타이머의 보상은 누적 유급 24시간까지입니다. 수동 기록과 기록 수정은 포인트를 추가하지 않습니다.
- **꾸미기:** 81종 카탈로그, 종류·보유 여부 필터, 실제 3D 모델 미리보기, 구매·장착·해제, 배회와 가구 상호작용.
- **기록:** 기기 시간대의 월별·일별 수익, 근무·휴식·시급 변경 구간 편집, 오래된 revision의 덮어쓰기 방지, CSV 내보내기.
- **화면:** 휴대폰 탭과 큰 화면 탐색 레일, 넓은 홈 화면의 두 열 배치, 다크 모드, 큰 글꼴용 스크롤, 회전 후 편집 초안 복원.
- **주변 화면:** 홈 화면 위젯의 수익·근무 상태, Wear OS의 근무 상태 확인과 원격 시작·휴식·재개·종료 요청.

위젯은 초 단위 타이머가 아닙니다. 시스템 갱신·절전 조건에 따라 늦을 수 있으며 최신 값은 앱에서 확인합니다. Wear OS 앱은 Android 휴대폰의 원본 기록을 사용하며 단독 앱으로 동작하지 않습니다. iPhone과 연결된 시계와 이 Android 앱 사이의 연동은 제공하지 않습니다. [Wear Data Layer 공식 안내](https://developer.android.com/training/wearables/data/overview)

## 현재 검증 상태

2026-09-25 기준 **Android 자동 테스트 134개(JVM 83 + 휴대폰 46 + Wear 5)가 통과**했습니다. 실제 최소 API 26에서는 ATF를 제외한 45개, 최소 Wear API 30에서는 5개가 통과했습니다. [PR #5](https://github.com/eric91405/piyak-bank-ios/pull/5)의 코드 커밋 `8fe25b7`에서 [Android CI](https://github.com/eric91405/piyak-bank-ios/actions/runs/36113766276)와 [iOS CI](https://github.com/eric91405/piyak-bank-ios/actions/runs/36113766453)가 통과했습니다.

| 범위 | 확인된 결과 |
| --- | --- |
| Release | 양쪽 APK·unsigned AAB 생성, Lint 오류 0, 네이티브 16 KB 정렬 통과. 경고는 휴대폰 18·Wear 14, 각 hint 1 |
| 3D | 81종, 메시 363개·삼각형 246,752개. GLES에서 81종·방 9조합·의상 9조합·EGL 복구 검사 |
| 화면 | 실제 Activity 회전·재생성, 좁은/가로/태블릿 viewport·글꼴 2배 자동 검사와 OS 분할 화면·최대 표시 크기 수동 확인 |
| 접근성 | ATF·플랫폼 접근성 트리 통과, 실제 TalkBack 주요 탐색·조작 확인. 스위치 접근은 가상 키 미인식으로 환경 차단 |
| 예외 | API 26 정수 API, CSV 취소·쓰기 실패·회전, 개별 알림 채널과 API 36 권한 거부/재허용 확인 |
| R8 수동 QA | API 36 실제 16 KB 페이지에서 근무·3D·기록, QA 업데이트·재시작·재부팅 후 101원/6P 보존 |
| 남은 단계 | 물리 휴대폰–Wear 연결·GPU·알림·위젯·배터리·보조 입력, 배포 서명과 Play 설치 |

정확한 환경·실행 증거·제약은 [검증 기록](docs/VALIDATION.md), 시나리오는 [UI 계획](docs/UI_TEST_PLAN.md)에 있습니다. 134개는 OS별 반복 검사를 중복 합산하지 않은 수치이며 모든 기기·아이템 조합을 완전 탐색했다는 뜻은 아닙니다. 기존 개인 Google Play 계정의 실제 조건과 최종 서명은 [출시 체크리스트](docs/PLAY_STORE.md)에 따라 확인해야 합니다.

## 개발 환경

| 구성 | 저장소 설정 |
| --- | --- |
| Android Gradle Plugin | 8.13.1 |
| Kotlin / Compose compiler plugin | 2.2.20 |
| Gradle Wrapper | 8.14, 배포 ZIP SHA-256 검증 |
| JDK | 17 이상, 개발 빌드에 Android Studio JBR 21 사용 |
| Android SDK | compileSdk 36 |
| 휴대폰·태블릿 | minSdk 26, targetSdk 36, versionCode 1 |
| Wear OS | minSdk 30, targetSdk 35, versionCode 1000001 |
| 설치 패키지 ID | 두 앱 모두 `com.minseo.piyakbank` |
| UI / 그래픽 | Jetpack Compose·Material 3 / OpenGL ES 2.0 |
| 로컬 저장 | SQLite 트랜잭션과 검증된 상태 직렬화 |

Android Studio에서 이 `android/` 폴더를 열고 SDK Manager로 Android SDK Platform 36과 필요한 빌드 도구를 설치합니다. Gradle JDK는 JDK 17 이상으로 선택합니다. SDK 경로는 Android Studio가 생성하는 로컬 `local.properties` 또는 환경의 Android SDK 설정을 사용하며, 개인 경로를 저장소에 커밋하지 않습니다. 첫 빌드는 Gradle·Maven 의존성 다운로드를 위해 네트워크가 필요합니다.

### 빌드와 테스트

아래 명령의 작업 디렉터리는 `android/`입니다. macOS 예시이며 Windows에서는 `nice`를 빼고 `gradlew.bat`를 사용합니다.

```sh
nice -n 15 ./gradlew --no-daemon --max-workers=1 :core:test :app:testDebugUnitTest :wear:testDebugUnitTest
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:assembleDebug :wear:assembleDebug
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:assembleDebugAndroidTest
```

기본 Debug 기기 검사는 SQLite 중심이며, UI·CSV·알림 예외는 별도 `.uitest` 설치본에서만 실행합니다. 먼저 아래 APK를 빌드한 뒤 QA 전용 기기 하나를 켭니다. 이 변형의 합성 데이터·테스트 제공자는 일반 Debug·Release와 분리됩니다.

```sh
nice -n 15 ./gradlew --no-daemon --max-workers=1 -PpiyakUiTest=true :app:assembleUiTest :app:assembleUiTestAndroidTest
# 빌드가 끝난 뒤 QA 기기에서 실행
nice -n 15 ./gradlew --no-daemon --max-workers=1 -PpiyakUiTest=true :app:connectedUiTestAndroidTest
```

API 26 원격 CI는 Linux KVM에서 미리 빌드한 APK를 설치한 뒤 `am instrument`를 실행합니다. `scripts/verify_instrumentation.py`가 실패·크래시·빈 실행·예상치 못한 skip을 거부하며 로그와 GPU 결과를 artifact로 남깁니다. 아직 원격 통과 결과를 확인하기 전입니다.

Release 코드 축소와 Lint, 배포 번들을 다시 검증하는 명령입니다. 실제 업로드에는 소유자가 준비한 서명이 필요합니다.

```sh
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:lintRelease :wear:lintRelease
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:bundleRelease :wear:bundleRelease
```

기본 산출물:

- 휴대폰 Debug APK: `app/build/outputs/apk/debug/app-debug.apk`
- 시계 Debug APK: `wear/build/outputs/apk/debug/wear-debug.apk`
- 휴대폰 테스트 APK: `app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk`
- 휴대폰 AAB: `app/build/outputs/bundle/release/app-release.aab`
- 시계 AAB: `wear/build/outputs/bundle/release/wear-release.aab`
- 테스트 결과: `core/build/reports/tests/test/`, `app/build/reports/tests/testDebugUnitTest/`, `wear/build/reports/tests/testDebugUnitTest/`
- Lint 결과: 각 앱 모듈의 `build/reports/`

서명 환경 변수가 없으면 Release에 업로드 서명을 적용하지 않습니다. unsigned 번들을 Play 업로드 준비 완료로 취급하지 않습니다. 키 준비와 실제 배포 검증은 [Play Store 출시 체크리스트](docs/PLAY_STORE.md)를 따릅니다.

### 발열을 줄이는 기본값

`gradle.properties`는 worker 1개, 병렬 빌드 끄기, JVM 최대 2GB, JVM processor count 2, Kotlin 컴파일 in-process로 설정했습니다. MacBook Air M4 16GB에서는 빌드와 에뮬레이터 실행을 나누고 사용하지 않는 에뮬레이터를 종료합니다. 실제 발열·메모리 압박에 맞춰 작업을 쉬거나 범위를 줄여야 하며 이 설정이 일정 온도를 보장하지는 않습니다.

앱의 3D 화면도 보이지 않을 때 렌더링을 쉬고, 움직임 설정·절전 모드·시스템 열 상태·동작 줄이기를 반영합니다. 전력과 실제 GPU 호환성은 실기기에서 검증해야 합니다.

## 프로젝트 구조

```text
android/
├── core/                   # 급여·보상·아이템·기록·시계 명령의 순수 Kotlin 규칙
├── app/
│   └── src/
│       ├── main/java/com/minseo/piyakbank/
│       │   ├── ui/         # Compose 화면, 초안과 대화상자 상태
│       │   ├── platform/   # 저장소, 알림, 위젯, 시계 통신, 내보내기
│       │   └── scene/      # 공용 OpenGL 3D 방과 캐릭터 동작
│       ├── main/assets/    # 카탈로그 썸네일과 변환된 3D 모델
│       ├── test/           # JVM 테스트
│       ├── androidTest/    # 저장소·CSV·알림·Compose·GPU instrumentation
│       └── uiTest/         # 격리 QA용 제공자; 일반 Debug·Release 제외
├── wear/                   # 연결된 Wear OS 앱, 공용 scene/assets 사용
├── scripts/                # iOS 원본 기하의 Android 모델 변환·검사
└── docs/                   # 실제 검증 기록, UI 계획, Play 출시 체크리스트
```

3D 모델을 바꿀 때는 [모델 변환 절차](scripts/SCENE.md)를 따릅니다. 일반 Android 빌드는 커밋된 모델을 사용하므로 SceneKit나 macOS 모델 변환이 필요하지 않습니다.

## 데이터와 개인정보

시급·근무·포인트·아이템의 원본은 휴대폰의 앱 저장소에 보관합니다. 개발자 서버, 광고, 이용 행태 분석 전송은 없습니다. 앱 삭제·초기화 전에 필요한 내용을 CSV로 보관해야 하며, CSV는 백업 복원 파일이 아닙니다.

연결된 Wear OS에는 근무 상태·오늘 예상 수익·잔액·장착 정보가 전달됩니다. Google Play services의 Wear Data Layer는 Bluetooth를 사용할 수 없으면 Google 클라우드를 통한 종단 간 암호화 중계를 사용할 수 있습니다. 앱의 `INTERNET` 권한 부재가 이러한 중계를 막는다는 의미는 아닙니다. 같은 패키지 이름과 서명으로 설치된 Android 휴대폰·시계 간에 통신합니다. [Google의 통신·서명 안내](https://developer.android.com/training/wearables/data/overview)

Android 전용 공개 개인정보처리방침: [개인정보처리방침](https://eric91405.github.io/piyak-bank-ios/privacy-android/). Pages 소스는 `main`의 `/docs`이며 2026-09-21 로그인 없이 HTTP 200 응답과 정책 내용을 확인했습니다. 배포 전 공개 페이지와 앱 내 안내의 일치를 확인해야 합니다. 운영자 김민서, 지원 문의 [eric91405@gmail.com](mailto:eric91405@gmail.com).
