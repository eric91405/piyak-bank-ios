# 인수인계 — 출시 전 수정·개선 작업

## 인수 상태 (2026-09-21)

아래 패치 2개는 이미 `94801b9`, `011f809`로 적용되어 있습니다. **`git am`을 다시 실행하지 마세요.** 후속 작업에서는 구조·캐시·리소스 정리를 유지하고 저장소 이전, 알림 재시도, 워치 이미지 복구를 보완했습니다. 최신 결과와 남은 실기기 검증은 [출시 검증 기록](docs/RELEASE_VALIDATION.md)에 기록합니다.

GitHub Pages는 `main` 병합 전에도 `codex/app-store-launch`의 `/docs`를 소스로 게시할 수 있습니다. [게시 절차](docs/PUBLISHING.md)를 따릅니다. 네이티브 Xcode 테스트 타깃 추가는 개발 편의 개선이며 App Store 제출 필수 조건은 아닙니다. 기존 Swift Package 테스트와 CI를 유지합니다. 아래 기능 추가 목록은 별도 로드맵이며 이번 안정화 범위에 포함되지 않습니다.

---

## 최초 인수 메모 (기록용)

claude.ai에서 레포 전체를 리뷰하고 정리한 결과다. 이 문서는 일회성 작업 지시이며, 끝나면 지워도 된다. 항구적인 프로젝트 규칙은 `CLAUDE.md`에 있다.

## 배경

