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

2026-09-21 기준 JVM 76개와 최종 기기 instrumentation 15개, **서로 다른 자동 테스트 91개를 통과했습니다.** 전체 출시 검증과 Play 배포는 아직 완료되지 않았습니다. 자세한 범위·증거·미실행 항목은 [검증 결과 기록](docs/VALIDATION.md)에 구분했습니다.

| 항목 | 확인된 결과 |
| --- | --- |
| JVM 테스트 | 코어 50개 + 앱 19개 + Wear 7개, 총 76개 통과 |
| 실제 SQLite instrumentation | API 35 Android 에뮬레이터에서 8개 통과 |
| 휴대폰·Wear OS Debug APK | 빌드 성공 |
| Release Lint | 양쪽 오류 0개; 휴대폰 경고 18개, Wear 경고 13개 및 각 hint 1개 |
| 최종 R8 축소 Release APK·AAB | 최신 수정으로 양쪽 재생성 성공; AAB unsigned, 휴대폰 약 9.3 MiB·Wear 약 7.9 MiB |
| 16 KB 네이티브 정렬 검사 | 최종 5개 산출물·4 ABI 검사 통과; APK ELF/무압축 ZIP·AAB ELF |
| 꾸미기·3D 파일 검사 | 카탈로그 81개 일치; 메시 362개·삼각형 245,728개, 원본 크기 검증 통과 |
| API 36·16 KB 페이지 R8 앱 | 로컬 개발용 서명으로 설치·실행; 방·삐약이·배회·화분 상호작용과 주요 근무 흐름 확인 |
| 수동 데이터 보존 | 정산 101원·6P를 프로세스 재시작과 최종 R8 QA APK 덮어쓰기 설치 후에도 보존 |
| 최종 API 36 instrumentation | 실제 16 KB 페이지 환경에서 SQLite 8개·설정 저장소 2개·Compose UI 5개, 총 15개 통과 |
| 가로 화면 | 환경 차단: 자동 회전이 켜져 있어도 현재 AVD가 앱을 세로 상태로 유지; 다른 환경 재검증 필요 |
| Wear API 35 작은 원형 화면 | R8 앱 설치·실행, 오프라인 조작 비활성화와 스크롤·새로고침 접근 확인 |
| 원격 CI | `f060db8` 대상 실행 통과; 후속 변경의 최종 실행은 확인 대기 |
| 실물 휴대폰–Wear OS 연결·알림·위젯·배터리 | 미실행 |
| Play 내부/비공개 테스트·출시 심사 | 미진행 |

Wear 최근 앱 화면·백업 규칙을 수정한 뒤 Lint를 재실행했습니다. 남은 경고가 0개라는 뜻은 아닙니다. 16 KB 페이지는 API 36 에뮬레이터에서 `getconf PAGESIZE`의 16384 값을 확인했으며 물리 기기 검증은 남아 있습니다. 81종 전체 착용 조합, 접근성, 실제 시계 연결과 Play 설치 검증은 [UI 테스트 계획](docs/UI_TEST_PLAN.md)을 따릅니다. 소유자는 기존 개인 Google Play 개발자 계정을 보유한다고 확인했으며, 계정 생성일과 적용 테스트 조건은 Console에서 확인해야 합니다.

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

QA 전용 휴대폰 또는 에뮬레이터를 하나 연결한 뒤 instrumentation 테스트를 실행합니다. 합성 데이터용 테스트 기기에서만 실행하고 실제 사용자의 기록이 든 설치본과 구분합니다.

```sh
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:connectedDebugAndroidTest
```

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
│       └── androidTest/    # 기기 저장소 instrumentation 테스트
├── wear/                   # 연결된 Wear OS 앱, 공용 scene/assets 사용
├── scripts/                # iOS 원본 기하의 Android 모델 변환·검사
└── docs/                   # 실제 검증 기록, UI 계획, Play 출시 체크리스트
```

3D 모델을 바꿀 때는 [모델 변환 절차](scripts/SCENE.md)를 따릅니다. 일반 Android 빌드는 커밋된 모델을 사용하므로 SceneKit나 macOS 모델 변환이 필요하지 않습니다.

## 데이터와 개인정보

시급·근무·포인트·아이템의 원본은 휴대폰의 앱 저장소에 보관합니다. 개발자 서버, 광고, 이용 행태 분석 전송은 없습니다. 앱 삭제·초기화 전에 필요한 내용을 CSV로 보관해야 하며, CSV는 백업 복원 파일이 아닙니다.

연결된 Wear OS에는 근무 상태·오늘 예상 수익·잔액·장착 정보가 전달됩니다. Google Play services의 Wear Data Layer는 Bluetooth를 사용할 수 없으면 Google 클라우드를 통한 종단 간 암호화 중계를 사용할 수 있습니다. 앱의 `INTERNET` 권한 부재가 이러한 중계를 막는다는 의미는 아닙니다. 같은 패키지 이름과 서명으로 설치된 Android 휴대폰·시계 간에 통신합니다. [Google의 통신·서명 안내](https://developer.android.com/training/wearables/data/overview)

Android 전용 공개 개인정보처리방침 예정 주소: [개인정보처리방침](https://eric91405.github.io/piyak-bank-ios/privacy-android/). 배포 전 실제 공개 페이지 접근과 앱 내 안내의 일치를 확인해야 합니다. 운영자 김민서, 지원 문의 [eric91405@gmail.com](mailto:eric91405@gmail.com).
