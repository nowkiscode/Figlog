# Figlog

> **Figma에서의 실제 작업 시간을 스마트하게 기록하고 공유하는 크로스 플랫폼 앱**
>
> Figlog는 Figma 창이 활성화되어 있고 사용자가 실제로 조작하고 있는 시간을 자동으로 감지하여 기록하는 생산성 도구입니다. 
> macOS 전용 네이티브 메뉴바 앱과 Windows 데스크톱 앱을 모두 지원하며, Firebase Firestore 연동을 통해 동료들과 실시간으로 작업 상태를 공유할 수 있습니다.

---

## 📥 설치 방법 (Installation)

### macOS (Universal Binary)
#### [👉 Figlog macOS 최신 버전 다운로드 (Download) 👈](https://github.com/nowkiscode/Figlog/releases/tag/Figlog-release)

1. 위의 **다운로드 링크**를 클릭하여 설치 파일을 다운로드합니다.
2. 다운로드된 `Figlog.app` 파일을 **응용프로그램(Applications)** 폴더로 드래그 앤 드롭합니다.
3. 앱 실행 시 macOS 보안 경고 팝업이 뜨는 경우:
   - 시스템 설정 -> 개인정보 보호 및 보안 -> 밑으로 스크롤하여 **'그래도 열기'** 버튼을 클릭합니다.
4. *최초 실행 시 Figma의 활성화 여부를 감지하기 위해 **손쉬운 사용(Accessibility)** 권한 허용이 필요합니다.*
5. 친구에게 배포 및 로컬 빌드 시 발생하는 Ad-hoc 서명/Quarantine 해제 방법은 [xcode_ad_hoc_build_guide.md](file:///Users/nowk/Documents/Figlog/xcode_ad_hoc_build_guide.md)를 참고하세요.

### Windows (C# / WinUI 3)
* Windows PC에서는 가벼운 REST API와 Win32 API를 사용해 빌드된 네이티브 클라이언트 앱을 지원합니다.
* `FiglogWindows` 폴더의 C# 프로젝트를 빌드하여 단일 `.exe` 실행 파일로 사용할 수 있습니다.

---

## ✨ 주요 기능 (Key Features)

### 1. 🧠 스마트 포커스 트래킹 (Smart Focus Tracking)
* **진짜 집중 시간만 기록:** Figma가 활성 창일 때 작동하며, 마우스 움직임과 키보드 입력이 멈수면 자동으로 '자리비움(Idle)' 상태로 전환하여 측정을 일시정지합니다.
* **유예 시간 (Grace Period):** 다른 앱을 잠시 조회하거나 메신저 답장을 보낼 때 세션이 끊기지 않도록 사용자 정의 유예 시간을 제공합니다.
* **스마트 병합:** 너무 짧게 끊어진 세션들은 타임라인의 가독성을 위해 자동으로 병합하여 렌더링합니다.

### 2. 👥 실시간 파티 공유 시스템 (Real-time Party System)
* **실시간 상태 연동:** Firebase Firestore 연동을 통해 나의 상태(`Figma 집중 중`, `Figma 대기 중`, `자리비움`, `오프라인`)와 오늘 누적 집중 시간을 동료들과 실시간 공유합니다.
* **파티 랭킹 (Party Ranking):** 파티 내에서 오늘 누가 더 오래 작업했는지 비교하고 순위를 확인할 수 있습니다.
* **파티 채팅 (Party Chat):** 파티 멤버들과 실시간으로 소통할 수 있는 채팅 기능이 지원되며, 알림 켜기/끄기를 설정할 수 있습니다. (데이터 최적화를 위해 메시지는 15일 경과 후 자동 삭제됩니다.)
* **멤버 히스토리 열람 (Member History):** 파티에 속한 다른 사용자의 세부 작업 기록(History)을 조회하여 서로의 작업 패턴을 참고할 수 있습니다.
* **파티(그룹) 관리:** 6자리 고유 코드로 새로운 파티를 생성하거나 기존 파티에 참가할 수 있습니다. 여러 파티에 중복 참가할 수 있습니다.
* **빈 파티 자동 삭제:** 마지막 멤버가 파티를 나가면 데이터베이스에서 해당 파티가 자동으로 삭제되는 GC(Garbage Collection) 기능이 내장되어 있습니다.

### 3. 📊 메뉴바 타임라인 & 툴팁 (Timeline & Hover Tooltips)
* **비주얼 타임라인:** 오늘 하루 집중했던 세션들이 메뉴바 팝오버 하단에 직관적인 타임라인 스트립으로 표시됩니다.
* **마우스 호버 툴팁:** 마우스를 세션 위에 올리면 해당 작업 세션의 구체적인 시작/종료 시간 및 세션 누적 집중 시간이 팝업으로 나타납니다.

### 4. ⚙️ 유연한 개인화 설정 (Customizable Settings)
* **자리비움 대기 시간 (Idle Threshold):** 사용자의 입력이 멈춘 후 몇 초 뒤에 자리비움으로 변경할지 설정합니다.
* **휴식 권장 알림 (Break Reminder):** 장시간 집중했을 때 건강을 위해 알림을 띄우고 휴식을 권장합니다.
* **시스템 시작 시 자동 실행 (Launch at Login):** 컴퓨터를 켜자마자 백그라운드에서 자동으로 추적을 시작하도록 설정할 수 있습니다.

---

## 💻 기술 스택 (Tech Stack)

### macOS Client
- **UI:** SwiftUI (Swift 6 Concurrency 지원)
- **Framework:** AppKit, CoreGraphics (시스템 입력 및 윈도우 감지)
- **Database:** Firebase Cloud Firestore SDK
- **Architecture:** Universal Binary (Apple Silicon `arm64` & Intel `x86_64`)

### Windows Client (REST API)
- **UI:** WinUI 3 / WPF
- **Framework:** Win32 API (P/Invoke - `GetForegroundWindow`, `GetLastInputInfo`)
- **Database:** Firebase REST API (가볍고 무설치 단일 파일 컴파일 지원)

---

## 📄 라이선스 (License)

This project is licensed under the MIT License.

