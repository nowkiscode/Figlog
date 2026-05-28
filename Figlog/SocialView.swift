import SwiftUI

struct SocialView: View {
    @ObservedObject private var firebase = FirebaseManager.shared
    @State private var partyCodeInput = ""
    @State private var newPartyName = ""
    @State private var isCreatingParty = false
    @State private var isShowingEditName = false
    @State private var newName = ""
    
    @State private var showingChatForParty: Party? = nil
    @State private var showingHistoryForUser: UserProfile? = nil
    
    @AppStorage("appLanguage") private var appLanguage = "en"
    
    var body: some View {
        VStack(spacing: 20) {
            if firebase.currentUserProfile == nil {
                VStack(spacing: 8) {
                    ProgressView("Connecting...")
                    if !firebase.debugError.isEmpty {
                        Text(firebase.debugError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                myProfileSection
                
                Divider()
                
                partyManagementSection
                
                partiesListSection
            }
        }
        .onAppear {
            firebase.startListeningToParties()
        }
        .onDisappear {
            firebase.stopListeningToParties()
        }
        .popover(item: $showingChatForParty) { party in
            ChatView(party: party)
                .frame(width: 300, height: 400)
                .environment(\.locale, Locale(identifier: appLanguage))
        }
        .popover(item: $showingHistoryForUser) { user in
            MemberHistoryView(user: user)
                .frame(width: 350, height: 450)
                .environment(\.locale, Locale(identifier: appLanguage))
        }
    }
    

    private var myProfileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My Profile")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                if isShowingEditName {
                    TextField(String(localized: "Name"), text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            saveName()
                        }
                    Button("Save") {
                        saveName()
                    }
                } else {
                    Text(firebase.currentUserProfile?.displayName ?? "")
                        .font(.headline)
                    Button(action: {
                        newName = firebase.currentUserProfile?.displayName ?? ""
                        isShowingEditName = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var partyManagementSection: some View {
        VStack(spacing: 12) {
            if isCreatingParty {
                HStack {
                    TextField(String(localized: "New Party Name"), text: $newPartyName)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Create") {
                        Task {
                            let success = await firebase.createParty(name: newPartyName)
                            if success {
                                newPartyName = ""
                                isCreatingParty = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newPartyName.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    Button("Cancel") {
                        isCreatingParty = false
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack {
                    TextField(String(localized: "Enter Party Code"), text: $partyCodeInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    
                    Button("Join") {
                        Task {
                            let success = await firebase.joinParty(code: partyCodeInput)
                            if success {
                                partyCodeInput = ""
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(partyCodeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    Button("Create Party") {
                        isCreatingParty = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    private var partiesListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("My Parties")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: {
                    firebase.refreshParties()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Refresh Parties")
            }
            
            if firebase.myParties.isEmpty {
                Text("You haven't joined any parties yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(firebase.myParties) { party in
                            partySection(party)
                        }
                    }
                }
            }
        }
    }
    
    private func partySection(_ party: Party) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(party.name)
                    .font(.headline)
                
                Text(party.id ?? "")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
                    .onTapGesture {
                        if let code = party.id {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                        }
                    }
                    .help("Click to copy code")
                
                Spacer()
                
                Button("Leave") {
                    if let code = party.id {
                        Task {
                            await firebase.leaveParty(code: code)
                        }
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                
                Button(action: {
                    showingChatForParty = party
                }) {
                    Image(systemName: "message")
                }
                .buttonStyle(.borderless)
                .help("Party Chat")
            }
            
            let members = party.members.compactMap { firebase.profilesCache[$0] }.sorted { $0.todayFocusTime > $1.todayFocusTime }
            if members.isEmpty {
                Text("Loading members...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        friendRow(member, index: index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showingHistoryForUser = member
                            }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func friendRow(_ friend: UserProfile, index: Int) -> some View {
        HStack(spacing: 12) {
            if index == 0 {
                Text("👑")
            } else if index == 1 {
                Text("🥈")
            } else if index == 2 {
                Text("🥉")
            } else {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
            }
            
            Circle()
                .fill(statusColor(for: friend))
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(statusText(for: friend))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(FocusTracker.formatCompactDuration(friend.todayFocusTime))
                    .font(.subheadline)
                    .monospacedDigit()
                Text("Today")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func saveName() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            firebase.updateDisplayName(trimmed)
        }
        isShowingEditName = false
    }
    
    private func statusColor(for friend: UserProfile) -> Color {
        // If last updated more than 10 minutes ago (600 seconds), consider offline
        if Date().timeIntervalSince(friend.lastUpdatedAt) > 600 {
            return .gray
        }
        
        switch friend.status {
        case "tracking": return .green
        case "idle": return .yellow
        case "paused": return .orange
        case "waiting": return .gray
        case "offline": return .gray
        default: return .gray
        }
    }
    
    private func statusText(for friend: UserProfile) -> String {
        // If last updated more than 10 minutes ago (600 seconds), consider offline
        if Date().timeIntervalSince(friend.lastUpdatedAt) > 600 {
            return "Offline"
        }
        
        switch friend.status {
        case "tracking": return "Focusing in Figma"
        case "idle": return "Idle"
        case "paused": return "Paused"
        case "waiting": return "Waiting for Figma"
        case "offline": return "Offline"
        default: return "Offline"
        }
    }
}

// MARK: - Chat View
struct ChatView: View {
    let party: Party
    @ObservedObject private var firebase = FirebaseManager.shared
    @State private var inputText = ""
    @State private var notificationsEnabled = true
    
    var body: some View {
        VStack {
            HStack {
                Text("\(party.name) Chat")
                    .font(.headline)
                Spacer()
                Toggle(isOn: $notificationsEnabled) {
                    Image(systemName: notificationsEnabled ? "bell.fill" : "bell.slash.fill")
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .onChange(of: notificationsEnabled) { oldValue, newValue in
                    UserDefaults.standard.set(newValue, forKey: "notificationsEnabled_\(party.id ?? "")")
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let messages = firebase.chatMessages[party.id ?? ""] ?? []
                    ForEach(messages) { msg in
                        let isMe = msg.senderId == firebase.currentUserProfile?.id
                        HStack {
                            if isMe { Spacer() }
                            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                                HStack {
                                    if !isMe {
                                        Text(msg.senderName)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                    }
                                    Text(msg.timestamp, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(msg.text)
                                    .font(.body)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(isMe ? Color.accentColor : Color.secondary.opacity(0.15))
                                    .foregroundColor(isMe ? .white : .primary)
                                    .cornerRadius(12)
                            }
                            if !isMe { Spacer() }
                        }
                    }
                }
                .padding()
            }
            
            HStack {
                TextField("Message...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendMessage() }
                
                Button("Send") { sendMessage() }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .onAppear {
            let key = "notificationsEnabled_\(party.id ?? "")"
            if UserDefaults.standard.object(forKey: key) != nil {
                notificationsEnabled = UserDefaults.standard.bool(forKey: key)
            }
        }
    }
    
    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let partyId = party.id else { return }
        firebase.sendMessage(text: trimmed, partyId: partyId)
        inputText = ""
    }
}

// MARK: - Member History View
struct MemberHistoryView: View {
    let user: UserProfile
    @ObservedObject private var firebase = FirebaseManager.shared
    @State private var historyData: [Date: RemoteDailyRecord]? = nil
    @State private var isLoading = true
    
    var body: some View {
        VStack {
            VStack(spacing: 4) {
                Text("\(user.displayName)'s History")
                    .font(.headline)
                Text("History is updated daily at midnight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            
            if user.shareHistory == false {
                Text("This user has hidden their history.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding()
            } else if isLoading {
                ProgressView("Loading...")
                    .padding()
            } else if let data = historyData, !data.isEmpty {
                let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
                let filteredData = data.filter { $0.key >= thirtyDaysAgo }
                let totalFocus = filteredData.values.map { $0.totalFocusTime }.reduce(0, +)
                let totalIdleTime = filteredData.values.map { $0.totalIdleTime }.reduce(0, +)
                
                VStack(alignment: .leading, spacing: 32) {
                    HStack(spacing: 40) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last 30 Days")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(FocusTracker.formatCompactDuration(totalFocus))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Idle Total")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(FocusTracker.formatCompactDuration(totalIdleTime))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Activity Heatmap")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        calendarHeatmap(stats: data)
                    }
                }
                .padding()
                Spacer()
            } else {
                Text("No history available.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            }
        }
        .frame(width: 360, height: 400)
        .task {
            if user.shareHistory != false, let uid = user.id {
                historyData = await firebase.fetchMemberHistory(uid: uid)
            }
            isLoading = false
        }
    }
    
    private func calendarHeatmap(stats: [Date: RemoteDailyRecord]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let days = lastNDays(30)
        let maxTime = stats.values.map { $0.totalFocusTime }.max() ?? 1
        let weekdays = Calendar.current.shortWeekdaySymbols
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.self) { date in
                    if date > Calendar.current.startOfDay(for: Date()) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.clear)
                            .aspectRatio(1, contentMode: .fit)
                    } else if let record = stats.first(where: { Calendar.current.isDate($0.key, inSameDayAs: date) })?.value {
                        let intensity = record.totalFocusTime / maxTime
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(max(0.15, intensity)))
                            .aspectRatio(1, contentMode: .fit)
                            .help("\(date.formatted(date: .abbreviated, time: .omitted)): \(FocusTracker.formatCompactDuration(record.totalFocusTime))")
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                            .aspectRatio(1, contentMode: .fit)
                            .help("\(date.formatted(date: .abbreviated, time: .omitted)): No activity")
                    }
                }
            }
        }
    }

    private func lastNDays(_ daysCount: Int) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysToSaturday = 7 - weekday
        let endOfWeek = calendar.date(byAdding: .day, value: daysToSaturday, to: today)!
        
        let gridCells = 35
        return (0..<gridCells).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: endOfWeek) }
    }
}
