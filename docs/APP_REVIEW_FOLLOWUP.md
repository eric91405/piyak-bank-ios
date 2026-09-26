# App Review 추가 정보 대응 · 2026-09-26

상태: **실물 기기 영상 대기. 답변 미전송·재제출 미진행.** 사용자 제공 기기는 **iPhone 16 / iOS 26.6.1**입니다. 설치 버전은 사용자 보고이며 최신 OS 여부·촬영 결과는 아직 확인하지 않았습니다.

제출: iOS 1.0 (2), ID `619653b0-9aa4-4b2f-9972-0157e1b90097`.
근거: 사용자가 제공한 App Store Connect 스크린샷 3장. Apple 메시지 시각은 2026-09-26 13:56이며, 상태는 해결되지 않은 문제 / 심사를 통과하지 못함입니다. 라이브 페이지를 재조회한 기록은 아닙니다.

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

## 실물 iPhone 녹화 순서

Apple의 필수 조건은 **실물 기기·최신 OS·앱 실행 장면·대표 사용 흐름**입니다. 아래 3~5분 길이는 작업 편의를 위한 권장이며 Apple이 지정한 분량이 아닙니다.

- TestFlight에서 제출된 **1.0 (2)**를 확인합니다. 기기 모델명과 설치된 iOS 버전을 기록하고, 설정 → 일반 → 소프트웨어 업데이트에서 최신 OS 여부를 확인합니다. 기기 일련번호나 Apple 계정을 영상에 담을 필요는 없습니다.
- 화면 녹화를 시작한 뒤 홈 화면에서 삐약뱅크 아이콘을 눌러 실행합니다. 앱 화면이 이미 열린 상태로 시작하지 않습니다.
- 첫 실행이면 시급 예시 `10000`을 입력하고 온보딩을 마칩니다. 이미 설정한 앱은 기존 상태로 진행하고 설정에서 시급을 보여 줍니다. 촬영을 위해 앱을 삭제하거나 기록을 초기화하지 않습니다.
- 홈에서 병아리를 누르거나 놀아주기를 실행합니다. 근무 시작 → 20~30초 진행 → 휴식 → 재개 → 20~30초 진행 → 종료 확인을 보여 줍니다. 홈의 예상 수익과 새 포인트 적립을 보여 줍니다.
- 기록에서 방금 종료한 예시 근무를 열고 근무/휴식 내역을 보여 줍니다. 예시 기록의 시급을 바꾸면 수익은 바뀌고 포인트는 늘지 않는 흐름도 확인할 수 있습니다.
- 꾸미기에서 아이템 미리보기, 회전·확대와 보유 아이템 장착을 보여 준 뒤 홈의 반영을 확인합니다. 이미 충분한 포인트가 있다면 구매도 보여 줍니다. 포인트가 부족하면 미리보기·보유 아이템으로 진행하고, 시계 변경이나 잔액 조작으로 구매를 연출하지 않습니다.
- 설정에서 시급·알림 선택·CSV 내보내기·이용 안내·개인정보 화면을 보여 줍니다. CSV는 예시 기록으로 기기의 파일 앱에 저장할 수 있습니다. 전체 초기화는 실행할 필요가 없습니다.
- iPhone 위젯이 설정돼 있으면 위젯 표시도 보여 줍니다. 실물 Watch가 있으면 연결과 시작/휴식/재개/종료를 별도 영상으로 추가할 수 있으나 이번 메시지가 별도의 Watch 영상까지 명시적으로 요구한 것은 아닙니다. 실제로 촬영·검증한 범위만 회신에 적습니다.
- 원본 화면 녹화를 유지합니다. 영상에 오류가 보이면 해당 오류를 기록하고 수정·재검증 후 제출 빌드와 영상을 일치시킵니다. 합성 영상이나 시뮬레이터를 실물 영상으로 제출하지 않습니다.

## 영문 답변 초안

**아래 `[VIDEO...]`, `[VERIFIED STEPS...]`는 아직 확인하지 않은 항목입니다. 실제 영상을 확인·첨부한 뒤 교체해야 합니다. 미촬영 상태에서 첨부/검증 완료라고 보내지 않습니다.** 같은 내용을 Notes에도 반영하되 업로드 결과에 맞게 영상 위치를 적습니다. 문안은 회신 입력란 4,000자보다 짧게 유지합니다.

