# App Store 제출 자료

## 첫 출시 범위

무료 다운로드, 광고·계정·실제 결제 없음. 유료 기능은 이후 버전에서 별도 설계합니다. 현재 출시 후보에 StoreKit 테스트 상품이나 구매 복원 화면은 없습니다.

## 한국어 상품 정보 초안

- 이름: 삐약뱅크 - 근무 기록과 방 꾸미기
- 부제: 내 시간을 기록하고 작은 친구를 키워요
- 기본 언어: 한국어
- 권장 기본 카테고리: 생산성
- 보조 카테고리 후보: 라이프스타일
- 키워드: 근무,시급,알바,출퇴근,시간기록,급여계산,병아리,꾸미기,포인트,타이머
- 지원 이메일: eric91405@gmail.com
- 운영자: 김민서
- 개인정보 URL: `https://eric91405.github.io/piyak-bank-ios/privacy/`
- 지원 URL: `https://eric91405.github.io/piyak-bank-ios/support/`

두 주소는 `docs/` 폴더를 GitHub Pages로 게시하는 고정 주소입니다. 공개 경로를 유지하려면 게시 소스 브랜치와 permalink를 관리해야 합니다. 제출 전에 다음을 확인하세요.

1. 저장소 Settings → Pages → Source를 `Deploy from a branch`, 브랜치 `main`, 폴더 `/docs`로 유지([게시 절차](PUBLISHING.md))
2. 첫 배포 후 위 두 주소가 실제로 열리는지 확인 (반영까지 몇 분 걸립니다)
3. `docs/_config.yml`은 심사 메모·검증 기록을 Pages 웹사이트에서 제외합니다. 공개 GitHub 저장소에서는 해당 원본 파일을 볼 수 있습니다.

### 준비된 화면

`docs/screenshots/`에 실제 시뮬레이터 캡처가 있습니다. iPhone 6.9인치용 `iphone-home.jpg`, `iphone-decorate.jpg`는 1320×2868입니다. 홈의 시간 보상 안내와 상점·아이템 미리보기의 새 가격을 반영했습니다. Watch Series 11 46mm의 `watch-summary.png`, `watch-character.png`는 416×496이며 연결 대기 상태의 실제 화면입니다. iPad 13인치용 `ipad-home.jpg`(2064×2752)와 `iphone-accessibility-dark.jpg`는 모델 개선 이전의 레이아웃·큰 글씨 검증 참고용입니다. 제출 전에 최종 서명 빌드와 일치하는 iPad 화면을 갱신하고 Watch 연결 상태의 화면을 확인하세요.

### 설명

일하는 나에게, 작은 친구 하나.
삐약뱅크에서 일한 시간을 기록하고 삐약이의 작은 세상을 키워 보세요.

• 근무 시작·휴식·종료를 간편하게 기록해요.
• 홈에서 입력한 시급과 유급 시간으로 계산한 예상 수익과 보유 포인트를 확인해요.
• 시급과 별개로 타이머 근무 10분당 100P를 모아요. 휴식은 제외하며 하루 최대 4,800P예요.
• 81개의 옷, 모자, 가구와 소품으로 입체적인 방을 꾸며요.
• 달력에서 기록을 확인하고 빠뜨린 근무를 추가하거나 수정해요.
• 근무 기록과 포인트 원장을 CSV로 내보내요.
• 연결된 Apple Watch에서 근무를 제어하고, iPhone 위젯에서 예상 수익을 확인해요.
• 삐약이를 누르거나 ‘놀아주기’ 버튼으로 인사하고 장착한 가구와 함께 놀아요.

회원가입과 광고 없이 사용할 수 있습니다. 기록은 기기에 저장되며 개발자 서버로 전송하지 않습니다.

보상은 6초당 1P씩 계산해 근무를 마칠 때 확정합니다. 같은 날의 짧은 근무 시간도 합산하며 하루 한도는 한국 시간(KST) 자정에 새로 시작합니다. 한 근무에서 보상에 반영하는 측정 시간은 최대 24시간입니다. 기록을 직접 추가하거나 완료 기록을 수정해도 추가 포인트가 생기지 않으며, 완료 기록 삭제로 확정 보상이 없어지지 않습니다. 새로 적립한 근무 보상 4,800P마다 레벨이 오르고 아이템 구매로 레벨은 줄어들지 않습니다.

예상 수익은 세금·수당·사업장별 정산 규칙을 반영하지 않습니다. 포인트는 앱 꾸미기 전용 가상 포인트이며 현금 가치, 현금 전환, 송금 또는 인출 기능이 없습니다. 삐약뱅크는 실제 은행이나 급여 지급 서비스가 아닙니다.

