# Figlog - 무료 배포 빌드 완벽 가이드 (Ad-hoc 서명)

애플 개발자 계정 결제($99/년) 없이, 전 세계 어떤 맥북에서도 열릴 수 있는 `Figlog.app`을 빌드하고 배포하는 방법입니다.

## 1. 개요 (왜 이런 과정을 거치는가?)
1. **Firebase Auth 제약 우회**: 기본 `FirebaseAuth`는 맥의 `Keychain` 접근을 요구하는데, 이는 개발자 인증서(Team ID)와 프로비저닝 프로필을 필수로 요구합니다. 이를 피하기 위해 `FirebaseAuth`를 삭제하고 자체 UUID를 `UserDefaults`에 저장하는 방식으로 인증을 대체했습니다. (Firestore 보안 규칙은 `allow read, write: if true;`로 설정)
2. **샌드박스(App Sandbox) 해제**: 샌드박스가 켜져 있으면 임의의 네트워킹 및 파일 시스템 접근이 막히며, 서명 검증이 깐깐해집니다.
3. **프로비저닝 프로필 삭제**: 프로비저닝 프로필은 "특정 맥북(UUID)에서만 실행 가능"하도록 제한을 겁니다. 이를 삭제하여 모든 기기에서 실행되게 만듭니다.
4. **꼬리표(Quarantine) 제거**: 다운로드한 앱에는 격리 꼬리표가 붙는데, 내부에 포장된 수십 개의 라이브러리(Firebase 등)는 `그래도 열기` 버튼으로 꼬리표가 떼어지지 않습니다. 명령어(`xattr -cr`)로 재귀적(Recursive)으로 떼어내야 합니다.

## 2. 완벽 빌드 터미널 명령어

Xcode의 자동 서명 기능이 자꾸 `Figlog.entitlements`에 샌드박스와 키체인 권한을 억지로 집어넣으려 하기 때문에, Xcode 화면의 'Build' 버튼을 누르지 말고 **무조건 터미널에서 아래 명령어를 실행해야 합니다.**

```bash
# 1단계: 권한 찌꺼기 파일(Entitlements) 속을 텅텅 비우기
cat << 'EOF' > Figlog/Figlog.entitlements
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EOF

# 2단계: Xcode 억지 서명 무시하고 Unsandboxed 쌩얼로 빌드하기 (Intel 및 Apple Silicon 모두 지원하는 Universal Binary 빌드)
xcodebuild -scheme Figlog -configuration Release CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ENABLE_APP_SANDBOX=NO ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO

# 3단계: 완성된 순정 앱을 바탕화면으로 복사하기
rm -rf ~/Desktop/Figlog.app 
cp -R $(find ~/Library/Developer/Xcode/DerivedData/Figlog-*/Build/Products/Release -maxdepth 1 -name "Figlog.app" | head -n 1) ~/Desktop/Figlog.app 

# 4단계: 내부에 숨겨진 모든 프레임워크(Firebase 등)에 야매(Ad-hoc) 서명 먹이기
find ~/Desktop/Figlog.app/Contents/Frameworks -type d -name "*.framework" -exec codesign --force --sign - {} \; 

# 5단계: 앱 메인 껍데기에 야매(Ad-hoc) 서명 먹이기
codesign --force --sign - ~/Desktop/Figlog.app 

# 6단계: 내 컴퓨터에서 꼬리표 떼기
xattr -cr ~/Desktop/Figlog.app
```

> **Tip 1:** 위 명령어를 한 줄씩 치기 귀찮다면, 모든 줄을 한꺼번에 복사해서 터미널에 붙여넣기 하셔도 됩니다.
> **Tip 2 (Intel Mac 대응):** 기본 빌드는 M1/M2/M3 맥북에서 실행하면 Apple Silicon(`arm64`) 전용으로 빌드됩니다. 위 2단계 명령에 `ARCHS="arm64 x86_64"`와 `ONLY_ACTIVE_ARCH=NO`를 추가함으로써, 하나의 앱 파일 안에 인텔과 애플 실리콘 바이너리가 모두 포함되는 **Universal Binary** 형태로 빌드됩니다. 


## 3. 친구에게 배포 및 실행 방법

1. 위 과정을 거쳐 바탕화면에 생성된 `Figlog.app`을 우클릭하여 **'Figlog 압축'**(`Figlog.zip`)을 만듭니다.
2. 압축 파일을 친구에게 전송합니다.
3. 친구는 다운로드 후 압축을 풉니다.
4. 친구 맥북의 터미널(Terminal)을 열고 아래 명령어를 입력합니다. (앱이 다운로드 폴더에 있는 경우)
   ```bash
   xattr -cr ~/Downloads/Figlog.app
   ```
5. `Figlog.app`을 더블클릭하면 어떤 경고나 에러 없이 정상 실행됩니다!

---

## 4. 🚨 트러블슈팅 (Troubleshooting)

### 인텔 맥(Intel Mac)에서 실행이 안 되는 경우

1. **CPU 아키텍처 문제 (Universal Binary 빌드 미적용)**
   - Apple Silicon(M1/M2/M3) 맥북에서 컴파일하면 기본적으로 인텔 맥에서 실행할 수 없는 `arm64` 전용 바이너리가 생성됩니다. 
   - **해결책:** 2단계 빌드 명령어 수행 시 `ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO` 인자가 들어갔는지 반드시 확인해 주세요.
   - **확인 방법:** 빌드된 `Figlog.app`을 우클릭하여 '정보 가져오기(Get Info)'를 누른 뒤 종류가 **'애플리케이션(범용)'** 혹은 **'Application (Universal)'**으로 되어 있는지 확인합니다. 터미널에서 `file ~/Desktop/Figlog.app/Contents/MacOS/Figlog`를 쳤을 때 `Mach-O universal binary` 라고 나오면 정상입니다.

2. **macOS 버전 문제 (Deployment Target)**
   - 현재 Figlog의 최소 지원 macOS 버전은 **14.6(Sonoma)**으로 설정되어 있습니다. 구형 인텔 맥의 경우 macOS 버전이 14.6보다 낮으면 앱이 실행되지 않습니다.
   - **해결책:**
     1. Xcode에서 `Figlog` 프로젝트 파일 선택 -> [Target] -> [Build Settings] -> **macOS Deployment Target**을 `14.0` 혹은 `13.0`(Ventura) 등으로 낮춥니다.
     2. `project.pbxproj` 파일 내의 `MACOSX_DEPLOYMENT_TARGET` 값들을 원하는 버전(예: `14.0`)으로 수정하고 저장한 뒤 다시 빌드 명령어를 실행합니다.

