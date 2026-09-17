# App Store 제출 자료

## 첫 출시 범위

무료 다운로드, 광고·계정·실제 결제 없음. 유료 기능은 이후 버전에서 별도 설계합니다. 현재 배포본에 StoreKit 테스트 상품이나 구매 복원 화면은 없습니다.

## 한국어 상품 정보 초안

- 이름: 삐약뱅크 - 근무 기록과 방 꾸미기
- 부제: 내 시간을 기록하고 작은 친구를 키워요
- 기본 언어: 한국어
- 권장 기본 카테고리: 생산성
- 보조 카테고리 후보: 라이프스타일
- 키워드: 근무,시급,알바,출퇴근,시간기록,급여계산,병아리,꾸미기,포인트,타이머
- 지원 이메일: eric91405@gmail.com
- 운영자: 김민서
- 개인정보 URL: [공개 개인정보처리방침](https://github.com/eric91405/piyak-bank-ios/blob/codex/app-store-launch/docs/PRIVACY.md)
- 지원 URL: [공개 지원 안내](https://github.com/eric91405/piyak-bank-ios/blob/codex/app-store-launch/docs/SUPPORT.md)

위 URL은 출시 후보 브랜치에서 접속 확인한 주소입니다. PR을 병합한 뒤 제출할 때는 `blob/main/docs/PRIVACY.md`, `blob/main/docs/SUPPORT.md` 주소로 바꾸고 최종 접속을 확인하세요.

### 준비된 화면

`docs/screenshots/`에 실제 시뮬레이터 캡처가 있습니다. iPhone 6.9인치용 `iphone-home.jpg`, `iphone-decorate.jpg`는 1320×2868이고, iPad 13인치용 `ipad-home.jpg`는 2064×2752입니다. `iphone-accessibility-dark.jpg`는 큰 글씨 검증 참고용입니다. 제출 시 최종 서명 빌드와 화면이 같은지 확인하고 Watch 실기기 화면도 추가하세요.

### 설명

일하는 나에게, 작은 친구 하나.
삐약뱅크에서 일한 시간을 기록하고 삐약이의 작은 세상을 키워 보세요.

• 근무 시작·휴식·종료를 간편하게 기록해요.
• 입력한 시급과 유급 시간으로 예상 수익을 확인해요.
• 근무를 마치면 꾸미기 포인트를 받아요.
• 81개의 옷, 모자, 가구와 소품으로 입체적인 방을 꾸며요.
• 달력에서 기록을 확인하고 빠뜨린 근무를 추가하거나 수정해요.
• 근무 기록과 포인트 원장을 CSV로 내보내요.
• 연결된 Apple Watch에서 근무를 제어하고, iPhone 위젯에서 예상 수익을 확인해요.
• 삐약이에게 오늘·어제·이번 주·지난주·이번 달·지난달의 예상 수익과 보유 포인트를 물어보세요.

회원가입과 광고 없이 사용할 수 있습니다. 기록은 기기에 저장되며 개발자 서버로 전송하지 않습니다. iOS 26 이상 지원 환경에서는 Apple Intelligence의 기기 내 AI로 일상 대화도 나눌 수 있습니다. 그 외 기기에서는 기본 응답을 제공합니다.

예상 수익은 세금·수당·사업장별 정산 규칙을 반영하지 않습니다. 포인트는 앱 꾸미기 전용 가상 포인트이며 현금 가치, 현금 전환, 송금 또는 인출 기능이 없습니다. 삐약뱅크는 실제 은행이나 급여 지급 서비스가 아닙니다.

iOS 17.0 이상. 워치 앱은 watchOS 10.0 이상 및 연결된 iPhone이 필요합니다. 위젯은 iPhone/iPad용이며 watchOS 컴플리케이션은 제공하지 않습니다. CSV는 열람용이며 가져오기 및 클라우드 동기화는 지원하지 않습니다.

### 심사 메모 (영문)

PiyakBank is a local work-time tracker with a virtual pet room. It is not a financial institution or a payroll/payment service. Estimated earnings are calculated solely from user-entered hourly wages and paid time. Virtual points have no monetary value and cannot be purchased, redeemed, transferred, or withdrawn. Version 1.0 is free and contains no in-app purchases, ads, or login.

To review: finish onboarding with an hourly wage, tap the yellow start button, pause/resume, then finish the session. Completed earnings award virtual points. The History tab allows manually adding a past non-overlapping work record (e.g. one hour at KRW 50,000) to try the shop without waiting. The Decorate tab includes item previews and purchase confirmation using virtual points only. Settings contains CSV export, local data reset, privacy policy, and support contact.

Watch control requires a reachable paired iPhone and completion of onboarding on the phone. We wait for an acknowledgement from the iPhone. Widget figures are five-minute estimates and update timing is controlled by WidgetKit. Foundation Models is optional and used only for local small talk; deterministic record answers and all other core features work without Apple Intelligence. No review account is required.

## App Privacy 응답 준비

현재 앱 코드에는 개발자 서버, 분석·광고·추적 SDK 또는 외부 AI 전송이 없습니다. 기기 내 처리만 하는 데이터는 Apple의 수집 정의와 구분해야 합니다. 이메일 지원은 사용자가 메일 앱에서 자발적으로 전송하며, 정책에는 문의 처리와 보관 기간을 기재했습니다.

App Store Connect의 최종 개인정보 응답은 실제 배포 버전·운영 방식과 일치하는지 확인 후 제출해야 합니다. 근무/시급 정보가 분석 도구나 오류 보고에 전송되도록 바꾸면 선언과 정책을 함께 수정해야 합니다.

## 제출 직전 운영자 확인

- Apple Developer 멤버십, 실제 번들 ID 3개, App Group 및 서명 프로파일
- App Store Connect 앱 생성/연결, 가격 무료, 판매 지역, 연령 등급 설문
- 개인정보·지원 문서의 공개 URL 접속 및 지원 이메일 수신 가능 여부
- 정책의 문의 메일 보관 기간(처리 완료 후 1년 이내) 실제 운영 준수
- 실물 iPhone + Watch 왕복 제어/재연결/강제종료 복구/알림 확인
- TestFlight 빌드와 필요한 iPhone/iPad 스크린샷, 최종 심사 제출

심사 승인 여부와 일정은 Apple이 결정합니다. 로컬 빌드·테스트 성공은 서명 업로드나 심사 승인 완료를 뜻하지 않습니다.

참고: [App Review](https://developer.apple.com/app-store/review/), [App Privacy](https://developer.apple.com/app-store/app-privacy-details/), [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/).
