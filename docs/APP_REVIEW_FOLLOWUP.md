# App Review 추가 정보 대응 · 2026-09-27

상태: **1.0 (4) 재제출 완료 — 2026-09-27 21:11 KST에 ‘심사 대기 중’ 확인.** 사용자가 정상 동작을 보고한 새 85초 영상에서 문의하기의 빌드 1.0 (4)와 새 설정 상세 화면을 확인했습니다. App Store Connect의 심사 빌드를 4로 교체하고 영상과 아래 3,722자 문안을 심사 Notes·회신에 반영했습니다. 21:09 KST 회신 전송 후 ‘심사 업데이트’와 ‘앱 심사에 다시 제출’을 완료했습니다. 출시 설정은 **승인 후 자동 출시**입니다. 심사 접수이며 승인·공개 출시 완료는 아닙니다.

최초 제출: iOS 1.0 (2), ID `619653b0-9aa4-4b2f-9972-0157e1b90097`.
근거: 사용자 제공 App Store Connect 스크린샷 3장과 2026-09-27 라이브 페이지 재조회. Apple 메시지 시각은 2026-09-26 13:56이며 당시 상태는 해결되지 않은 문제 / 심사를 통과하지 못함이었습니다.

## Apple 요청과 현재 준비 범위

메시지 제목은 **Guideline 2.1 - Information Needed - New App Submission**입니다. Apple은 개발자 계정의 제한적인 심사 이력을 언급하고 다음 여섯 항목을 회신 및 App Review Information의 Notes에 추가하도록 요구했습니다.

1. 최신 OS의 실물 기기에서 앱 실행부터 주요 사용 흐름을 보여 주는 화면 녹화.
2. 앱 목적, 대상 사용자, 해결하는 문제와 제공 가치.
3. 초기 설정과 주요 기능 사용 방법, 필요한 로그인/샘플 파일.
4. 핵심 기능에 사용하는 외부 서비스·도구·플랫폼.
5. 지역별 기능/콘텐츠 차이 또는 동일 동작 설명.
6. 규제 대상 서비스·보호된 타사 자료를 제공하는 경우 관련 권한 문서.

하단의 Prevent Common Issues는 일반 예방 안내입니다. 이 메시지에 특정 크래시, 오류 재현 단계, 발견된 유료 상품 누락이나 UGC 신고 기능 결함이 명시되지는 않았습니다. 다만 이것이 앱의 나머지 검사를 모두 통과했다는 뜻은 아닙니다.

현재 제출 소스의 iOS 코드·프로젝트 의존성·설정·에셋 생성기를 검토해 2~6번 답변 초안을 준비했습니다. 계정/회원가입·공개 UGC·유료 콘텐츠는 없으며 개인 근무 기록과 사용자가 선택하는 CSV 내보내기가 있습니다. 금융기관 연동·실제 결제·AI·광고·분석 SDK 및 개발자 서버는 없습니다. 앱의 외부 동작인 WatchConnectivity, OS 공유/파일 저장, 지원 메일과 GitHub Pages도 구분해 설명합니다. Android의 Google Play services를 iOS 답변에 포함하지 않습니다.

## 이전 영상 검토 · 제출 대상에서 제외

- 원본 `ScreenRecording_09-27-2026 18-17-19_1.mp4`: 80.043515초, 1180×2556, HEVC/AAC, 78,107,634바이트. 원본을 변경하지 않았습니다. 개인 영상과 추출 프레임은 공개 저장소에 넣지 않습니다.
- 영상 전체 구간에서 1초 간격의 80개 프레임을 추출해 시각적으로 확인했습니다. 모든 프레임을 실시간 재생한 검사나 기기를 직접 조작한 시험은 아닙니다. 확인한 이미지에 오류 팝업·크래시·멈춤을 나타내는 정지 상태는 보이지 않았습니다. 오디오는 레벨 검사에서 최대 -91 dB로 사실상 무음입니다.
- 약 00:00~00:02: 홈 화면에서 앱 아이콘을 눌러 실행하는 장면.
- 약 00:06~00:08: 시급 10,320원을 확인하고 근무 시작.
- 약 00:14~00:16: 휴식 상태에서 수익 20원 유지. 약 00:17부터 재개 후 수익 증가.
- 약 00:21~00:25: 종료 확인, 39원 확정, 2P 적립, 잔액 19P→21P.
- 약 00:31~00:59: 상점 탐색, 정장 조끼 미리보기, 회전·확대·방 보기 및 보유 아이템 필터. 구매나 신규 장착 완료를 보여 준다고 설명하지 않습니다.
- 약 01:00~01:05: 월 합계 376원, 당일 종료 기록 39원 표시. 기록 편집 완료까지 보여 주지는 않습니다.
- 약 01:06~01:18: 기본 시급·시간 보상 규칙·알림 설정, 근무 기록 CSV의 시스템 저장 창. 파일 앱에서 실제 저장 파일을 다시 열지 않았으므로 내용/저장 완료까지 검증했다고 쓰지 않습니다.
- 약 01:19: 홈으로 복귀. 온보딩·Watch·위젯·앱 개인정보 본문·앱 빌드 번호·OS 버전 확인 화면은 포함되지 않았습니다. 영상에 없는 동작을 설명에 추가하거나 관련 검증을 완료 처리하지 않습니다.
- Apple은 분량을 지정하지 않았으므로 80초라는 이유로 더 길게 촬영하도록 요구하지 않습니다. 최신 OS 여부는 별도 충족이 필요한 명시 조건입니다.

