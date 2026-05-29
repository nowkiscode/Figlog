import Foundation
import Combine
import FirebaseCore
import FirebaseFirestore
import UserNotifications

// MARK: - User Profile Model
struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String?
    var displayName: String
    var status: String // "tracking", "idle", "offline"
    var activeAppName: String?
    var todayFocusTime: TimeInterval
    var lastUpdatedAt: Date
    var shareHistory: Bool?
}

// MARK: - Party Model
struct Party: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var members: [String]
    var createdAt: Date
}

// MARK: - Chat & History Models
struct ChatMessage: Codable, Identifiable {
    @DocumentID var id: String?
    var senderId: String
    var senderName: String
    var text: String
    var timestamp: Date
    var expireAt: Date
}

struct RemoteDailyRecord: Codable {
    var totalFocusTime: TimeInterval
    var totalIdleTime: TimeInterval
    var sessions: [FocusSession]
}

// MARK: - Firebase Manager
final class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    
    // Lifecycle
    deinit {
        stopListeningToParties()
    }
    
    // Published properties for SwiftUI bindings
    @Published var currentUserProfile: UserProfile?
    @Published var myParties: [Party] = []
    @Published var profilesCache: [String: UserProfile] = [:]
    @Published var debugError: String = ""
    @Published var latestVersion: String? = nil
    
    // Chat & History Data
    @Published var chatMessages: [String: [ChatMessage]] = [:] // partyId -> messages
    
    // MARK: - Private Properties
    private var db = Firestore.firestore()
    private var myProfileListener: ListenerRegistration?
    private var myPartiesListener: ListenerRegistration?
    private var membersListeners: [ListenerRegistration] = []
    private var chatListeners: [String: ListenerRegistration] = [:]
    private var isListeningToPartiesView = false
    private let usersCollection = "users"
    
    private init() {}
    
    // MARK: - User Setup
    func setupUser() async {
        var currentUID = UserDefaults.standard.string(forKey: "userUID") ?? ""
        if currentUID.isEmpty {
            currentUID = UUID().uuidString
            UserDefaults.standard.set(currentUID, forKey: "userUID")
        }
        print("Firebase initialized with UUID: \(currentUID)")
        await setupUserProfile(uid: currentUID)
        listenToMyProfile(uid: currentUID)
        await fetchLatestVersion()
    }
    
    
    private func setupUserProfile(uid: String) async {
        let docRef = db.collection(usersCollection).document(uid)
        do {
            let document = try await docRef.getDocument()
            if !document.exists {
                let newProfile = UserProfile(
                    displayName: "User_" + String(Int.random(in: 1000...9999)),
                    status: "offline",
                    todayFocusTime: 0,
                    lastUpdatedAt: Date(),
                    shareHistory: true
                )
                try docRef.setData(from: newProfile)
                self.currentUserProfile = newProfile
            } else {
                self.currentUserProfile = try document.data(as: UserProfile.self)
            }
        } catch {
            let errorMsg = "Firestore Error: \(error.localizedDescription)"
            print(errorMsg)
            self.debugError = errorMsg
        }
    }
    
    // MARK: - Firestore Listeners
    private func listenToMyProfile(uid: String) {
        myProfileListener?.remove()
        myProfileListener = db.collection(usersCollection).document(uid)
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self, let document = documentSnapshot else { return }
                DispatchQueue.main.async {
                    do {
                        self.currentUserProfile = try document.data(as: UserProfile.self)
                    } catch {
                        print("Error decoding my profile: \(error)")
                    }
                }
            }
    }
    
    // MARK: - Parties & Members Listeners
    func startListeningToParties() {
        guard !isListeningToPartiesView else { return }
        isListeningToPartiesView = true
        listenToMyParties()
    }
    
    func stopListeningToParties() {
        guard isListeningToPartiesView else { return }
        isListeningToPartiesView = false
        myPartiesListener?.remove()
        myPartiesListener = nil
        membersListeners.forEach { $0.remove() }
        membersListeners.removeAll()
        chatListeners.values.forEach { $0.remove() }
        chatListeners.removeAll()
        myParties = []
        profilesCache.removeAll()
        chatMessages.removeAll()
    }
    
    func refreshParties() {
        stopListeningToParties()
        startListeningToParties()
    }
    
    private func listenToMyParties() {
        guard let myUid = UserDefaults.standard.string(forKey: "userUID") else { return }
        myPartiesListener?.remove()
        myPartiesListener = db.collection("parties")
            .whereField("members", arrayContains: myUid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let docs = snapshot?.documents else { return }
                var parties: [Party] = []
                var allMemberUIDs = Set<String>()
                for doc in docs {
                    if let party = try? doc.data(as: Party.self) {
                        parties.append(party)
                        for uid in party.members {
                            allMemberUIDs.insert(uid)
                        }
                    }
                }
                DispatchQueue.main.async {
                    self.myParties = parties.sorted { $0.name < $1.name }
                    if self.isListeningToPartiesView {
                        self.listenToMembers(uids: Array(allMemberUIDs))
                        for party in parties {
                            if let pid = party.id {
                                self.listenToChatMessages(partyId: pid)
                            }
                        }
                    }
                }
            }
    }
    
    private func listenToMembers(uids: [String]) {
        membersListeners.forEach { $0.remove() }
        membersListeners.removeAll()
        
        guard !uids.isEmpty else { return }
        
        let chunks = stride(from: 0, to: uids.count, by: 10).map {
            Array(uids[$0..<min($0 + 10, uids.count)])
        }
        
        for chunk in chunks {
            let listener = db.collection(usersCollection)
                .whereField(FieldPath.documentID(), in: chunk)
                .addSnapshotListener { [weak self] snapshot, error in
                    guard let self = self, let docs = snapshot?.documents else { return }
                    for doc in docs {
                        if let profile = try? doc.data(as: UserProfile.self), let uid = profile.id {
                            DispatchQueue.main.async {
                                self.profilesCache[uid] = profile
                            }
                        }
                    }
                }
            membersListeners.append(listener)
        }
    }
    
    // MARK: - Status & Profile Updates
    func updateMyStatus(status: String, activeAppName: String?, todayFocusTime: TimeInterval) {
        guard let uid = UserDefaults.standard.string(forKey: "userUID") else { return }
        
        var data: [String: Any] = [
            "status": status,
            "todayFocusTime": todayFocusTime,
            "lastUpdatedAt": FieldValue.serverTimestamp()
        ]
        
        if let activeAppName = activeAppName {
            data["activeAppName"] = activeAppName
        } else {
            data["activeAppName"] = FieldValue.delete()
        }

        db.collection(usersCollection).document(uid).updateData(data) { error in
            if let error = error {
                print("Error updating status: \(error)")
            }
        }
    }
    
    func updateDisplayName(_ name: String) {
        guard let uid = UserDefaults.standard.string(forKey: "userUID") else { return }
        db.collection(usersCollection).document(uid).updateData(["displayName": name])
    }
    
    func updateShareHistory(_ share: Bool) {
        guard let uid = UserDefaults.standard.string(forKey: "userUID") else { return }
        db.collection(usersCollection).document(uid).updateData(["shareHistory": share])
    }
    
    // MARK: - Party Management
    func createParty(name: String) async -> Bool {
        guard let myUid = UserDefaults.standard.string(forKey: "userUID") else { return false }
        let code = generatePartyCode()
        let party = Party(id: code, name: name, members: [myUid], createdAt: Date())
        do {
            try db.collection("parties").document(code).setData(from: party)
            return true
        } catch {
            print("Error creating party: \(error)")
            return false
        }
    }
    
    func joinParty(code: String) async -> Bool {
        guard let myUid = UserDefaults.standard.string(forKey: "userUID") else { return false }
        let upperCode = code.uppercased().trimmingCharacters(in: .whitespaces)
        guard !upperCode.isEmpty else { return false }
        let docRef = db.collection("parties").document(upperCode)
        do {
            let doc = try await docRef.getDocument()
            if doc.exists {
                try await docRef.updateData([
                    "members": FieldValue.arrayUnion([myUid])
                ])
                return true
            }
            return false
        } catch {
            print("Error joining party: \(error)")
            return false
        }
    }
    
    func leaveParty(code: String) async -> Bool {
        guard let myUid = UserDefaults.standard.string(forKey: "userUID") else { return false }
        let upperCode = code.uppercased()
        let docRef = db.collection("parties").document(upperCode)
        do {
            let _ = try await db.runTransaction { (transaction, errorPointer) -> Any? in
                let doc: DocumentSnapshot
                do {
                    try doc = transaction.getDocument(docRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                
                guard let party = try? doc.data(as: Party.self) else { return nil }
                
                var newMembers = party.members
                newMembers.removeAll { $0 == myUid }
                
                if newMembers.isEmpty {
                    transaction.deleteDocument(docRef)
                } else {
                    transaction.updateData(["members": newMembers], forDocument: docRef)
                }
                return nil
            }
            return true
        } catch {
            print("Error leaving party: \(error)")
            return false
        }
    }
    
    // MARK: - Chat & History Features
    
    func sendMessage(text: String, partyId: String) {
        guard let uid = UserDefaults.standard.string(forKey: "userUID"),
              let name = currentUserProfile?.displayName, !text.isEmpty else { return }
        
        let expireAt = Calendar.current.date(byAdding: .day, value: 15, to: Date()) ?? Date().addingTimeInterval(15 * 24 * 3600)
        let message = ChatMessage(senderId: uid, senderName: name, text: text, timestamp: Date(), expireAt: expireAt)
        
        do {
            try db.collection("parties").document(partyId).collection("messages").addDocument(from: message)
        } catch {
            print("Error sending message: \(error)")
        }
    }
    
    private func listenToChatMessages(partyId: String) {
        if chatListeners[partyId] != nil { return }
        
        let listener = db.collection("parties").document(partyId).collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let snapshot = snapshot else { return }
                
                var newMessages: [ChatMessage] = []
                
                let myUid = UserDefaults.standard.string(forKey: "userUID") ?? ""
                
                for change in snapshot.documentChanges {
                    if change.type == .added, let msg = try? change.document.data(as: ChatMessage.self) {
                        if msg.senderId != myUid && msg.timestamp.timeIntervalSinceNow > -5.0 {
                            // Check if notifications are enabled for this party
                            let defaults = UserDefaults.standard
                            let key = "notificationsEnabled_\(partyId)"
                            let enabled = defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
                            
                            if enabled {
                                self.triggerLocalNotification(title: msg.senderName, body: msg.text)
                            }
                        }
                    }
                }
                
                for doc in snapshot.documents {
                    if let msg = try? doc.data(as: ChatMessage.self) {
                        newMessages.append(msg)
                    }
                }
                
                DispatchQueue.main.async {
                    self.chatMessages[partyId] = newMessages
                }
            }
        chatListeners[partyId] = listener
    }
    
    private func triggerLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func uploadDailyHistory(date: Date, totalFocusTime: TimeInterval, totalIdleTime: TimeInterval, sessions: [FocusSession]) {
        guard let uid = UserDefaults.standard.string(forKey: "userUID") else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let docId = formatter.string(from: date)
        
        let record = RemoteDailyRecord(totalFocusTime: totalFocusTime, totalIdleTime: totalIdleTime, sessions: sessions)
        
        do {
            try db.collection(usersCollection).document(uid).collection("history").document(docId).setData(from: record)
        } catch {
            print("Error uploading history: \(error)")
        }
    }
    
    func fetchMemberHistory(uid: String) async -> [Date: RemoteDailyRecord]? {
        do {
            let snapshot = try await db.collection(usersCollection).document(uid).collection("history").getDocuments()
            var history: [Date: RemoteDailyRecord] = [:]
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            
            for doc in snapshot.documents {
                if let record = try? doc.data(as: RemoteDailyRecord.self), let date = formatter.date(from: doc.documentID) {
                    history[date] = record
                }
            }
            return history
        } catch {
            print("Error fetching member history: \(error)")
            return nil
        }
    }
    
    // MARK: - Utilities
    private func generatePartyCode() -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).compactMap { _ in letters.randomElement() })
    }
    
    func fetchLatestVersion() async {
        let docRef = db.collection("config").document("app")
        do {
            let doc = try await docRef.getDocument()
            if doc.exists, let data = doc.data(), let latest = data["latestVersion"] as? String {
                let latestVer = latest
                DispatchQueue.main.async {
                    self.latestVersion = latestVer
                }
            }
        } catch {
            print("Error fetching latest version: \(error.localizedDescription)")
        }
    }
}
