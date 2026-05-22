import SwiftUI

struct SocialView: View {
    @ObservedObject private var firebase = FirebaseManager.shared
    @State private var inviteCodeInput = ""
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
                
                addFriendSection
                
                friendsListSection
            }
        }
        .onAppear {
            firebase.startListeningToFriends()
        }
        .onDisappear {
            firebase.stopListeningToFriends()
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
                
                VStack(alignment: .trailing) {
                    Text(String(localized: "Invite Code"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 4) {
                        Text(firebase.currentUserProfile?.inviteCode ?? "")
                            .font(.system(.body, design: .monospaced, weight: .bold))
                            .textSelection(.enabled)
                        Button(action: {
                            if let code = firebase.currentUserProfile?.inviteCode {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                            }
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var addFriendSection: some View {
        HStack {
            TextField(String(localized: "Friend's Invite Code"), text: $inviteCodeInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            
            Button(String(localized: "Add Friend")) {
                Task {
                    let success = await firebase.addFriend(by: inviteCodeInput)
                    if success {
                        inviteCodeInput = ""
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(inviteCodeInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
    
    private var friendsListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Friend Status"))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if firebase.friendsProfiles.isEmpty {
                Text(String(localized: "No friends added yet."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(firebase.friendsProfiles) { friend in
                            friendRow(friend)
                        }
                    }
                }
            }
        }
    }
    
    private func friendRow(_ friend: UserProfile) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor(for: friend.status))
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(statusText(for: friend.status))
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
    
    private func statusColor(for status: String) -> Color {
        switch status {
        case "tracking": return .green
        case "idle": return .yellow
        case "paused": return .orange
        case "offline": return .gray
        default: return .gray
        }
    }
    
    private func statusText(for status: String) -> String {
        switch status {
        case "tracking": return String(localized: "Focusing in Figma")
        case "idle": return String(localized: "Idle")
        case "paused": return String(localized: "Paused")
        case "offline": return String(localized: "Offline")
        default: return String(localized: "Offline")
        }
    }
}
