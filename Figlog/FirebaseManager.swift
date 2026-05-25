import Foundation
import Combine
import FirebaseCore
import FirebaseFirestore

// MARK: - User Profile Model
struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String?
    var displayName: String
    var status: String // "tracking", "idle", "offline"
    var todayFocusTime: TimeInterval
    var lastUpdatedAt: Date
}

// MARK: - Party Model
struct Party: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var members: [String]
    var createdAt: Date
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
    
    // MARK: - Private Properties
    private var db = Firestore.firestore()
    private var myProfileListener: ListenerRegistration?
    private var myPartiesListener: ListenerRegistration?
    private var membersListeners: [ListenerRegistration] = []
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
                    lastUpdatedAt: Date()
                )
                try docRef.setData(from: newProfile)
                self.currentUserProfile = newProfile
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
        myParties = []
        profilesCache.removeAll()
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
    func updateMyStatus(status: String, todayFocusTime: TimeInterval) {
        guard let uid = UserDefaults.standard.string(forKey: "userUID") else { return }
        let data: [String: Any] = [
            "status": status,
            "todayFocusTime": todayFocusTime,
            "lastUpdatedAt": FieldValue.serverTimestamp()
        ]
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
    
    // MARK: - Utilities
    private func generatePartyCode() -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).compactMap { _ in letters.randomElement() })
    }
}
