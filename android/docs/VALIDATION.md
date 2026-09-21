# Android 검증 결과 기록

기준일: 2026-09-21. [PR #4](https://github.com/eric91405/piyak-bank-ios/pull/4)로 `main`에 병합한 Android 작업에서 직접 실행한 결과와 남은 검증을 구분한다(병합 커밋 `4786cdd`). 이 문서는 **Play 출시 승인, 실기기 전체 호환성, 결함 없음의 보증이 아니다.** 후속 코드 변경 시 영향을 받는 검사는 해당 커밋과 Release 산출물에서 다시 확인한다.

## 실행을 확인한 검사

| 검사 | 결과 | 확인 범위와 증거 |
| --- | --- | --- |
| 순수 Kotlin 코어 JVM | **50개 통과**, 실패·오류·건너뜀 0개 | `core/build/test-results/test/TEST-*.xml`; 임금·일별 분배·KST 보상·시계 변경·재부팅·기록 revision·구매·Watch 명령 정책 |
| 휴대폰 앱 JVM | **19개 통과**, 실패·오류·건너뜀 0개 | `app/build/test-results/testDebugUnitTest/TEST-*.xml`; JSON 저장 형식 11개, 캐릭터 동작 규칙 4개, 설정 변경 정책 4개 |
| Wear JVM | **7개 통과**, 실패·오류·건너뜀 0개 | `wear/build/test-results/testDebugUnitTest/TEST-*.xml`; 최초 응답 전 push, 요청 단일 실행, 만료·노드 변경·이전 응답 배제 |
| Android 실제 SQLite | **8개 통과** | API 35 에뮬레이터에서 `BankDatabaseTest` 실행, instrumentation 출력 `OK (8 tests)` |
| 휴대폰·Wear Debug | **APK 생성 성공** | 각 모듈 `build/outputs/apk/debug/` |
| 휴대폰 Release Lint | **오류 0개**, 경고 18개, hint 1개 | `app/build/reports/lint-results-release.xml` 및 `.txt` |
| Wear Release Lint | **오류 0개**, 경고 13개, hint 1개 | `wear/build/reports/lint-results-release.xml` 및 `.txt` |
| 최종 R8 축소 Release | **최신 수정으로 양쪽 APK·AAB 재생성 성공**, AAB 업로드 서명 없음 | 최종 빌드 1분 42초; AAB 휴대폰 9,715,780바이트(약 9.3 MiB), Wear 8,267,672바이트(약 7.9 MiB); `build/outputs/bundle/release/` |
| 네이티브 16 KB 정렬 | **최종 APK·AAB 등 5개 산출물, 포함된 4 ABI 검사 통과** | `scripts/check_native_alignment.py`; APK의 ELF LOAD·무압축 `.so` ZIP 정렬, AAB 내부 ELF LOAD 정렬 검사 |
| iOS/Android 카탈로그 | **81개 일치** | `core/verify_catalog.py`; ID·슬롯·이름·가격·기본 보유 정보 |
| 변환된 3D 파일 | **메시 362개, 삼각형 245,728개 검사 통과** | `scripts/check_scene_assets.py`; 원본 기하 경계와 바이너리·인덱스·노멀·카탈로그 연결 검사 |
| API 36 실제 페이지 크기 | **16,384바이트 확인** | 에뮬레이터에서 `getconf PAGESIZE` 실행; 파일 정렬 검사와 별도의 실행 증거 |
| API 36 R8 앱 수동 실행 | **주요 흐름 확인** | 로컬 개발용 서명으로 설치한 축소 Release APK에서 첫 설정·근무·정산·재시작·화분 미리보기 확인 |
| 최종 R8 QA 앱 업데이트 | **기존 QA 위 설치·실행·데이터 보존 확인** | 같은 로컬 개발용 인증서의 최종 APK로 업데이트 후 101원·6P 유지, 방·화분 GPU 표시 정상 확인; Play 서명 검증 아님 |
| API 36 GPU 관찰 | **방·삐약이·창문·러그·화분 및 동작 확인** | 수정된 메시의 올바른 크기·배회·화분 상호작용을 관찰; 81종 전체 조합을 뜻하지 않음 |
| API 36 최종 instrumentation | **15개 모두 통과**, 실행 10.627초 | 실제 16 KB 페이지 환경, `OK (15 tests)`; SQLite 8개·설정 저장소 2개·Compose UI 5개. 최초 실행의 Snackbar 가림 결함 수정 후 재검증 |
| Wear API 35 R8 앱 수동 실행 | **작은 원형 화면의 오프라인 흐름 확인** | 설치·실행, 조작 버튼 비활성화, 스크롤·새로고침 접근. 실제 휴대폰과 연결하지 않음 |
| PR 최종 커밋 원격 CI | **`009fb1f`의 Android·iOS 모두 통과** | [Android 실행 35574930705](https://github.com/eric91405/piyak-bank-ios/actions/runs/35574930705) · [iOS 실행 35574930707](https://github.com/eric91405/piyak-bank-ios/actions/runs/35574930707) |
| 공개 정책·지원 페이지 | **4개 주소 HTTP 200 및 내용 확인** | `main`의 `/docs`를 Pages 소스로 설정. [홈](https://eric91405.github.io/piyak-bank-ios/)·[iOS 정책](https://eric91405.github.io/piyak-bank-ios/privacy/)·[Android 정책](https://eric91405.github.io/piyak-bank-ios/privacy-android/)·[지원](https://eric91405.github.io/piyak-bank-ios/support/)을 인증 없이 확인 |

**서로 다른 자동 테스트는 총 91개(JVM 76 + 최종 instrumentation 15)다.** API 35 SQLite 8개는 API 36에서도 실행한 같은 테스트이므로 별도로 중복 합산하지 않는다.

위 XML·APK·AAB·Lint 보고서는 로컬 또는 CI에서 생성하는 결과물이며 저장소에 빌드 디렉터리 전체를 커밋하지 않는다. 이후 재실행 시 수치가 달라지면 이 기록을 갱신한다. AAB 크기는 위 검증 시점의 파일 크기이며 기기별 Play 다운로드·설치 크기는 아니다.

### SQLite 검사의 구체적 범위

테스트 전용 이름의 합성 데이터베이스만 사용했다. 실제 SQLite에서 파일을 닫고 다시 열어 기록·원장·진행 중 상태가 유지되는지, 서로 다른 연결의 오래된 revision이 저장을 덮어쓰지 못하는지 확인했다. SQL 오류를 주입한 정산의 전체 롤백과 재시도, 손상된 JSON의 원본 보존, revision 불일치, 잘못된 상태 거부, 미래 스키마의 다운그레이드 금지도 검사했다.

이는 물리 기기의 저장 공간 부족·전원 손실·제조사별 파일 시스템과 동일한 시험은 아니다. 실제 사용자 저장소를 손상시키거나 초기화해 시험하지 않았다.

### GPU·기기에서 직접 확인한 범위

API 36 휴대폰 에뮬레이터에서 실제 페이지 크기 16,384바이트를 확인하고, R8로 축소한 Release APK를 로컬 개발용 서명으로 설치했다. 이는 Debug 코드 빌드의 실행 결과와 구분하며, 소유자의 업로드 키나 Play 최종 앱 서명 검증은 아니다. 첫 설정, 시작·휴식·재개·종료를 실행해 **예상 수익 101원·보상 6P**를 확인했고, 프로세스를 다시 실행한 뒤 두 값이 유지됐다. 화분 미리보기도 열었다. 이 실행에서 확인한 휴대폰 앱 크래시 로그는 비어 있었다. 이후 같은 로컬 개발용 인증서로 서명한 **최종 R8 QA APK를 기존 QA 설치 위에 업데이트**하고 다시 실행했다. 101원·6P가 유지됐고 방과 화분의 GPU 표시도 올바르게 확인했다. 이 결과는 동일한 QA 인증서의 업데이트 검증이며 Play 최종 앱 서명이나 최소 지원 OS 검증을 대신하지 않는다.

모델 변환에서 일부 원시 도형 크기가 단위 크기로 대체되던 결함은 명시된 치수의 직접 메시 변환으로 수정했다. 수정된 방·삐약이·창문·러그·화분이 실제 에뮬레이터 GPU에서 올바르게 표시됐고, 배회와 화분 상호작용을 관찰했다. **카탈로그 81종 전부, 모든 착용 조합·시점·물리 GPU의 검증은 아니다.**

Wear API 35 작은 원형 에뮬레이터에도 R8 QA APK를 설치해 실행했다. 휴대폰과 연결되지 않은 상태에서 원격 조작이 비활성화됐고, 스크롤·새로고침에 접근할 수 있었다. 이 시스템 이미지의 부팅·캡처 중 `sensorservice`와 `screencap` 시스템 프로세스 오류를 관찰했다. 이를 삐약뱅크 앱 프로세스 크래시로 기록하지 않으며, 해당 환경의 캡처·시스템 안정성 제약으로 구분한다. 실제 연결된 휴대폰–Wear 통신은 미검증이다.

가로 화면은 **환경 차단**으로 기록한다. Pixel 7 AVD의 빠른 설정에서 자동 회전 On을 확인했지만, 에뮬레이터의 왼쪽 회전은 표면을 돌릴 뿐 Android 앱의 창은 세로 상태를 유지했다. 가로 레이아웃을 실제로 실행한 것으로 판단할 수 없어 통과 처리하지 않았다. 물리 기기 또는 다른 시스템 이미지에서 다시 검증해야 한다.

### 발견한 결함과 재검증 상태

- API 36 최초 instrumentation 실행은 SQLite·UI를 합쳐 **13개 중 12개 통과·1개 실패**였다. 근무 시작 뒤 Snackbar가 하단 휴식 버튼을 덮어 실제 터치를 막는 결함을 수동으로도 확인했다. Snackbar를 측정한 조작 영역 위로 배치하도록 수정했으며, 테스트는 즉시 조작과 영역 비겹침을 확인한다. **설정 저장소 테스트 2개를 추가한 총 15개 최종 재실행은 10.627초에 모두 통과했다.**
- 오래된 종료 확인이 시계에서 새로 시작한 근무를 끝내는 문제를 세션·상태 토큰으로 방지했다. 설정 변경은 필드별로 최신 저장 값에 반영하고, 근무 시작이 먼저 저장됐다면 시급 변경을 거부한다. 해당 정책을 포함한 최신 JVM **76개는 통과**했으며 실제 저장소의 동시 설정 변경 2개 검사도 최종 instrumentation 실행에서 통과했다.
- Wear의 최근 앱 화면(`WearRecents`)과 백업 규칙(`DataExtractionRules`)을 수정하고 Release Lint를 다시 실행했다. Wear 결과는 **오류 0개·경고 13개·hint 1개**다. 남은 경고는 별도 검토 대상이며 경고 0개로 표현하지 않는다.
- 최초 Wear 응답 전 push가 도착할 때의 요청 반복, UI 상태 갱신 경쟁, 이전 알림과 휴식·설정 변경의 경쟁을 보완했다. 순수 정책 검사는 통과했지만 실제 휴대폰–시계 전송과 시스템 알림의 종합 검증은 남아 있다.

[PR #4](https://github.com/eric91405/piyak-bank-ios/pull/4)는 `main`에 병합했다(병합 커밋 `4786cdd`). 원격 CI 성공을 확인한 대상은 PR 최종 커밋 `009fb1f`이며, [Android 실행](https://github.com/eric91405/piyak-bank-ios/actions/runs/35574930705)과 [iOS 실행](https://github.com/eric91405/piyak-bank-ios/actions/runs/35574930707)이 모두 통과했다. 로컬 최종 instrumentation 15개, 최종 R8 APK·AAB 빌드와 5개 산출물의 16 KB 정렬 재검사도 통과했다. 이 기록은 병합 커밋에서 별도 CI를 실행했다는 의미가 아니다.

## 아직 완료되지 않은 검증

| 항목 | 상태 | 필요한 실행 |
| --- | --- | --- |
| 81개 아이템·전체 착용 조합 | 부분 확인, 전체 미완료 | 기본 방·삐약이·화분 확인 외에 모든 모델·조합·시점·클리핑·수명 주기 검증 |
| 자동 검사에 포함되지 않은 전체 UI 시나리오 | 미완료 | 최종 instrumentation 15개 통과와 구분해 아래 화면·기기별 수동 계획 수행 |
| 최소 Android API 26 / Wear API 30 | 미실행 | 최소 지원 버전에서 설치·실행·저장소·알림·화면 검증 |
| 가로 화면 | **환경 차단** | 자동 회전 On·회전 조작에도 앱이 세로로 남는 AVD 제약. 실기기/다른 이미지에서 실제 가로 창으로 재검증 |
| 태블릿·분할 화면·좁은 화면 | 전체 검증 미완료 | 창 변경, 입력 초안, 스크롤과 모든 버튼 접근 확인 |
| TalkBack·최대 글꼴·표시 크기·스위치 접근 | 미실행 | 실제 접근성 탐색·읽기·입력·포커스·대비 검증 |
| 물리 Android GPU와 장시간 전력 | 미실행 | 서로 다른 GPU·제조사에서 렌더링·배터리·열 상태·프로세스 복구 확인 |
| 물리 기기의 알림·위젯 | 미실행 | 권한 거절/재허용, 절전·방해 금지, 시간대·날짜·재부팅·예약 취소 확인 |
| 연결된 물리 휴대폰–Wear OS | 미실행 | 최초 연결·시작/휴식/재개/종료·오프라인·재연결·노드 변경·초기화·양쪽 재부팅 |
| 물리 16 KB 페이지 기기 실행 | 미실행 | API 36 16 KB 에뮬레이터 실행과 구분하여 최종 배포 설치본의 물리 기기 실행 확인 |
| CSV 실제 제공자·실패·취소 | 전체 검증 미완료 | 문서 저장 제공자, 한글·날짜·합계, 취소·저장 실패 경로 확인 |
| 배포 서명 Release 설치·업데이트 | 미진행 | 로컬 개발용 서명 QA 설치와 구분하여 소유자 업로드 키·Play 최종 서명·업데이트·양쪽 통신 확인 |
| Play 내부/비공개 테스트와 사전 출시 보고서 | 미진행 | Console 계정·조건 확인 후 실제 설치·충돌·ANR·접근성·피드백 검증 |
| 스토어·개인정보 제출 항목 | 미완료 | 공개 정책 URL, 데이터 보안·등급·지원 정보·스크린샷·계정별 요구사항 확인 |

소유자는 **기존 개인 Google Play 개발자 계정 보유**를 확인했다. 계정 생성일·인증·권한·비공개 테스트와 production access 조건은 아직 Console에서 확인하지 않았다. 서명·계정·Play 단계는 [출시 체크리스트](PLAY_STORE.md)를 따르며 iOS의 Apple Developer Program 또는 TestFlight 상태를 Google Play 계정 상태로 추정하지 않는다.

## 재현 명령과 기록 규칙

`android/`에서 JVM·정적·번들 검사를 실행한다. 발열을 줄이기 위해 worker 1개를 유지하고, 빌드 중에는 에뮬레이터를 종료한다.

```sh
nice -n 15 ./gradlew --no-daemon --max-workers=1 :core:test :app:testDebugUnitTest :wear:testDebugUnitTest
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:lintRelease :wear:lintRelease
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:bundleRelease :wear:bundleRelease
python3 core/verify_catalog.py
python3 scripts/check_scene_assets.py
python3 scripts/check_native_alignment.py app/build/outputs/apk/debug/app-debug.apk wear/build/outputs/apk/debug/wear-debug.apk app/build/outputs/bundle/release/app-release.aab wear/build/outputs/bundle/release/wear-release.aab
```

기기 검사는 빌드가 끝난 뒤 QA 기기 한 대에서 별도로 실행한다. 실행마다 커밋·빌드 종류·기기/API·설정·합성 데이터 조건·명령·결과를 남기고, 실패를 수정했으면 영향을 받는 경로를 재검증한다. 초기 검증과 최종 수정 후 결과를 섞어 모든 항목을 통과로 표시하지 않는다.