`main`(c70a8be, 2026-06-14)은 학교 과제 제출본. `codex/app-store-launch`(5784338, 2026-09-17, PR #1)는 codex로 재작성한 무료 출시 후보다. StoreKit 인앱결제와 FoundationModels AI 채팅을 제거하고, 2D SVG를 코드 생성 SceneKit 3D로 교체했으며, 시급과 꾸미기 포인트를 분리하고 배포 타깃을 iOS 26.5에서 17.0으로 낮췄다.

## 이미 적용된 것 — `piyakbank-fixes.patch`의 커밋 2개

**컴파일 검증이 안 된 상태다.** 작성 환경에 Swift 툴체인이 없었다. 첫 작업은 이 패치를 적용하고 빌드를 통과시키는 것.

```sh
git checkout codex/app-store-launch
git am < piyakbank-fixes.patch
swift test --jobs 1
python3 scripts/check_release_assets.py
xcodebuild -project PiyakBank.xcodeproj -scheme PiyakBank -configuration Debug \
  -jobs 1 -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/PiyakBank CODE_SIGNING_ALLOWED=NO build
```

커밋 1 — 미사용 SVG 130개 삭제(코드 참조 0곳 확인, 앱 6.0M→5.1M, 워치 1.1M→524K), `docs/`를 GitHub Pages로 게시하는 설정 추가, 개인정보·지원 URL을 브랜치 blob 링크에서 Pages 고정 주소로 교체.

커밋 2 — 코드 9건:

1. `WorkSession.decodedSegments()`에 `@Transient` 캐시. 저장 blob을 키로 써서 롤백 시 자동 무효화
2. `HistoryView` 월 합계를 해당 월과 겹치는 기록으로 한정
3. `HomeView`에 KST 안내. 기기 시간대가 KST가 아니면 한도 초기화 시각을 기기 시각으로 환산해 표시
4. `WatchSync` 초상화 PNG를 상태 페이로드에서 분리. 착용 변경 시에만 `transferUserInfo`로 전송, 워치는 직전 초상화 유지
5. `NotificationScheduler` 문구를 단정형에서 조건형으로, 계획 미변경 시 재예약 생략
6. SwiftData 스토어를 App Group으로 이전 (복사 방식 + 실패 시 폴백)
7. `CharacterComposite`를 VoiceOver 요소로 노출, 착용 요약 레이블과 놀아주기 액션
8. `PB.C.coral` → `PB.C.accent` 이름 정정 (실제 값이 보라색, 8곳)
9. 알림 탭을 `UIApplication.open` 대신 `AppRouter` 직접 호출로

### 빌드 후 확인할 것

**6번이 가장 위험하다.** 기존 데이터가 있는 기기에 덮어 설치해서 기록·잔액·보유/착용 아이템이 보존되는지, 재실행 시 잔액 전환이 반복되지 않는지, App Group 컨테이너에 `PiyakBank.store`가 생겼는지 확인. 유실 경로가 없도록 복사+폴백으로 짰지만 검증 없이 출시하면 안 된다.

나머지: 워치 착용 변경 반영과 상태만 바뀔 때 캐릭터 유지(4), 포그라운드 재진입 시 알림 주기 유지(5), VoiceOver 방 설명과 두 번 탭 동작(7), 시간대를 KST 외로 바꿨을 때 안내 노출(3).

## 남은 작업 — 출시 블로커

- **Apple Watch 스크린샷.** watchOS 앱을 포함해 제출하면 App Store Connect가 별도로 요구한다. `docs/screenshots/`에 iPhone·iPad만 있다. 워치 시뮬레이터에서 적산 화면과 캐릭터 화면을 캡처해 추가할 것.
- **Xcode 테스트 타깃 추가.** 현재 네이티브 타깃 3개뿐이라 `swift test`로만 검증되고 ⌘U가 안 된다. File → New → Target → Unit Testing Bundle. 파일 시스템 동기화 그룹이라 `Tests/`가 자동으로 붙는다.
- **GitHub Pages 게시.** Settings → Pages → `main` 브랜치 `/docs`. 게시 후 `https://eric91405.github.io/piyak-bank-ios/privacy/`와 `/support/`가 열리는지 확인.
- 서명 Archive, TestFlight 업로드, 실물 iPhone+Watch 왕복 제어·재연결·알림·위젯 갱신 확인. 이건 사람 손과 Apple 계정이 필요하다.

## 남은 작업 — 기능 추가

우선순위 순. 앞의 셋은 v1에 넣을 만한 크기이고, 다중 알바부터는 스키마가 바뀌므로 1.1로 미루는 편이 낫다. **한 번에 하나씩, 각각 빌드를 통과시킨 뒤 다음으로 넘어갈 것.**

1. **Live Activity / 다이나믹 아일랜드.** 앱의 핵심 가치가 실시간 적산인데 잠금화면에는 5분 단위 추정 위젯뿐이다. `ActivityAttributes` 정의, 위젯 타깃을 `WidgetBundle`로 개편, `Info.plist`에 `NSSupportsLiveActivities`, `SessionController`의 start/pause/resume/stop에 수명주기 연결. `SessionSnapshot`이 이미 있어 데이터는 준비돼 있다.
2. **백업·복원.** CSV 내보내기는 있는데 가져오기가 없어 기기를 바꾸면 전부 소실된다. CloudKit private DB 동기화가 정석이고, 최소한 JSON 백업·복원이라도 필요하다. 개인정보 처리방침과 App Privacy 응답을 함께 수정해야 한다.
3. **watchOS 컴플리케이션.** 워치 앱이 있는데 문자판 컴플리케이션이 없다. 위젯 타깃 이름이 `PiyakComplication`이지만 실제로는 iOS 위젯이다.
4. **다중 알바.** 기본 시급이 하나뿐이라 근무 기록에 어디서 일했는지가 남지 않는다. 직장 이름 + 시급 프리셋. SwiftData 스키마 변경과 마이그레이션 필요.
5. **주휴수당 예상.** 주 15시간 이상 기준. 법적 단정이 아니라 "예상"으로 표시해야 한다. 야간·연장 가산도 같은 맥락.
6. **도감·목표·업적.** 아이템 전체가 76,750P인데 하루 한도가 4,800P라 8시간 근무 16일이면 다 산다. 그 뒤 포인트를 모을 이유가 없다.
7. **영어 로컬라이즈.** 현재 `.environment(\.locale, ko_KR)` 강제에 통화도 하드코딩. String Catalog로 빼는 작업은 지금이 가장 싸다.
