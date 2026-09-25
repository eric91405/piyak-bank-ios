# App Store 제출 자료

## 첫 출시 범위

첫 출시 지역은 **대한민국만**으로 사용자가 확정했습니다(2026-09-26). 무료 다운로드, 광고·계정·실제 결제 없음. 유료 기능은 이후 버전에서 별도 설계합니다. 현재 출시 후보에 StoreKit 테스트 상품이나 구매 복원 화면은 없습니다.

## App Store Connect 입력 현황 · 2026-09-26

- 사용자 결정: 대한민국만 무료 출시. TestFlight 정상 동작을 보고했으며 개별 기기·OS·업데이트 시험 범위는 미확인입니다.
- 서버 재조회 확인: 한국어 설명·프로모션·키워드·지원 URL·저작권·심사 메모, 로그인 불필요, 1.0 (2) 연결, 수동 출시 및 부제 저장.
- 연령 등급 저장 확인: 글로벌 4+, 대한민국 전체 이용가. 어린이 전용 카테고리는 선택하지 않았습니다.
- 심사 연락처는 사용자가 지정한 이름·이메일·전화번호를 Apple에 입력했습니다. 비공개 연락처는 공개 저장소에 기재하지 않습니다. 공개 지원 이메일은 기존 Gmail 주소입니다.
- 공개 개인정보처리방침 및 지원 URL의 HTTP 200 응답을 확인했습니다.
- 저장 확인: 기본 생산성·보조 라이프스타일, 타사 콘텐츠 없음, 무료 가격(기준 대한민국 KRW), 대한민국 1개 지역만 배포. 새로운 지역 자동 추가는 선택하지 않았습니다.
- Mac 및 Vision Pro 배포는 껐으며 저장 완료를 확인했습니다.
- 실제 스크린샷 등록 완료: iPhone 6.9인치 3장(6.5인치에 재사용), iPad 13인치 2장, Apple Watch Series 11 2장. 아래 파일 목록을 따릅니다.
- App Privacy: 개인정보처리방침 URL과 데이터 미수집 응답을 저장하고, 사용자가 답변 정확성·지침/관련 법 준수·변경 시 갱신에 대한 동의를 승인한 뒤 게시했습니다. Apple의 게시 완료 표시를 확인했습니다.
- 2026-09-26 **01:56 KST**에 **1.0 (2)** 심사 제출 완료. Apple이 “1개의 항목 제출됨”을 표시했고 제출 상세 화면에서 **심사 대기 중**을 확인했습니다.

[심사 제출 상세](https://appstoreconnect.apple.com/apps/6816129028/distribution/reviewsubmissions/details/619653b0-9aa4-4b2f-9972-0157e1b90097). 승인과 공개 출시는 아직이며 수동 출시 설정을 유지합니다. 제출 접수는 전체 기기 검증이나 심사 승인을 뜻하지 않습니다.

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

`docs/screenshots/`의 실제 시뮬레이터 캡처를 등록했습니다. 이미지 생성이나 합성 목업을 사용하지 않았습니다.

- iPhone 6.9인치: `iphone-home.jpg`, `iphone-decorate.jpg`, `iphone-item-preview.jpg` (1320×2868). 시간 보상 안내·상점·미리보기의 새 가격을 반영합니다.
- iPad 13인치: `ipad-home.jpg`, `ipad-decorate.jpg` (2064×2752). 2026-09-26 출시 소스 `de91f5d`의 Release 빌드로 갱신했습니다.
- Apple Watch Series 11: `watch-summary.png`, `watch-controls.png` (416×496). 같은 소스에서 연결된 iPhone의 진행 중 근무와 휴식·종료 버튼을 보여 줍니다. 왕복 제어 확인 범위는 [검증 기록](RELEASE_VALIDATION.md)을 따릅니다.

기존 `watch-character.png`는 연결 대기 상태이며 제출하지 않았습니다. `iphone-accessibility-dark.jpg`는 모델 개선 이전의 큰 글씨 QA 참고 자료입니다.

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

2026-09-26 Apple Developer Program **개인** 멤버십과 Xcode 개발자 팀을 확인했습니다. App Store Connect 앱 `6816129028`(SKU `piyakbank-ios`)을 생성하고, `de91f5d`의 **1.0 (2)** 빌드를 배포 서명·IPA 검증 후 TestFlight에 업로드했습니다. 내부 그룹 `내부 출시 검증`에는 계정 소유자만 추가했습니다. Apple 처리·설치 결과와 남은 화면·호환성·실기기 시험은 [출시 검증 기록](RELEASE_VALIDATION.md#현재-상태)을 기준으로 확인하세요. 심사 제출은 완료했으며 승인과 공개 출시는 아직입니다.

- **Apple Watch 스크린샷.** 416×496 수익·제어 화면 2장 등록 완료. 시뮬레이터 왕복 제어를 확인했으며 실물 통신·장착 이미지 시험은 별도입니다.
- **GitHub Pages 게시 확인.** `main`의 `/docs`를 게시 소스로 유지하고, iOS 개인정보·지원 URL이 실제로 열리는지 확인. Android 전용 정책과 구분하며 [게시 절차](PUBLISHING.md)를 참고
- Apple Developer 멤버십·번들 ID 3개·App Group·배포 서명 프로파일 구성 완료. 각 후속 IPA도 `scripts/verify_distribution_ipa.py`로 실제 서명 권한을 확인
- App Store Connect 앱 생성/연결·무료 가격·대한민국 단독·연령 등급 입력 완료. 개인정보 게시 동의·게시·심사 제출 완료
- 개인정보·지원 문서의 공개 URL 접속 및 지원 이메일 수신 가능 여부
- 정책의 문의 메일 보관 기간(처리 완료 후 1년 이내) 실제 운영 준수
- 실물 iPhone + Watch 왕복 제어/재연결/강제종료 복구/알림 확인
- TestFlight 빌드와 iPhone/iPad/Watch 스크린샷 연결 완료. 1.0 (2) 심사 대기 중

심사 승인 여부와 일정은 Apple이 결정합니다. 로컬 빌드·테스트 성공은 서명 업로드나 심사 승인 완료를 뜻하지 않습니다.

참고: [App Review](https://developer.apple.com/app-store/review/), [App Privacy](https://developer.apple.com/app-store/app-privacy-details/), [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/).
