# SwiftUI Localization (Eng -> Kor) Skill Guide

이 문서는 Figlog 프로젝트 등에서 영어를 한국어로 번역할 때 (String Catalogs `.xcstrings` 사용) 주의해야 할 점과, 팝업(Popover/Sheet) 화면에서 번역이 누락되는 문제를 해결하는 **"스킬(Skill)"**을 정리한 가이드입니다.

## 1. Localizable.xcstrings 수동 번역 추가 방법
Xcode 15부터 도입된 String Catalogs (`.xcstrings`)는 JSON 형태를 띠고 있습니다. 만약 AI(또는 스크립트)를 통해 외부에서 번역을 수동으로 추가한다면 아래 구조를 따르세요.

```json
    "Message..." : {
      "localizations" : {
        "ko" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "메시지 입력..."
          }
        }
      }
    }
```
> [!IMPORTANT]
> - `Text("\(party.name) Chat")` 처럼 변수가 포함된 문자열(String Interpolation)의 경우, Xcode는 기본적으로 `"%@ Chat"` 이라는 Key를 생성합니다.
> - `.xcstrings` 내부에도 `"%@ Chat"` 이라는 키 값으로 번역(`"%@ 채팅"`)을 추가해야 정상적으로 매핑됩니다.

## 2. 팝업 창(Popover / Sheet) 번역 누락 해결 방법 (가장 중요)

### 🚨 문제 원인
SwiftUI에서 `.popover`, `.sheet`, `.fullScreenCover` 등으로 새로운 창을 띄우면, 부모 창(Main View)에 적용된 환경 변수(`.environment(\.locale)`)가 **자식 창으로 자동 상속되지 않습니다.** 
이로 인해 앱 전체가 한국어로 잘 나오더라도, 팝업 창 안의 내용만 시스템 기본 언어(영어 등)로 노출되는 현상이 발생합니다.

### ✅ 해결 방법
팝업 뷰를 호출하는 부분에서 명시적으로 `.environment(\.locale, ...)`를 다시 주입해주어야 합니다.

**[잘못된 예시 - 번역 안 됨]**
```swift
.popover(item: $showingChatForParty) { party in
    ChatView(party: party)
}
```

**[올바른 예시 - 번역 정상 적용 (정석)]**
```swift
@AppStorage("appLanguage") private var appLanguage = "en" // 언어 설정 불러오기

// ...

.popover(item: $showingChatForParty) { party in
    ChatView(party: party)
        // 팝업 창 내부에도 앱 언어 설정을 명시적으로 주입 (필수!)
        .environment(\.locale, Locale(identifier: appLanguage))
}
```

## 3. 적용 후 주의사항 (캐시 삭제)
외부 스크립트나 터미널을 통해 `Localizable.xcstrings`를 수정했다면, Xcode가 변경 사항을 감지하지 못해 이전 번역을 보여줄 수 있습니다.
반드시 **Product > Clean Build Folder (`Cmd + Shift + K`)**를 실행하여 캐시를 비운 후 다시 빌드(`Cmd + R`)해야 완벽하게 적용됩니다.
