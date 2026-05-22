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

# 2단계: Xcode 억지 서명 무시하고 Unsandboxed 쌩얼로 빌드하기
xcodebuild -scheme Figlog -configuration Release CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ENABLE_APP_SANDBOX=NO 

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

> **Tip:** 위 명령어를 한 줄씩 치기 귀찮다면, 모든 줄을 한꺼번에 복사해서 터미널에 붙여넣기 하셔도 됩니다.

## 3. 친구에게 배포 및 실행 방법

1. 위 과정을 거쳐 바탕화면에 생성된 `Figlog.app`을 우클릭하여 **'Figlog 압축'**(`Figlog.zip`)을 만듭니다.
2. 압축 파일을 친구에게 전송합니다.
3. 친구는 다운로드 후 압축을 풉니다.
4. 친구 맥북의 터미널(Terminal)을 열고 아래 명령어를 입력합니다. (앱이 다운로드 폴더에 있는 경우)
   ```bash
   xattr -cr ~/Downloads/Figlog.app
   ```
5. `Figlog.app`을 더블클릭하면 어떤 경고나 에러 없이 정상 실행됩니다!
