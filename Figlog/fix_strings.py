import json

with open('Localizable.xcstrings', 'r', encoding='utf-8') as f:
    data = json.load(f)

translations = {
    "Cancel": "취소",
    "Click to copy code": "클릭하여 코드 복사",
    "Connecting...": "연결 중...",
    "Create": "생성",
    "Create Party": "파티 생성",
    "Enter Party Code": "파티 코드 입력",
    "Focusing in Figma": "피그마 집중 중",
    "Idle": "유휴 상태",
    "Join": "참가",
    "Leave": "나가기",
    "Loading members...": "멤버 불러오는 중...",
    "My Parties": "내 파티 목록",
    "My Profile": "내 프로필",
    "My Stats": "내 통계",
    "Name": "이름",
    "New Party Name": "새 파티 이름",
    "Offline": "오프라인",
    "Paused": "일시정지",
    "Refresh Parties": "파티 새로고침",
    "Save": "저장",
    "Waiting for Figma": "피그마 대기 중",
    "You haven't joined any parties yet.": "아직 참가한 파티가 없습니다."
}

strings = data.get("strings", {})

for key, translated_value in translations.items():
    if key not in strings:
        strings[key] = {}
    
    if "localizations" not in strings[key]:
        strings[key]["localizations"] = {}
        
    strings[key]["localizations"]["ko"] = {
        "stringUnit": {
            "state": "translated",
            "value": translated_value
        }
    }

with open('Localizable.xcstrings', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print("Translations updated successfully.")