iOS 17.0 이상. 워치 앱은 watchOS 10.0 이상 및 연결된 iPhone이 필요합니다. 위젯은 iPhone/iPad용이며 watchOS 컴플리케이션은 제공하지 않습니다. CSV는 열람용이며 가져오기 및 클라우드 동기화는 지원하지 않습니다.

### 심사 메모 (영문)

PiyakBank is a local work-time tracker with a virtual pet room. It is not a financial institution or a payroll/payment service. Estimated earnings are calculated solely from user-entered hourly wages and paid time. Virtual points have no monetary value and cannot be purchased, redeemed, transferred, or withdrawn. Version 1.0 is free and contains no in-app purchases, ads, or login.

To review: finish onboarding with an hourly wage, start the work timer, pause/resume, then finish the session. Timer-measured working time earns 1 point per 6 seconds (100 per 10 minutes), excluding pauses, independently of the hourly wage. The daily cap is 4,800 points, with days defined by midnight in Asia/Seoul. A session can contribute at most 24 hours of measured reward time; earnings tracking continues beyond reward limits. Manually added or edited records never generate extra points, and deleting a work record does not remove its already finalized reward. Duplicate or overlapping reward intervals are counted once. Level progression uses newly earned timer rewards, not wages, purchases, or migrated balances.

The Decorate tab allows previewing items without purchasing; default items are already owned. Non-default items cost 450–4,000 virtual points. Please use previews and the default items to review the room without waiting to earn points. On Home, tap the chick or the “놀아주기” (Play) button to greet it or trigger interactions with equipped furniture. Today's estimated earnings and the point balance are displayed on Home; dated work records are in History. Settings contains CSV export, local data reset, privacy policy, and support contact.

On upgrade from the earlier reward policy, existing balances are divided by 20 and rounded down, then limited to 0–4,800 points once. Owned items and work history remain available; old transactions remain in the point-ledger CSV with the legacy kind and are excluded from the current balance. Only time measured after the upgrade earns new rewards for a previously active session. This is an offline personal app: these rules do not verify real employment or prevent direct device-storage tampering.

Watch control requires a reachable paired iPhone and completion of onboarding on the phone. We wait for an acknowledgement from the iPhone. Widget figures are five-minute estimates and update timing is controlled by WidgetKit. No review account is required.

## App Privacy 응답 준비

현재 앱 코드에는 개발자 서버나 분석·광고·추적 SDK가 없습니다. 기기 내 처리만 하는 데이터는 Apple의 수집 정의와 구분해야 합니다. 이메일 지원은 사용자가 메일 앱에서 자발적으로 전송하며, 정책에는 문의 처리와 보관 기간을 기재했습니다.

App Store Connect의 최종 개인정보 응답은 실제 배포 버전·운영 방식과 일치하는지 확인 후 제출해야 합니다. 근무/시급 정보가 분석 도구나 오류 보고에 전송되도록 바꾸면 선언과 정책을 함께 수정해야 합니다.

## 제출 직전 운영자 확인

2026-09-21 현재 Apple Developer Program 미가입이며 Xcode에는 무료 Personal Team만 확인됐습니다. 배포 서명 Archive·TestFlight 업로드·심사 제출은 진행하지 않았습니다. 완료한 테스트와 남은 화면·호환성·실기기 시험은 [출시 검증 기록](RELEASE_VALIDATION.md#현재-상태)을 기준으로 확인하세요.

- **Apple Watch 스크린샷.** 416×496 수익·캐릭터 화면 2장을 준비했습니다. 제출 대상과 최종 서명 빌드의 화면·규격이 일치하는지 확인하세요. 실제 통신 시험은 별도로 필요합니다.
- **GitHub Pages 게시 확인.** `main`의 `/docs`를 게시 소스로 유지하고, iOS 개인정보·지원 URL이 실제로 열리는지 확인. Android 전용 정책과 구분하며 [게시 절차](PUBLISHING.md)를 참고
- Apple Developer 멤버십, 실제 번들 ID 3개, App Group 및 서명 프로파일
- App Store Connect 앱 생성/연결, 가격 무료, 판매 지역, 연령 등급 설문
- 개인정보·지원 문서의 공개 URL 접속 및 지원 이메일 수신 가능 여부
- 정책의 문의 메일 보관 기간(처리 완료 후 1년 이내) 실제 운영 준수
- 실물 iPhone + Watch 왕복 제어/재연결/강제종료 복구/알림 확인
- TestFlight 빌드와 필요한 iPhone/iPad 스크린샷, 최종 심사 제출

심사 승인 여부와 일정은 Apple이 결정합니다. 로컬 빌드·테스트 성공은 서명 업로드나 심사 승인 완료를 뜻하지 않습니다.

참고: [App Review](https://developer.apple.com/app-store/review/), [App Privacy](https://developer.apple.com/app-store/app-privacy-details/), [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/).
