import SwiftUI

struct SocialView: View {
    @ObservedObject private var firebase = FirebaseManager.shared
    @State private var partyCodeInput = ""
    @State private var newPartyName = ""
    @State private var isCreatingParty = false
    @State private var isShowingEditName = false
    @State private var newName = ""
    
    var body: some View {
        VStack(spacing: 20) {
            if firebase.currentUserProfile == nil {
                VStack(spacing: 8) {
                    ProgressView(String(localized: "Connecting..."))
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
    }
    

    private var myProfileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "My Profile"))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                if isShowingEditName {
                    TextField(String(localized: "Name"), text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            saveName()
                        }
                    Button(String(localized: "Save")) {
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
                    
                    Button(String(localized: "Create")) {
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
                    
                    Button(String(localized: "Cancel")) {
                        isCreatingParty = false
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack {
                    TextField(String(localized: "Enter Party Code"), text: $partyCodeInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    
                    Button(String(localized: "Join")) {
                        Task {
                            let success = await firebase.joinParty(code: partyCodeInput)
                            if success {
                                partyCodeInput = ""
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(partyCodeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    Button(String(localized: "Create Party")) {
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
                Text(String(localized: "My Parties"))
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
                .help(String(localized: "Refresh Parties"))
            }
            
            if firebase.myParties.isEmpty {
                Text(String(localized: "You haven't joined any parties yet."))
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
                    .help(String(localized: "Click to copy code"))
                
                Spacer()
                
                Button(String(localized: "Leave")) {
                    if let code = party.id {
                        Task {
                            await firebase.leaveParty(code: code)
                        }
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
            
            let members = party.members.compactMap { firebase.profilesCache[$0] }.sorted { $0.displayName < $1.displayName }
            if members.isEmpty {
                Text(String(localized: "Loading members..."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 8) {
                    ForEach(members) { member in
                        friendRow(member)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func friendRow(_ friend: UserProfile) -> some View {
        HStack(spacing: 12) {
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
                Text(String(localized: "Today"))
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
        case "offline": return .gray
        default: return .gray
        }
    }
    
    private func statusText(for friend: UserProfile) -> String {
        // If last updated more than 10 minutes ago (600 seconds), consider offline
        if Date().timeIntervalSince(friend.lastUpdatedAt) > 600 {
            return String(localized: "Offline")
        }
        
        switch friend.status {
        case "tracking": return String(localized: "Focusing in Figma")
        case "idle": return String(localized: "Idle")
        case "paused": return String(localized: "Paused")
        case "offline": return String(localized: "Offline")
        default: return String(localized: "Offline")
        }
    }
}
