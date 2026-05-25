import json

translations = {
    "My Stats": "내 통계",
    "Friends": "파티 목록",
    "Back": "뒤로",
    "Weekly": "주간",
    "Monthly": "월간",
    "Last 7 Days": "최근 7일",
    "Last 30 Days": "최근 30일",
    "Idle Total": "총 유휴 시간",
    "Activity Heatmap": "활동 히트맵",
    "Resume tracking": "추적 재개",
    "Pause tracking": "추적 일시정지",
    "History": "히스토리",
    "Quit FigLog": "FigLog 종료",
    "Sessions": "세션 수",
    "Idle Today": "오늘 총 유휴 시간",
    "Idle after": "유휴 상태 감지 기준",
    "Timeline": "타임라인",
    "Recent Sessions": "최근 집중 기록",
    "No Figma focus sessions yet today": "아직 오늘의 피그마 집중 기록이 없습니다",
    "Paused": "일시정지",
    "Tracking Figma": "Figma 추적 중",
    "Out of Figma but still tracking": "피그마 이탈 중 (추적 유지)",
    "Waiting for Figma": "피그마 대기 중",
    "Time for a short break": "잠깐 쉬어갈 시간입니다",
    "You have focused in Figma for %@.": "피그마에서 %@ 동안 집중했습니다.",
    "General": "일반",
    "Time without activity before a session is marked idle.": "해당 시간 동안 마우스/키보드 입력이 없으면 유휴 상태(Idle)로 전환됩니다.",
    "Grace period": "피그마 이탈 허용 시간",
    "Time allowed outside Figma before a session ends.": "피그마가 아닌 다른 앱을 사용해도 이 시간 내에 돌아오면 집중 시간이 유지됩니다.",
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
    "Name": "이름",
    "New Party Name": "새 파티 이름",
    "Offline": "오프라인",
    "Refresh Parties": "파티 새로고침",
    "Save": "저장",
    "You haven't joined any parties yet.": "아직 참가한 파티가 없습니다.",
    "Today": "오늘",
    "Remind me after": "휴식 알림 기준 시간",
    "Break reminder": "휴식 알림",
    "Language": "언어",
    "English": "영어",
    "Korean": "한국어",
    "Launch at login": "로그인 시 자동 실행"
}

with open('Localizable.xcstrings', 'r', encoding='utf-8') as f:
    data = json.load(f)

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

print("Translations completely updated.")