```text
Hello App Review Team,

Thank you for your request regarding Guideline 2.1. Below is the information for PiyakBank, version 1.0 (2).

1. Physical-device recording
[VIDEO: verified attachment name or accessible recording link.]
Device: iPhone 16. OS: iOS 26.6.1. Build: 1.0 (2), installed through TestFlight.
The recording begins with app launch and demonstrates [VERIFIED STEPS: fill from the actual video].

2. Purpose and audience
PiyakBank is a personal work-time tracker for Korean-speaking users, including hourly and part-time workers. Users record work and breaks, view simple estimated earnings, and use time-earned virtual points to decorate a chick's room. The room provides a small visual incentive to keep personal records. It is available to individual consumers and does not require membership of an employer or organization.

3. Setup and access
There is no registration, login, account deletion flow, or required sample file. On first launch, enter an hourly wage (for example, 10000 KRW) and complete onboarding. Notification permission is optional.
Home: start work, pause, resume, and finish. After finishing, open History to inspect or edit the record. Timer-measured work earns 1 point per 6 seconds, excluding breaks, with a 4800-point daily cap. Wages do not affect points, and manually adding/editing records does not earn points.
Decorate: preview items without buying them, equip owned items, or spend earned points. Default items are already owned. Other items cost 450-4000 virtual points. Points cannot be bought with money; there are no paid features, subscriptions, or in-app purchases.
Settings: change the default wage, choose local notifications, export work records or the point ledger as CSV, and view help/privacy information. CSV import is not supported.
The optional Watch app requires a paired, reachable iPhone with onboarding completed. The iPhone/iPad widget shows an estimate; refresh timing is controlled by WidgetKit. The phone app works without a Watch.
There is no public user-content feed, messaging, or user-to-user content sharing service. Work records are private local data. CSV export uses the system file exporter at the user's request.

4. Services and platforms
The iOS app has no third-party SDKs, developer-operated backend, external data provider, authentication service, payment processor, advertising/analytics service, or AI service. Core tracking and room rendering work locally using Apple's SwiftUI, SwiftData, and SceneKit. It uses UserNotifications for local reminders, WidgetKit/App Groups for its widget, WatchConnectivity for the paired Watch, and the system file exporter for CSV.
Public support/privacy pages are hosted on GitHub Pages. Support email opens the user's mail app voluntarily. Neither is required for core functionality. The app has no in-app cloud synchronization.

5. Regional behavior
Initial App Store availability is South Korea only. The interface is Korean and earnings are displayed in KRW. There are no region-specific content catalogs or feature switches. The point cap resets at midnight Asia/Seoul regardless of location; earnings/history dates follow the device's local calendar/time zone.

6. Regulated services and third-party content
Despite the name PiyakBank, this is not a bank or a payment/payroll provider. It does not connect to financial accounts, accept deposits, lend money, or offer transfers or withdrawals. Earnings are simple estimates based on user input, excluding taxes and workplace-specific rules. Virtual points have no cash value and cannot be redeemed or transferred.
The chick, room, and items are generated from the project's own SceneKit geometry, including rendered preview images and app icons. The app uses Apple system fonts/symbols and does not distribute third-party content feeds or licensed media catalogs.

Thank you for reviewing the additional information.
```

## 영상 수령 후 진행

1. 모델·OS·1.0 (2) 일치, 앱 실행 장면, 주요 흐름 및 오류 유무를 실제 영상으로 확인합니다. 앱의 모든 기기/접근성 검증이 완료됐다고 쓰지 않습니다.
2. 영상을 App Review에 첨부하거나 Apple이 접근할 수 있는 제출 방식을 사용하고, 실제 첨부/접근 성공을 확인합니다. 공개 저장소에 개인 영상이나 연락처를 커밋하지 않습니다.
3. 위 초안의 영상 문단을 실제 관찰 내용으로 바꾸고, Apple 요청대로 회신과 Notes 양쪽에 반영합니다. 사용자에게 Apple 회신 전송 지시를 받은 뒤 보냅니다.
4. 필요한 정보 보완을 마치고 UI의 해결 절차를 따릅니다. 메타데이터 문제는 동일 빌드로 재제출할 수 있지만, 영상에서 앱 오류가 발견되면 수정 빌드를 먼저 검증합니다. 지금은 새 빌드 필요 여부나 승인 가능성을 확정하지 않습니다.

공식 절차: [Reply to App Review messages](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/reply-to-app-review-messages), [Manage a submission with unresolved issues](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/manage-a-submission-with-unresolved-issues).
