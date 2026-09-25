# Android 검증 결과 기록

기준일: **2026-09-25**. [PR #5](https://github.com/eric91405/piyak-bank-ios/pull/5)의 최소 OS·화면·접근성·CSV·알림·3D 보완 결과다. **서로 다른 Android 자동 테스트 134개가 통과**했다. 수동 검증 범위와 환경 차단, 물리 기기·Play 배포 단계는 아래에 별도로 기록한다. 모든 기기에서 결함이 없음을 보장하는 수치가 아니다.

## 실행 결과

| 검사 | 결과 | 환경·증거 |
| --- | --- | --- |
| 코어 / 앱 / Wear JVM | **52 + 19 + 12 = 83개 통과**, 실패·오류·skip 0 | 각 모듈 `build/test-results/` XML |
| 휴대폰 API 36 | **46개 통과**, 실패·skip 0, 59.685초 | 실제 16 KB 페이지 ARM64 에뮬레이터, 격리 `.uitest`; SQLite·CSV·알림·설정·GPU·Compose·ATF·플랫폼 접근성 트리 |
| 최소 휴대폰 API 26 | **45개 통과**, 79.549초 | Linux x86 KVM 원격 실행. API 34 이상 ATF 한 개는 SDK 조건으로 대상에서 제외되며 skip으로 보고되지 않음 |
| 최소 Wear API 30 | **5개 통과** | 실제 Wear 에뮬레이터, 오프라인·오래된 대상·상태 복원·큰 글꼴·Activity 재생성. 연결 상태는 합성 데이터 |
| Release Lint | **양쪽 오류 0개** | 휴대폰 Warning 18·Hint 1, Wear Warning 14·Hint 1. 경고 0개를 의미하지 않음 |
| Debug / R8 Release | **휴대폰·Wear APK와 AAB 생성 성공** | AAB는 업로드 서명 없음. 수동 QA APK만 로컬 개발용 인증서로 서명 |
| 네이티브 16 KB 정렬 | **검사 통과** | APK·AAB의 포함된 4 ABI ELF LOAD, APK의 무압축 `.so` ZIP 정렬. 최종 휴대폰 수정 후 재검사 |
| 카탈로그·원본 메시 | **81종, 메시 363개, 삼각형 246,752개 통과** | `verify_catalog.py`, `check_scene_assets.py`; 원본 크기·행렬·프레임 연속성·노멀·인덱스 검사 |
| production GLES | **81종 + 방 9조합 + 의상 9조합 통과** | API 26/36 렌더링·GL 오류·실루엣·대비·중복 이미지·EGL 컨텍스트 복구 검사, 생성 contact sheet 육안 확인 |
| 원격 Android CI | **빌드·JVM·Lint·번들·정렬·최소 API 모두 통과** | 코드 커밋 `8fe25b7`, [실행 36113766276](https://github.com/eric91405/piyak-bank-ios/actions/runs/36113766276) |
| iOS 회귀 | **Swift 115개·초기 스키마 이전·Release 빌드 통과** | [실행 36113766453](https://github.com/eric91405/piyak-bank-ios/actions/runs/36113766453). Android 테스트와 별도 |
| 공개 페이지 | **4개 HTTP 200과 내용 확인, 2026-09-21** | `main/docs` Pages: [홈](https://eric91405.github.io/piyak-bank-ios/)·[iOS 정책](https://eric91405.github.io/piyak-bank-ios/privacy/)·[Android 정책](https://eric91405.github.io/piyak-bank-ios/privacy-android/)·[지원](https://eric91405.github.io/piyak-bank-ios/support/) |

134개는 **JVM 83 + 휴대폰 46 + Wear 5**다. API 26/35/36에서 반복한 같은 테스트를 더하지 않는다. API 26 ARM64 로컬 실행도 이전 44개 묶음에서 통과했고, 이후 추가한 플랫폼 접근성 트리를 포함한 최종 45개는 위 원격 실행에서 확인했다. CI는 빈 실행·중단·실패·예상하지 않은 skip·필수 클래스 누락을 결과 파서로 거부한다.

CI 산출물 `piyak-android-validation`에 보고서와 APK/AAB, `piyak-phone-api26-instrumentation`에 원시 instrumentation 출력·JSON 요약·GPU PNG/tar가 남는다. 후자는 보존 기간 14일이므로 영구 보관소가 아니며 필요 시 같은 명령으로 재생성한다. 빌드 디렉터리 전체는 Git에 커밋하지 않는다.

## 수동 QA와 검증의 한계

### 최소 OS·저장·시스템 경계

- API 26 R8 앱에서 온보딩, 근무·휴식·정산, 재실행·재부팅 후 **45원·2P** 보존을 확인했다. 시스템 문서 선택기의 취소와 Downloads 저장을 직접 조작하고 CSV의 UTF-8 BOM·한글 헤더·45원 합계를 확인했다.
- API 26에서 앱 전체 알림 허용을 유지한 채 개별 채널을 차단했다. 앱의 차단 표시와 활성화 거부를 확인한 후 시스템에서 재허용하고 앱 설정을 다시 켰다.
- API 36에서 실제 알림 런타임 권한 팝업의 거부, 안내 표시, 시스템 설정에서 재허용, 앱의 허용 상태 반영과 스위치 활성화를 확인했다. 제조사 절전 환경의 실제 알림 도착 시간을 검증한 것은 아니다.
- API 36의 `getconf PAGESIZE`는 **16384**였다. R8 앱의 시작·휴식·재개·정산·화분 미리보기, 프로세스 재실행을 확인했다. 최신 QA APK를 같은 개발용 인증서로 덮어 설치하고 재부팅·분할 화면 조작 후에도 **101원·6P**를 유지했다. 마지막 수동 실행의 crash 로그는 비어 있었다.
- 실제 ContentResolver를 사용하는 격리 테스트로 null URI/stream·권한 해제·쓰기/flush/close 실패·취소·저장 중 Activity 재생성을 검사했다. 테스트 제공자는 `src/uiTest`에만 있으며 Release에 노출되지 않는다. 외부 클라우드 제공자 전체를 시험한 것은 아니다.
- SQLite 검사는 합성 데이터만 사용한다. 재열기·두 연결의 revision 충돌·SQL 오류 정산 롤백과 재시도·손상 JSON 원본 보존·잘못된 상태·미래 스키마 다운그레이드 거부를 확인했다. 물리 저장 공간 부족이나 전원 손실과 동일한 시험은 아니다.

### 화면과 접근성

- 실제 Activity의 세로/가로 변경과 재생성에서 선택 탭·기록 구간·시급 초안을 유지했다. 별도의 Compose viewport 검사로 320dp, 720×360dp 가로, 태블릿 배치, 글꼴 2배와 스크롤·대화상자를 확인했다. 물리 태블릿 검증과는 구분한다.
- API 36 R8 앱에서 **OS의 실제 분할 화면**을 Settings와 함께 열어 홈, 탭 전환, 101원 기록, 시작 확인창과 취소 버튼에 접근했다. 분할 창을 종료한 후에도 앱 데이터를 유지했다.
- OS 설정에서 **font_scale 2.0 / density 540**을 함께 적용했다. 홈·기록·탭, 스크롤과 시작 확인창의 취소/시작 버튼 접근을 확인하고 **1.0 / 420**으로 복원했다.
- **TalkBack 16.0.0.738667889**를 켜고 시스템의 읽기 텍스트 표시와 포커스를 확인했다. 홈 제목·포인트·상태·3D 방 설명·장면 조작, 네 탭, 시작 확인/취소, 움직임 정지, 화분 미리보기 열기/닫기, 기록 편집 입력창 접근/취소를 직접 수행했다. 음성 발음 품질이나 모든 오류의 실제 낭독을 확인했다고 주장하지 않는다. ATF와 잘못된 입력 검사는 별도의 자동 결과다.
- **스위치 접근: 환경 차단.** 설치된 Google Switch Access를 활성화했으나 USB 장치 없음으로 설정 마법사를 완료하지 못했고, 수동 할당 화면도 Android Studio의 가상 볼륨 키·키보드 입력을 스위치로 등록하지 않았다. 스위치로 앱을 조작하는 시험은 미완료이며 실제 보조 입력 장치에서 확인해야 한다. 시험 후 TalkBack·Switch Access는 모두 껐다. QA 에뮬레이터의 내비게이션은 3버튼 상태다.

### 3D와 Wear

81개 아이템을 각각 렌더링하고 모든 슬롯의 아이템이 한 번씩 포함되도록 방 9조합·의상 9조합을 검사했다. 선인장 가지와 곡선 튜브의 연결, 카테고리별 contact sheet를 확인했다. 단색 러그 세 종류는 단순한 색상 수 대신 대비·실루엣 검사를 유지한다. **모든 가능한 조합·시점·물리 GPU를 완전 탐색한 결과가 아니다.**

Wear API 30의 실제 기기 테스트 5개와 API 35 작은 원형 R8 화면의 오프라인 안내·조작 비활성화·스크롤·새로고침을 확인했다. API 35 이미지의 `sensorservice`/캡처 시스템 오류는 앱 크래시와 구분한다. 물리 휴대폰–시계의 페어링·Data Layer 전송은 아직 검증하지 않았다.

## 발견해서 수정한 결함

- **API 26 수익 계산 크래시:** 존재하지 않는 `BigInteger.longValueExact()` 대신 비트 길이 범위를 검사하는 호환 변환을 사용한다. 오버플로 거부를 유지하며 최소 OS 실행을 CI에 추가했다.
- **회전 중 CSV 중단·중복:** application 참조만 가진 ViewModel이 진행 작업과 결과를 유지한다. 취소를 실패로 변환하지 않고 스트림 종료 실패도 성공으로 보고하지 않는다.
- **알림 권한과 상태 불일치:** 앱 권한과 개별 채널을 함께 확인하고 오래되거나 손상된 예약, 재허용, 중간 취소를 처리한다. 시스템 동기화 실패가 저장된 근무·원장을 되돌리지 않는다.
- **큰 글꼴과 창 변경:** 버튼 너비·스크롤·짧은 가로 탐색을 보완했다. density 변경 후 Compose 대화상자가 사라지는 문제는 창을 다시 만들되 입력 초안은 외부에 유지하여 해결했다.
- **TalkBack의 3D 방 설명 누락:** Compose 내부 테스트에는 보이지만 native View가 플랫폼 접근성 트리에서 설명을 숨겼다. 설명을 Compose 부모에 옮기고 자식 native View의 중복 노드를 숨겼다. 실제 TalkBack과 플랫폼 접근성 트리 회귀 테스트 모두 재확인했다.
- **오래된 Wear 종료 대상:** 확인창을 열 때의 인스턴스·세션·상태와 현재 대상을 비교해 이전 명령으로 새 근무를 끝내지 못하게 했다.
- **3D 곡선 이음새:** 튜브의 프레임 연속성과 닫힌 곡선의 비틀림을 보정하고 선인장 가지 끝을 연결했다. iOS·Android·Watch 생성 에셋과 버전 지문을 함께 갱신했다.
- **CI 환경 경쟁:** 선택적 logcat 청소 실패는 경고로 남기고 실제 테스트는 수행한다. KVM udev 권한 반영을 기다린 후 확인한다. 테스트 실패·누락을 통과시키는 완화는 하지 않았다.

## 배포 전 남은 검증

| 항목 | 다음 실행 |
| --- | --- |
| 물리 휴대폰–Wear OS | 최초 연결·시작/휴식/재개/종료·오프라인·재연결·노드 변경·초기화·양쪽 재부팅 |
| 물리 태블릿·보조 입력 장치 | 실제 화면/다중 창과 스위치 조작, TalkBack 오류 낭독·한국어 음성 확인 |
| 제조사·물리 GPU·장시간 전력 | 서로 다른 GPU, 배터리·발열·절전·프로세스 복구, 물리 16 KB 기기 |
| 실제 알림·위젯 | 권한·채널·방해 금지·절전·날짜·시간대·재부팅·예약 취소와 화면 갱신 |
| 배포 서명과 Play 설치 | 소유자 업로드 키, 양쪽 최종 app signing 인증서, 내부 테스트 설치·업데이트·연동 |
| Play Console 제출 | 계정별 조건, 데이터 보안·등급·지원 정보·스크린샷, 사전 출시 보고서와 실제 피드백 |

기존 **개인 Google Play 개발자 계정 보유**는 확인했다. 생성일·인증·production access·테스트 조건은 아직 Console에서 확인하지 않았다. [출시 체크리스트](PLAY_STORE.md)를 따른다. Android 자동 검증 결과로 iOS 미완료 항목이나 물리 기기·스토어 설치를 완료 처리하지 않는다.

## 재현과 산출물

`android/`에서 실행한다. 로컬은 worker 1개·nice 15·JVM CPU 2개/최대 2GB를 사용하며 빌드와 에뮬레이터를 겹치지 않는다. 한 번에 QA 에뮬레이터 하나만 실행하고 작업 후 종료한다. 9월 25일 수동 QA 동안 macOS thermal state는 nominal이었다.

```sh
nice -n 15 ./gradlew --no-daemon --max-workers=1 :core:test :app:testDebugUnitTest :wear:testDebugUnitTest
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:lintRelease :wear:lintRelease :app:bundleRelease :wear:bundleRelease
nice -n 15 ./gradlew --no-daemon --max-workers=1 -PpiyakUiTest=true :app:assembleUiTest :app:assembleUiTestAndroidTest
python3 core/verify_catalog.py
python3 scripts/check_scene_assets.py
python3 scripts/check_native_alignment.py app/build/outputs/bundle/release/app-release.aab wear/build/outputs/bundle/release/wear-release.aab
# 빌드 완료 후 합성 QA 기기를 켠 다음 실행
bash scripts/run_phone_instrumentation_ci.sh
```

로컬 최종 unsigned AAB: 휴대폰 **9,785,514바이트**, Wear **8,306,160바이트**. 기기별 Play 다운로드 크기가 아니다. 로컬 환경의 파일 식별값이며 CI 재빌드의 바이트 동일성을 의미하지 않는다.

| AAB | SHA-256 |
| --- | --- |
| 휴대폰 | `2343c72f8ecb94059511252ade1724ea38e116e80652b829235c345a173d32e9` |
| Wear | `82391d78f0b6343c2ac24f69e7b7e3a06e8f0ab0771c0b74cdc67a724f991833` |
