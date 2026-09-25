# Google Play 출시 체크리스트

기준일: 2026-09-25. 이 문서는 Android 휴대폰·태블릿 앱과 Wear OS 앱의 배포 준비 절차다. 소유자는 기존 **개인 Google Play 개발자 계정**을 보유한다고 확인했다. 계정 생성일·인증 상태·업로드 권한과 적용되는 테스트 조건은 Console에서 아직 확인하지 않았으며, 실제 Play 업로드나 공개 출시는 수행하지 않았다. 체크되지 않은 항목은 완료로 간주하지 않는다.

## 코드와 테스트의 현재 위치

- [x] [PR #5](https://github.com/eric91405/piyak-bank-ios/pull/5) 코드 `8fe25b7`의 [Android](https://github.com/eric91405/piyak-bank-ios/actions/runs/36113766276)·[iOS](https://github.com/eric91405/piyak-bank-ios/actions/runs/36113766453) 원격 검사 통과.
- [x] JVM 83개, API 36 휴대폰 46개, 최소 Wear API 30 5개 통과. 최소 휴대폰 API 26 원격 실행도 45개 통과.
- [x] 양쪽 Debug/R8 Release APK·unsigned AAB 생성과 16 KB 네이티브 정렬 검사 통과.
- [x] Release Lint 오류 0. 휴대폰 Warning 18·Wear Warning 14 및 각 Hint 1은 남아 있음.
- [x] 81종 카탈로그·메시 363개·삼각형 246,752개, production GLES 81종·방 9조합·의상 9조합·EGL 복구 확인.
- [x] API 26 CSV 선택기 취소/저장·45원 내용·개별 알림 채널, API 36 알림 권한 거부/재허용 확인.
- [x] 실제 ContentResolver·SQLite로 쓰기/닫기 실패·취소·Activity 재생성·예약 오류와 데이터 보존 확인.
- [x] 실제 Activity 회전·재생성, 좁은/가로/태블릿 viewport, ATF·플랫폼 접근성 트리 통과.
- [x] R8 앱의 실제 TalkBack 주요 탐색·조작, 최대 OS 글꼴/표시 크기, OS 분할 화면 확인.
- [x] 동일 QA 인증서의 최신 R8 업데이트·재시작·재부팅 후 101원/6P 보존. Play 서명 검증과는 구분.
- [ ] 스위치 접근 실제 조작: 에뮬레이터의 가상 키 등록 실패로 환경 차단, 물리 보조 입력 장치 필요.
- [ ] 물리 태블릿·휴대폰–Wear 연결·제조사 알림/위젯·GPU·발열·전력·물리 16 KB 기기.
- [ ] 소유자 업로드 키·Play App Signing, 내부 테스트 설치본의 양쪽 앱 인증서·연동·업데이트.
- [ ] Console 계정 조건·스토어 입력·내부/비공개 테스트·production access·사전 출시 보고서.

서로 다른 자동 검사는 **134개(83 + 46 + 5)**다. OS별로 반복한 같은 테스트를 중복 합산하지 않는다. 자세한 실행 환경·제약은 [검증 기록](VALIDATION.md)에 남긴다. unsigned AAB 생성이나 에뮬레이터 통과만으로 출시 준비가 끝난 것은 아니다.

## 패키지, 지원 범위와 버전

| 항목 | 휴대폰·태블릿 | Wear OS |
| --- | --- | --- |
| `applicationId` | `com.minseo.piyakbank` | `com.minseo.piyakbank` |
| `minSdk` | 26 | 30 |
| `compileSdk` | 36 | 36 |
| `targetSdk` | 36 | 35 |
| 초기 `versionCode` | 1 | 1000001 |
| 초기 `versionName` | 1.0.0 | 1.0.0 |
| 독립 사용 | 가능 | 연결된 Android 휴대폰 필요 |

2026년 8월 31일부터 새 앱과 업데이트는 일반 Android API 36 이상, Wear OS API 35 이상을 대상으로 해야 한다. 현재 설정은 이 대상 API 기준에 맞추었으며, 실제 제출 때 Console 요구사항을 다시 확인한다. [Google Play 대상 API 정책](https://support.google.com/googleplay/android-developer/answer/11926878)

두 앱의 applicationId와 최종 설치 서명은 동일해야 Wear Data Layer로 통신한다. `namespace`가 다른 것은 설치 패키지 이름이 다른 것과 구분한다. Wear OS 앱은 Android 휴대폰용이며 iOS 연결을 제공하지 않는다. [Data Layer 지원 범위와 서명 제한](https://developer.android.com/training/wearables/data/overview)

휴대폰·Wear OS의 versionCode 범위를 구분하고 재사용하지 않는다. 업데이트마다 해당 산출물의 코드를 올리고 Play Console에서 지원 기기·폼팩터의 실제 선택 결과를 확인한다. 동일 앱의 Wear OS 배포 설정을 구성하고 시계 번들이 휴대폰용 설치로 노출되지 않는지도 검사한다.

## 소유자가 준비할 서명과 계정

- [x] 소유자에게 기존 개인 Google Play 개발자 계정 보유를 확인했다.
- [ ] 실제 Console에서 계정 생성일·인증 상태·앱 생성/업로드 권한과 해당 계정의 production access 요구사항을 확인한다.
- [ ] 사용자 소유의 업로드 키를 준비하고 안전하게 보관한다. 저장소·로그·공개 CI에 키나 비밀번호를 넣지 않는다.
- [ ] 두 앱을 동일한 서명 구성으로 빌드한다. Play가 배포하는 양쪽 앱의 최종 app signing 인증서도 일치하는지 검증한다.
- [ ] Play App Signing에서 업로드 키와 앱 서명 키의 역할을 확인하고 소유자가 키 접근·복구 수단을 관리한다.
- [ ] 개발용 debug 키와 배포용 설치본의 서명을 구분한다. 서로 다른 서명은 정상 업데이트나 휴대폰–시계 통신을 보장하지 않는다.

프로젝트는 다음 환경 변수를 읽는다. 키를 코드나 예시 비밀번호로 자동 생성하지 않으며, 값은 소유자가 관리하는 비밀 저장소에서 빌드 환경으로 제공한다.

| 환경 변수 | 용도 |
| --- | --- |
| `PIYAK_KEYSTORE` | 업로드 키 저장소 파일 경로 |
| `PIYAK_STORE_PASSWORD` | 키 저장소 비밀번호 |
| `PIYAK_KEY_ALIAS` | 사용할 키 별칭 |
| `PIYAK_KEY_PASSWORD` | 해당 키 비밀번호 |

네 항목을 모두 준비한 뒤 `android/`에서 실행한다.

```sh
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:lintRelease :wear:lintRelease
nice -n 15 ./gradlew --no-daemon --max-workers=1 :app:bundleRelease :wear:bundleRelease
```

업로드 대상은 `app/build/outputs/bundle/release/app-release.aab`와 `wear/build/outputs/bundle/release/wear-release.aab`다. 서명 변수가 없으면 Release에 업로드 서명이 적용되지 않으므로 파일 생성만으로 배포 준비가 끝난 것이 아니다. 실제 생성물의 서명·패키지·버전·대상 SDK를 검사한 뒤 업로드한다.

## 스토어 설명과 제출 자료

표현 초안:

> **삐약뱅크 — 근무 기록과 작은 방 꾸미기**
>
> 일한 시간을 기록하고 예상 수익을 확인하세요. 근무로 모은 포인트로 삐약이의 방을 꾸미며, 휴대폰·위젯·연결된 Wear OS 시계에서 오늘의 근무를 살펴볼 수 있어요.

- [ ] 스토어 제목·짧은 설명·전체 설명을 실제 구현과 맞춘다. 현재 무료이며 로그인·광고·인앱 결제·AI 대화가 없다.
- [ ] 예상 수익은 입력한 시급과 유급 시간의 세전 단순 추정치임을 명시한다. 실제 은행 계좌·입출금·대출·급여 지급 서비스를 제공한다고 표현하지 않는다.
- [ ] 실제 Release 설치 화면으로 휴대폰·태블릿·Wear OS 스크린샷과 필요한 그래픽을 만든다. 합성 잔액이나 개발 도구 화면을 실제 사용자 결과처럼 홍보하지 않는다.
- [ ] 한국어 텍스트, 앱 아이콘, 시작 화면, 지원 이메일 `eric91405@gmail.com`, 운영자 김민서 정보를 확인한다.
- [ ] 대상 연령·콘텐츠 등급·카테고리·광고·앱 액세스 등의 질문을 소유자가 실제 기능에 맞게 작성한다. 계정이 없으므로 로그인용 심사 계정이 필요하지 않다는 점을 앱 액세스 안내에 적는다.
- [ ] 금융 기능 관련 질문이 Console에 제시되면 예상 수익 계산·기록 기능과 실제 금융 서비스 부재를 구분하여 해당 정책과 실제 기능 기준으로 답한다. 앱 이름만으로 신고 답변을 결정하지 않는다.
- [ ] 휴대폰이 필요한 Wear OS 앱이라는 점, 연결이 끊기면 최신 상태와 명령 처리가 제한된다는 점을 안내한다.

## 개인정보와 데이터 보안

공개 정책 주소는 [Android 개인정보처리방침](https://eric91405.github.io/piyak-bank-ios/privacy-android/)이다. Pages 소스는 `main`의 `/docs`이며 2026-09-21 로그인 없이 HTTP 200 응답과 정책 내용을 확인했다. 제출 전에 실제 공개 상태, 로그인 없이 접근 가능 여부, 앱 내 정책과의 일치를 확인한다.

- [ ] 시급·근무·포인트·아이템의 원본이 휴대폰 앱 저장소에 있고 개발자 서버로 전송하지 않는다는 설명을 확인한다.
- [ ] 연결된 시계에 근무 상태·오늘 예상 수익·잔액·장착 정보를 전달한다고 고지한다.
- [ ] Google Play services의 Data Layer가 Google 클라우드를 통한 종단 간 암호화 중계를 사용할 수 있음을 고지한다. 앱에 `INTERNET` 권한이 없다는 이유로 모든 데이터가 기기 밖으로 나가지 않는다고 주장하지 않는다. [공식 통신 경로 안내](https://developer.android.com/training/wearables/data/overview)
- [ ] 데이터 보안 설문은 연결 기기 전송, Google SDK, 사용자가 선택한 CSV 저장·공유 경로를 실제 빌드 기준으로 검토해 작성한다. “자체 서버 없음”만 보고 모든 항목을 자동으로 “없음” 처리하지 않는다.
- [ ] 앱 초기화·삭제와 CSV 보관의 차이, 계정 동기화·CSV 복원 기능이 없다는 점을 안내한다.
- [ ] 필요한 알림 권한과 시스템 설정 동작을 확인한다. 실제로 사용하지 않는 권한·SDK가 최종 병합 Manifest에 추가되지 않았는지 검사한다.

## 테스트 트랙과 실제 출시

2023년 11월 13일 이후 만든 개인 개발자 계정에는, 최소 12명의 테스터가 연속 14일 이상 참여한 비공개 테스트를 거친 뒤 production access를 신청하는 조건이 있다. 신청 과정에는 테스트 내용과 피드백, 출시 준비 상태에 대한 답변이 필요하다. 계정 유형·생성일·Console의 현재 조건을 확인하고 해당 여부를 결정한다. 내부 테스트만으로 이 비공개 테스트 조건을 충족했다고 기록하지 않는다. [새 개인 계정 테스트 요구사항](https://support.google.com/googleplay/android-developer/answer/14151465)

1. 소유자가 Play Console 앱·Wear OS 배포 설정과 필요한 선언을 준비한다.
2. 서명된 두 AAB를 내부 테스트에 올리고 Play에서 실제 설치한다.
3. Release 설치본으로 [UI 테스트 계획](UI_TEST_PLAN.md)의 핵심 흐름을 검증한다. 앱 서명과 Wear 연결, 프로세스·재부팅 복구, 배터리, 위젯·알림, 데이터 보존을 포함한다.
4. 사전 출시 보고서의 충돌·ANR·접근성·기기 호환성 항목을 검토하고 재현한 문제를 수정한다.
5. 계정에 해당하면 비공개 테스트를 운영하고 실제 피드백·수정·재검증 내용을 기록한 뒤 production access를 신청한다.
6. 스토어 자료·정책 URL·데이터 보안·등급·기기 지원·버전·서명을 최종 확인하고 심사를 제출한다.
7. 승인과 게시 상태를 확인하고 초기 사용자 피드백과 Android vitals를 살펴본다. 승인·배포 성공·결함 없음은 빌드 성공만으로 보장되지 않는다.

기존 개인 개발자 계정 보유는 소유자가 확인했다. 정책 선언, 계정별 테스트 조건, 테스터 모집, 키 관리와 Console 배포 상태는 소유자 및 실제 Console에서 추가로 확인할 항목이다. 현재 저장소에는 Play 테스트 트랙·공개 출시가 완료되었다는 증거가 없다.
