<div align="center">

<!-- ▼▼▼ [이미지 1] 앱 아이콘 또는 홈 화면 대표 컷 (정사각 권장, 가로 200~300px) ▼▼▼ -->
<img width="1024" height="1024" alt="AppIcon_1024" src="https://github.com/user-attachments/assets/92586314-2957-4d39-bfba-bc75b3e5f950" />
<!-- ▲▲▲ -->

# 삐약뱅크 (PiyakBank)

### 내 시간이 돈이 되는 순간을 실시간으로 — 시급 적산 + 병아리 키우기

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20watchOS-FFD64D)]()
[![Swift](https://img.shields.io/badge/Swift-5.9-FF9E8A)]()
[![iOS](https://img.shields.io/badge/iOS-26.0+-5C4A1E)]()

**🎬 데모 영상:** https://youtu.be/I2SiUjNcYJs

[![데모 영상 보기](https://img.shields.io/badge/▶_데모_영상_보기-YouTube-FF0000?style=for-the-badge&logo=youtube)](https://youtu.be/I2SiUjNcYJs)

</div>

---

## 📖 한눈에 보기

**삐약뱅크**는 아르바이트 시급이 1초마다 쌓이는 것을 실시간으로 보여주고, 그렇게 번 포인트로 병아리 캐릭터 **삐약이**를 키우고 꾸미는 iOS·watchOS 앱입니다. "내가 지금 일해서 얼마를 벌고 있는가"라는 추상적인 감각을, 눈에 보이는 숫자와 키우는 재미로 바꿔주는 것이 목표입니다.

> Apple Watch에서 실시간으로 급여를 확인하고 제어할 수 있도록, iOS와 watchOS를 함께 설계한 프로젝트입니다.

---

## ✨ 핵심 기능

### 1. 실시간 시급 적산 (Real-time Accrual)
근무를 시작하면 설정한 시급이 **1초 단위로 적립**됩니다. 일시정지하면 적산도 함께 멈추며, 다시 재개할 수 있습니다.

<!-- ▼▼▼ [이미지 2] 홈 화면 — 적립 중 + 말풍선 ▼▼▼ -->
<img width="1179" height="2556" alt="856BD67F-60BF-4003-9CFD-BFCDE1DA6BDE_1_102_o" src="https://github.com/user-attachments/assets/896d1746-f00c-441a-b4c4-56ce956726cc" />
<!-- ▲▲▲ -->

### 2. 두 가지 적립 알림 (Smart Notifications)
- **마일스톤 알림** — 오늘 누적 금액이 1만 / 3만 / 5만 / 10만 / 15만 / 20만 원에 도달할 때
- **주기 알림** — 사용자가 설정한 간격(15 / 30 / 60분)마다 현재 누적 금액 보고

<!-- ▼▼▼ [이미지 3] 알림 배너가 뜬 화면 ▼▼▼ -->
<img width="1179" height="2556" alt="B3882BC9-ACE3-45A9-938F-1FD0B6547678_1_102_o" src="https://github.com/user-attachments/assets/c9aa2183-6b29-4a10-a299-8b3f2062a529" />
<!-- ▲▲▲ -->

### 3. 꾸미기 & 게이미피케이션 (Decoration)
모은 포인트로 방과 삐약이를 꾸밉니다. **배경 · 벽장식 · 가구 · 소품 · 러그 · 옷 · 모자 · 눈 · 목** 9개 카테고리에 걸쳐 **총 81종**의 아이템을 제공하며, 착용/해제가 자유롭습니다.

<!-- ▼▼▼ [이미지 4] 꾸미기 화면 — 아이템 그리드 + 착용된 삐약이 ▼▼▼ -->
<img width="1179" height="2556" alt="8CE7D263-81D1-4047-9C8D-8B4D8B255BA4_1_102_o" src="https://github.com/user-attachments/assets/c3eb1195-a1ea-4d94-a39b-361f8f2cd92c" />
<!-- ▲▲▲ -->

### 4. 온디바이스 AI 펫 (On-Device AI Chat)
삐약이를 탭하면 대화할 수 있습니다. Apple의 **온디바이스 Foundation Models**로 동작하여 네트워크 없이 작동하고, 급여 데이터가 기기를 벗어나지 않습니다. AI가 숫자를 지어내지 않도록 **Tool Calling**으로 실제 적립 원장을 직접 조회해 답변합니다.

<!-- ▼▼▼ [이미지 5] AI 채팅 화면 — "온디바이스 AI" 배지 + 대화 ▼▼▼ -->
<img width="1179" height="2556" alt="72DD1B0D-4B26-4095-B623-5F264920B6AE_1_102_o" src="https://github.com/user-attachments/assets/095aec8a-1d8f-4a6e-8341-05549af70ac8" />
<!-- ▲▲▲ -->

### 5. Apple Watch 연동 (watchOS Companion)
손목에서 실시간 적립 금액을 확인하고, 근무 시작·일시정지·정지를 제어할 수 있습니다. 폰과 **양방향 동기화**되며, 꾸미기에서 착용한 모습이 워치 캐릭터 화면에도 그대로 반영됩니다.

<!-- ▼▼▼ [이미지 6] 워치 — 적산 화면 / 캐릭터 동기화 화면 ▼▼▼ -->
<table>
<tr>
<td><img alt="워치 적산 화면" src="https://github.com/user-attachments/assets/5bd4e543-30dc-4222-94cb-b93225f8ba20" /></td>
<td><img alt="워치 캐릭터 동기화" src="https://github.com/user-attachments/assets/f1278884-b0f4-4e71-91d5-9831ad4d5622" /></td>
</tr>
</table>
<!-- ▲▲▲ -->

### 6. 기록 & 통계 (History & Stats)
월별 달력에서 일별 적립 내역을 확인하고, 설정 화면에서 통산 적립액·적립일수·최고 수입일 등의 통계를 볼 수 있습니다.

<!-- ▼▼▼ [이미지 7] 기록 달력 화면 ▼▼▼ -->
<img width="359" height="780" alt="717400EA-F908-419C-ACC4-51CCFA69B15C_4_5005_c" src="https://github.com/user-attachments/assets/8d6ab536-efb6-4491-a5b1-dbf4106deaa4" />

<!-- ▼▼▼ [이미지 8] 설정 화면 — 프로필 카드 + 통계 ▼▼▼ -->
<img width="359" height="780" alt="BEA6CB33-820B-442D-9626-7A82CC198B15_4_5005_c" src="https://github.com/user-attachments/assets/c534562b-4d44-4048-bda6-fbf075b91ac2" />
<!-- ▲▲▲ -->

---

## 🛠 기술 스택 (Tech Stack)

| 영역 | 사용 기술 |
|------|-----------|
| Language | Swift 5.9 |
| UI | SwiftUI |
| 영속성 | SwiftData |
| 알림 | UNUserNotificationCenter |
| 워치 연동 | WatchConnectivity |
| 인앱결제 | StoreKit 2 |
| 위젯 | WidgetKit |
| 온디바이스 AI | FoundationModels (Apple Intelligence) |

---

## 🏗 아키텍처 (Architecture)

세 개의 타깃이 `Shared` 코드를 공유하는 구조입니다.

```
PiyakBank/
├── App/            앱 진입점 · 라우팅 · 서비스 와이어링 · AI 엔진
├── Services/       세션 컨트롤러 · 알림 스케줄러 · 스토어 · 워치 싱크
├── Shared/         설계 토큰 · 경제(원장) 모델 · 공용 설정    ← 3타깃 공유
├── Views/          홈 · 꾸미기 · 기록 · 캐릭터 합성 뷰
├── Watch/          watchOS 앱 (적산 · 제어 · 캐릭터 페이지)
└── Widget/         WidgetKit 익스텐션
```

### 핵심 설계 결정
- **포인트 원장(Ledger) 방식** — 잔액을 단일 필드로 저장하지 않고, 모든 적립·구매·환불을 거래 기록(`PointTransaction`)으로 남긴 뒤 합산합니다. 자정 리셋 없이 날짜 필터만으로 "오늘 번 돈"을 정확히 계산합니다.
- **캐릭터 합성(Compositing)** — 공용 몸체 위에 옷·모자·안경·목 아이템을 동일 좌표계의 레이어로 겹쳐 그립니다. 의상은 통합 실루엣 방식으로 베이스를 교체합니다.
- **AI 환각 방지** — 잔액·기간 통계 질문은 LLM이 추측하지 않고 Tool Calling으로 SwiftData 원장을 직접 조회하여, 화면에 표시되는 금액과 항상 일치합니다.

---

## ⚙️ 빌드 방법 (Getting Started)

```bash
git clone https://github.com/eric91405/piyak-bank-ios.git
```

1. Xcode에서 `PiyakBank.xcodeproj` 열기
2. Scheme → Run → Options → **StoreKit Configuration**을 `Products.storekit`으로 지정
3. iOS 26.0+ 기기 또는 시뮬레이터에서 실행
4. (선택) 온디바이스 AI 채팅은 Apple Intelligence가 활성화된 실기기에서 동작하며, 미지원 환경에서는 자동으로 규칙 기반 응답으로 대체됩니다.

> **Requirements:** Xcode 16+, iOS 26.0+, watchOS 26.0+
> ⚠️ **라이트 모드 권장:** 이 앱은 말랑한 파스텔 톤에 맞춰 라이트 모드 기준으로 디자인되었습니다. 실기기에서 다크 모드로 실행하면 일부 색상이 의도와 다르게 보일 수 있으니, **설정 → 디스플레이에서 라이트 모드로 두고 사용하는 것을 추천**합니다.


---

## 👤 만든 사람

**김민서** · 한성대학교 iOS Programming
GitHub [@eric91405](https://github.com/eric91405)

<div align="center">

🐤 *오늘도 차곡차곡, 삐약!*

</div>
