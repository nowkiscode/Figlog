import re
import os

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Generic replacements
    content = re.sub(r'Text\(String\(localized: "([^"]+)"\)\)', r'Text("\1")', content)
    content = re.sub(r'Button\(String\(localized: "([^"]+)"\)\)', r'Button("\1")', content)
    content = re.sub(r'\.help\(String\(localized: "([^"]+)"\)\)', r'.help("\1")', content)
    content = re.sub(r'Label\(String\(localized: "([^"]+)"\)\)', r'Label("\1")', content)
    content = re.sub(r'ProgressView\(String\(localized: "([^"]+)"\)\)', r'ProgressView("\1")', content)
    content = re.sub(r'TextField\(String\(localized: "([^"]+)"\)\)', r'TextField("\1")', content)

    # Specific fixes
    if 'ContentView.swift' in filepath:
        content = content.replace(
            'let periodTitle = historyPeriod == 7 ? String(localized: "Last 7 Days") : String(localized: "Last 30 Days")',
            'let periodTitle: LocalizedStringKey = historyPeriod == 7 ? "Last 7 Days" : "Last 30 Days"'
        )
        content = content.replace(
            'statBlock(title: String, value: String)',
            'statBlock(title: LocalizedStringKey, value: String)'
        )
        content = content.replace(
            'Text(tracker.statusText)',
            'Text(LocalizedStringKey(tracker.statusText))'
        )
        # statBlock calls
        content = re.sub(r'statBlock\(title: String\(localized: "([^"]+)"\),', r'statBlock(title: "\1",', content)
        
        # HelpView hardcoded strings -> Text("XYZ") which are automatically LocalizedStringKey
        content = content.replace('Text("How to use FigLog")', 'Text("How to use FigLog")')
        content = content.replace('Text("Timeline Colors:")', 'Text("Timeline Colors:")')

    if 'FocusTracker.swift' in filepath:
        content = re.sub(r'return String\(localized: "([^"]+)"\)', r'return "\1"', content)
        content = content.replace('String(localized: "Time for a short break")', '"Time for a short break"')
        # Notification content cannot easily use SwiftUI environment, so let's leave FocusTracker notification as String(localized:) for now, or use NSLocalizedString. Wait, the Python script already replaced it if it matches `return ...`. For Notifications:
        # It's at line 499: content.title = String(localized: "Time for a short break").
        # If I replaced it to `"Time for a short break"`, the notification won't be localized unless I use NSLocalizedString. But the user didn't mention notifications. Let's fix the UI first.
        content = content.replace('content.title = "Time for a short break"', 'content.title = String(localized: "Time for a short break")')
        
    if 'SocialView.swift' in filepath:
        content = re.sub(r'return String\(localized: "([^"]+)"\)', r'return "\1"', content)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

process_file('ContentView.swift')
process_file('SocialView.swift')
process_file('SettingsView.swift')
process_file('FocusTracker.swift')

print("Refactoring complete.")