**최신 OS 근거:** [Apple security releases](https://support.apple.com/en-us/100100), 2026-09-27 조회. iOS 27은 2026-09-14 출시이며 iPhone 11 이후 모델을 지원합니다. 첫 영상은 iOS 26.6.1 촬영으로 확인되어 제외했고, 사용자는 아래 새 영상을 iOS 27 업데이트 후 촬영했다고 확인했습니다.

## 이전 빌드 영상 검토 · 2026-09-27 19:38 촬영

- 제출 후보 원본 `ScreenRecording_09-27-2026 19-38-29_1.mp4`: 71.026667초, 1180×2556, HEVC/AAC, 72,432,393바이트. 원본은 변경하지 않았으며 개인 영상·추출 프레임을 저장소에 넣지 않습니다.
- 사용자 확인: **iPhone 16 / iOS 27 / TestFlight 1.0 (2)**. 영상 자체에는 설정의 앱 버전 1.0이 표시되지만 OS 버전이나 빌드 번호 (2)는 표시되지 않습니다. 기기·OS·빌드는 사용자 확인에 근거합니다.
- 전체 구간에서 1초 간격의 71개 프레임을 시각 검토했습니다. 실시간 전체 재생이나 기기를 직접 조작한 시험은 아닙니다. 확인한 장면에서 오류 팝업·비정상 종료는 보이지 않았습니다. 오디오 레벨은 평균 -59.6 dB / 최대 -21.5 dB이며, 음성 내용은 검증하지 않았습니다.
- 약 00:00~00:03: 홈 화면에서 앱 실행, 병아리와 방 표시.
- 약 00:05~00:06: 시급 10,320원 확인 후 근무 시작. 약 00:15~00:16 휴식 상태에서 일 합계 63원 유지, 약 00:17 재개 후 증가.
- 약 00:23~00:28: 근무 종료 확인과 3P 적립. 잔액 21P→24P, 일 합계 39원→86원. 신규 기록의 47원과 일 합계 증가분이 일치합니다.
- 약 00:29~00:51: 상점 탐색, 멜빵바지(900P) 미리보기, 모델 회전·확대·방 보기, 보유 아이템 필터. 잔액 부족으로 구매 버튼이 비활성화돼 있으며 실제 구매나 신규 장착을 시연했다고 표현하지 않습니다.
- 약 00:52~00:58: 월 합계 423원과 당일 두 기록 47원·39원 확인. 기록 편집은 시연하지 않았습니다.
- 약 00:59~01:08: 시급·보상 규칙·알림·CSV 내보내기 메뉴·도움말/개인정보 메뉴·앱 버전 1.0 표시. 새 영상에서는 CSV 저장 창이나 도움말/개인정보 본문을 열지 않았습니다.
- 약 01:09~01:10: 홈으로 복귀. 온보딩·Watch·위젯·계정·실제 결제 시연은 없습니다. 계정과 실제 결제는 앱에 없는 기능입니다.
- 사용자 확인에 따라 최신 OS의 실물 기기에서 앱 실행과 대표 사용 흐름을 보여 주는 자료로 준비합니다. 이번 영상으로 전체 기기·접근성·시스템 연동 시험을 완료 처리하지 않습니다. 최종 자료 수락 여부는 Apple 심사에서 결정됩니다.

## 최신 영상 검토 · 2026-09-27 20:50 전달

- 사용자 제공 파일 `KakaoTalk_Video_2026-09-27-20-50-33.mp4`: 85.165초, 884×1920, HEVC/AAC, 13,904,631바이트. 전달받은 파일은 변경하지 않았으며 영상·추출 이미지를 공개 저장소에 넣지 않습니다.
- 사용자는 설정 개편 후 정상 동작을 보고하며 새 영상을 전달했습니다. 약 01:15의 문의하기 화면에 **1.0 (4)**가 직접 표시됩니다. 기기/OS 설명은 앞서 확인한 iPhone 16 / iOS 27 환경을 따르며, 이번 영상에서 OS 설정 화면을 독립 확인한 것은 아닙니다.
- 전체 구간에서 1초 간격의 85개 프레임을 시각 검토했습니다. 전체 실시간 재생, 정량적 FPS 측정, 오디오 내용 검사 또는 직접 실물 조작 시험은 아닙니다. 확인한 장면에서 오류 팝업이나 비정상 종료는 보이지 않았습니다.
- 00:00~00:02: 홈 화면에서 앱 실행. 00:06~00:08: 시급 10,320원 확인 후 근무 시작. 00:18~00:20: 휴식 중 일 합계 116원 유지, 이후 재개해 증가.
- 00:28~00:31: 종료 확인·3P 적립, 잔액 24P→27P, 일 합계 86원→143원. 기록 화면의 새 근무 57원과 일 합계 증가분이 일치합니다.
- 00:32~00:51: 상점 탐색, 정장 조끼 미리보기, 회전·방 보기, 보유 아이템 필터. 잔액 부족에 따른 구매 비활성화가 보이며, 실제 구매나 신규 장착을 시연했다고 설명하지 않습니다.
- 00:52~00:58: 월 합계 480원, 당일 기록 57원·47원·39원. 이전 영상의 기록 두 건이 새 빌드에도 보이지만, 이것만으로 전체 업데이트·재시작 데이터 보존 시험을 완료 처리하지 않습니다.
- 00:59~01:16: 설정의 6개 메뉴와 근무 설정·꾸미기 보상·내 데이터·이용 안내·문의하기 상세 화면. 01:17~01:20: 앱 내 개인정보처리방침 본문. 약 01:24 홈 복귀.
- CSV 메뉴는 표시하지만 내보내기·파일 내용 검증은 시연하지 않습니다. 기록 편집·전체 초기화·온보딩·Watch·위젯을 시연했다고 주장하지 않습니다. 이 영상과 사용자 보고를 모든 기기·접근성·시스템 연동 검증 완료로 취급하지 않습니다.

## 실물 iPhone 녹화 순서

Apple의 필수 조건은 **실물 기기·최신 OS·앱 실행 장면·대표 사용 흐름**입니다. 아래 3~5분 길이는 작업 편의를 위한 권장이며 Apple이 지정한 분량이 아닙니다.

- TestFlight에서 제출 후보 **1.0 (4)**를 확인합니다. 기기 모델명과 설치된 iOS 버전을 기록하고, 설정 → 일반 → 소프트웨어 업데이트에서 최신 OS 여부를 확인합니다. 기기 일련번호나 Apple 계정을 영상에 담을 필요는 없습니다.
- 화면 녹화를 시작한 뒤 홈 화면에서 삐약뱅크 아이콘을 눌러 실행합니다. 앱 화면이 이미 열린 상태로 시작하지 않습니다.
- 첫 실행이면 시급 예시 `10000`을 입력하고 온보딩을 마칩니다. 이미 설정한 앱은 기존 상태로 진행하고 설정에서 시급을 보여 줍니다. 촬영을 위해 앱을 삭제하거나 기록을 초기화하지 않습니다.
- 홈에서 병아리를 누르거나 놀아주기를 실행합니다. 근무 시작 → 20~30초 진행 → 휴식 → 재개 → 20~30초 진행 → 종료 확인을 보여 줍니다. 홈의 예상 수익과 새 포인트 적립을 보여 줍니다.
- 기록에서 방금 종료한 예시 근무를 열고 근무/휴식 내역을 보여 줍니다. 예시 기록의 시급을 바꾸면 수익은 바뀌고 포인트는 늘지 않는 흐름도 확인할 수 있습니다.
- 꾸미기에서 아이템 미리보기, 회전·확대와 보유 아이템 장착을 보여 준 뒤 홈의 반영을 확인합니다. 이미 충분한 포인트가 있다면 구매도 보여 줍니다. 포인트가 부족하면 미리보기·보유 아이템으로 진행하고, 시계 변경이나 잔액 조작으로 구매를 연출하지 않습니다.
- 설정에서 시급·알림 선택·CSV 내보내기·이용 안내·개인정보 화면을 보여 줍니다. CSV는 예시 기록으로 기기의 파일 앱에 저장할 수 있습니다. 전체 초기화는 실행할 필요가 없습니다.
- iPhone 위젯이 설정돼 있으면 위젯 표시도 보여 줍니다. 실물 Watch가 있으면 연결과 시작/휴식/재개/종료를 별도 영상으로 추가할 수 있으나 이번 메시지가 별도의 Watch 영상까지 명시적으로 요구한 것은 아닙니다. 실제로 촬영·검증한 범위만 회신에 적습니다.
- 원본 화면 녹화를 유지합니다. 영상에 오류가 보이면 해당 오류를 기록하고 수정·재검증 후 제출 빌드와 영상을 일치시킵니다. 합성 영상이나 시뮬레이터를 실물 영상으로 제출하지 않습니다.

## 최신 영문 답변 · 1.0 (4)

아래 3,722자 문안을 Notes에 저장하고 같은 문안과 새 영상을 심사팀에 전송했습니다(잔여 278자). 회신 메시지 수 2개, 21:09 KST 회신 및 새 파일명·다운로드 표시를 확인했습니다.

```text
Hello App Review Team,

Here is the requested Guideline 2.1 information for PiyakBank 1.0 (4). This build improves room animation and organizes Settings into detail pages.

1. Physical-device recording
Attached: KakaoTalk_Video_2026-09-27-20-50-33.mp4 (85 seconds), recorded on a physical iPhone 16 running iOS 27 with TestFlight 1.0 (4).
It begins with app launch and shows work start, pause, resume, finish and point credit; item/room previews with rotation; work history; and the new Settings pages, including Help, Contact and Privacy. At about 01:15, Contact displays 1.0 (4). There are no account, public UGC or paid-content flows.

2. Purpose and audience
PiyakBank helps Korean-speaking users, including hourly/part-time workers, keep personal work and break records, view estimated earnings and decorate a chick's room with time-earned virtual points. The room encourages recordkeeping. No employer or organization membership is required.

3. Setup and access
No registration, login, credentials or sample files are required. On first launch, enter an hourly wage (e.g. 10000 KRW) and finish onboarding. Notification permission is optional.
Home: start, pause, resume and finish work. History (기록): inspect, add or edit records. Timer work earns 1 point per 6 seconds excluding breaks, capped at 4800 points per day. Wages and manually added/edited records do not increase points.
Decorate (꾸미기): preview items freely, equip owned items or spend earned points. Default items are owned. There are no point purchases, paid features, subscriptions or in-app purchases.
Settings (설정): Work Settings (근무 설정) contains wage/reminders; My Data (내 데이터) contains CSV exports and a reset with confirmation. Help (이용 안내), Contact (문의하기) and Privacy (개인정보 처리방침) are directly accessible from Settings. Contact includes email/copy options and the support website. Privacy includes the policy text and web link.
The optional Watch app needs a paired, reachable iPhone with onboarding complete. The iPhone/iPad widget's refresh timing is controlled by WidgetKit. The phone app works without a Watch.
There is no public UGC feed, messaging or user-to-user sharing service. Records are private local data. CSV export uses the system file exporter at the user's request. CSV import and in-app cloud synchronization are not supported.

4. Services and platforms
The iOS app has no third-party SDKs, developer backend, external data provider, authentication/payment service, ads/analytics or AI service. Core tracking/rendering run locally with Apple's SwiftUI, SwiftData and SceneKit. It uses UserNotifications for local reminders, WidgetKit/App Groups for the widget, WatchConnectivity for the paired Watch and the system file exporter for CSV.
Optional public support/privacy pages use GitHub Pages. Email support opens the user's mail app only on request.

5. Regional behavior
App Store availability is South Korea only. The interface is Korean and earnings use KRW. There are no regional content catalogs or feature switches. The point cap resets at midnight Asia/Seoul regardless of location; earnings/history dates follow the device's local calendar/time zone.

6. Regulated services and third-party content
PiyakBank is a personal tracker, not a bank or payment/payroll provider. It does not connect to financial accounts, accept deposits, lend, transfer or withdraw money. Earnings are simple user-input estimates excluding taxes and workplace-specific rules. Points have no cash value and cannot be redeemed or transferred.
The chick, room, items, previews and icons use the project's own SceneKit geometry. The app uses Apple system fonts/symbols and has no third-party content feeds or licensed media catalogs.

Thank you.
```

## 최신 App Store Connect 반영 · 1.0 (4)

1. 심사 버전의 빌드를 `39948079-bd9e-460a-b7ae-45fa4bac16f3` / **1.0 (4)**로 바꾸고 저장했습니다. 로그인 불필요, 기존 설명·스크린샷·지원 URL·개인정보 설정을 유지했습니다.
2. 새 영상을 심사 정보 첨부와 회신 양쪽에 업로드했습니다. 이전 영상과 실패한 임시 업로드가 최종 회신에 섞이지 않도록 정상 첨부가 있는 초안을 저장·다시 열어 확인했습니다. Notes 문안은 첨부 처리 후에도 일치했습니다.
3. 초기 업로드 실패 중 제공 영상이 다운로드 폴더에서 휴지통으로 이동한 것을 확인했습니다. 사용자가 파일을 복원한 후 작업 폴더의 사본을 사용했습니다. 사용자의 Chrome 전환 지시와 파일 접근 권한 설정 후 업로드를 마쳤습니다. 영상 자체를 수정하거나 다시 인코딩하지 않았습니다.
4. **21:09 KST**에 회신 전송을 완료했습니다. 화면의 메시지 수가 1개에서 2개로 늘었고 최신 영문 답변 및 `KakaoTalk_Video_2026-09-27-20-50-33.mp4` 첨부가 표시됐습니다.
5. ‘심사 업데이트’에서 지난 예약일(9월 26일)로 인한 출시 날짜 유효성 오류가 표시돼, 사용자 선택에 맞게 **자동으로 버전 출시**로 변경·저장했습니다. 과거 날짜가 붙은 예약 옵션은 선택하지 않습니다.
6. ‘심사 업데이트’ 후 **1.0 (4) / 심사 준비됨**을 확인하고 ‘앱 심사에 다시 제출’을 실행했습니다. **21:11 KST** 확인 시 제출 전체와 항목 모두 **심사 대기 중**입니다. 기존 제출 ID `619653b0-9aa4-4b2f-9972-0157e1b90097`을 사용합니다. 이 기록은 최종 승인이나 전체 기기 시험 완료를 의미하지 않습니다.

## 이전 App Store Connect 반영 기록 · 1.0 (2) / 2026-09-27 19:48

1. 새 영상의 대표 흐름과 사용자 확인 환경(iPhone 16 / iOS 27 / TestFlight 1.0 (2))을 반영했습니다.
2. 앱 심사 정보 첨부 파일에 새 MP4를 올려 처리 중 표시가 사라지고 파일명만 표시되는 상태를 확인했습니다. 첨부 처리 시 저장하지 않은 Notes가 이전 값으로 돌아가, 처리 완료 후 최종 문안을 다시 입력하고 저장했습니다. 저장 버튼 비활성화와 입력 내용을 확인했습니다.
3. 심사팀 회신에도 같은 MP4와 3,794자 문안을 넣고 **초안 저장**을 눌렀습니다. 19:48 KST 초안에 파일명·다운로드·초안 계속 작성·초안 삭제가 표시됩니다. 메시지 개수는 기존 Apple 메시지 1개이며 아직 회신하지 않았습니다.
4. 이 시점에는 회신 전송·재제출 전이었으며, 이후 사용자가 움직임·설정 개선을 요청했습니다. 현재 상태는 문서 첫머리를 따릅니다.
5. 출시 설정이 **2026-09-26 13:00 이후 승인 시 자동 출시**로 표시됩니다. 이전 수동 출시 계획과 달라 사용자가 자동 출시 유지 방향을 확인했고 현재 설정을 유지합니다.

개인 영상과 비공개 연락처는 공개 저장소에 넣지 않습니다. 이번 자료 보완은 전체 기기/접근성 검증 완료나 승인 보장이 아닙니다.

공식 절차: [Reply to App Review messages](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/reply-to-app-review-messages), [Manage a submission with unresolved issues](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/manage-a-submission-with-unresolved-issues).
