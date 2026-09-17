# 출시 개선 검증 기록

검증일: 2026-09-17. 기준: 기존 main `c70a8be`에서 개선한 출시 후보.

## 완료한 구현

- 동일 계산기를 iOS/Watch/Widget에서 사용, 휴식 제외, 자정 분할과 원 단위 반올림 손실 수정
- 근무/포인트 정산 한 번 저장, 실패 시 UI 모델까지 복원, SwiftData 기준 세션 복구
- 재실행 가능한 워치 명령 차단, 시급 동기화, 응답 확인, 오프라인 예약 명령 제거
- 무료 81개 포인트 아이템, 기존 보유 내역 보존, StoreKit 경로 제거
- SceneKit 입체 방·병아리·아이템, 새 아이콘과 동일 모델에서 만든 미리보기
- 근무 기록 추가/수정/삭제, CSV 내보내기, 로컬 초기화
- 시급/알림 설정 유지, 알림 동의 선택화, 예약 경쟁 상태 제거
- 안내/지원/개인정보 문서, 타깃별 PrivacyInfo, URL scheme
- 스크롤 가능한 화면과 Dynamic Type, 다크 모드 색상, Reduce Motion 대응
- 기기 내 대화의 수익 조회를 결정적 코드로 분리, 취소/중복 전송 처리

## 검증 명령

```sh
swift test --scratch-path /tmp/piyak-core-tests
python3 scripts/check_release_assets.py
xcodebuild -project PiyakBank.xcodeproj -scheme PiyakBank -configuration Debug -jobs 2 -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/piyak-bank-release-work CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PiyakBank.xcodeproj -scheme PiyakBank -configuration Release -jobs 2 -destination 'generic/platform=iOS' -derivedDataPath /tmp/piyak-bank-release-work-device CODE_SIGNING_ALLOWED=NO build
```

## 자동 검증 결과

- **Swift Testing 20개 통과.** 실제 공통 계산기, SessionController, SwiftData 저장소를 대상으로 실행했습니다. XCTest의 별도 0개 출력과 구분합니다.
- 정수 시급, 휴식, 자정 분할, DST, 1,000개 소수 밀리초 구간의 금액 보존, 예전 스냅샷 호환성을 검증했습니다.
- 강제 저장 실패 시 정산·구매·장착·기록 수정·삭제·초기화의 원장과 화면 모델 복원을 확인했습니다.
- 근무 상태 복구, 중복/만료/다른 세션 워치 명령 차단, 설정 유지, 기존 정산 보정의 재실행 안전성을 확인했습니다.
- 리소스 검사 통과: 81개 고유 아이템 미리보기, iOS/Watch 1024px 불투명 아이콘, 3개 개인정보 매니페스트, URL scheme, StoreKit 테스트 설정 제거.
- **Debug 시뮬레이터 및 Release 기기 대상 빌드 성공.** 앱·동반 Watch 앱·위젯이 모두 포함됩니다. 서명은 비활성화한 검증 빌드입니다.
- Release 산출물에서 iOS 17.0 / watchOS 10.0 최소 버전과 매니페스트 포함을 확인했습니다. FoundationModels는 weak link이므로 이전 OS에서 프레임워크의 존재를 강제하지 않습니다.
- AppIntents를 사용하지 않아 나오는 메타데이터 추출 생략 경고 외 빌드 오류는 없습니다.

## 직접 확인한 동작

- iPhone 17 / iOS 26.5: 온보딩, 시급 입력, 근무 시작·휴식·재개·종료, 164원/164P 정산, 기록 표시, 상점 미리보기 및 포인트 부족 시 구매 차단.
- iPhone 17 Pro Max: 다크 모드와 접근성 큰 글씨에서 홈 화면·근무 버튼·기록의 날짜 선택기 확인. 최종 밝은 홈과 꾸미기 화면 캡처.
- iPad Pro 13인치(M5): 온보딩 및 최종 2열 홈 화면, 대기 상태에서의 입체 렌더링 확인.
- 입체 장면은 대기·꾸미기에서 정지하고, 화면이 활성화된 근무 중에만 24fps로 움직입니다. Reduce Motion에서는 정지합니다.

[실제 화면 캡처](screenshots/): iPhone 1320×2868, iPad 2064×2752. 원본 시뮬레이터 화면을 크기 변경 없이 JPEG로 내보냈으며 합성 목업이 아닙니다. 접근성 다크 모드 이미지는 QA 참고용입니다.

발열을 줄이기 위해 마지막 검증은 빌드 작업 수를 2개로 제한하고, 빌드 중에는 시뮬레이터를 끄며 화면 확인은 한 기기씩 수행했습니다.

## 제출 전 남은 검증

- 이 환경에는 유효한 코드 서명 인증서가 없고, 등록된 실물 iPhone/Watch는 연결되지 않았습니다. **서명 Archive, TestFlight 업로드, App Store 심사 제출은 수행하지 않았습니다.**
- 물리 기기 Watch 왕복 제어·재연결·백그라운드 통신, 실제 알림 수신, 위젯의 시스템 갱신 시점, 실기기 배터리/메모리 확인이 필요합니다. 통신 명령의 단위 테스트와 빌드 성공만으로 이를 대체하지 않습니다.
- iOS 17 / watchOS 10 런타임은 설치되어 있지 않습니다. 최소 버전 빌드는 통과했지만 해당 OS에서의 실행은 미검증입니다.
- 기존 SwiftData 필드와 아이템 ID는 보존했으나, 사용 중인 실데이터 사본을 이용한 버전 업그레이드 검증도 필요합니다.
- 지원 환경에서 Apple Intelligence 일상 대화, 실제 VoiceOver 사용, 접근성 최대 글씨와 가로 화면의 전체 흐름은 실기기에서 추가 확인해야 합니다.

제출 자료와 운영자 설정은 [APP_STORE.md](APP_STORE.md)를 참고하세요. 로컬 검증 통과가 Apple 심사 승인을 의미하지는 않습니다.
