import Foundation
import Combine
import FirebaseCore
import FirebaseFirestore

// MARK: - User Profile Model
struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String?
    var displayName: String
    var inviteCode: String
    var status: String // "tracking", "idle", "offline"
    var todayFocusTime: TimeInterval
    var friends: [String]
    var lastUpdatedAt: Date
}

// MARK: - Firebase Manager
final class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    
    // Lifecycle
    deinit {
        stopListeningToFriends()
    }
    
    // Published properties for SwiftUI bindings
    @Published var currentUserProfile: UserProfile?
    @Published var friendsProfiles: [UserProfile] = []
    @Published var debugError: String = ""
    
    // MARK: - Private Properties
    private var db = Firestore.firestore()
    private var friendsListeners: [ListenerRegistration] = []
    private var myProfileListener: ListenerRegistration?
    private var profilesCache: [String: UserProfile] = [:]
    private var isListeningToFriendsView = false
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
                    inviteCode: generateInviteCode(),
                    status: "offline",
                    todayFocusTime: 0,
                    friends: [],
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
                // Decode profile and update UI on main thread
                DispatchQueue.main.async {
                    do {
                        self.currentUserProfile = try document.data(as: UserProfile.self)
                        if self.isListeningToFriendsView {
                            self.listenToFriends(friendUIDs: self.currentUserProfile?.friends ?? [])
                        }
                    } catch {
                        print("Error decoding my profile: \(error)")
                    }
                }
            }
    }
    
    // MARK: - Friend List Listener
    private func listenToFriends(friendUIDs: [String]) {
        // Clean up any existing listeners and cache
        friendsListeners.forEach { $0.remove() }
        friendsListeners.removeAll()
        profilesCache.removeAll()
        
        guard !friendUIDs.isEmpty else {
            self.friendsProfiles = []
            return
        }
        
        // Firestore "in" queries support up to 10 IDs; split larger sets into chunks.
        let chunks = stride(from: 0, to: friendUIDs.count, by: 10).map {
            Array(friendUIDs[$0..<min($0 + 10, friendUIDs.count)])
        }
        
        for chunk in chunks {
            let listener = db.collection(usersCollection)
                .whereField(FieldPath.documentID(), in: chunk)
                .addSnapshotListener { [weak self] querySnapshot, error in
                    guard let self = self, let documents = querySnapshot?.documents else { return }
                    for doc in documents {
                        if let profile = try? doc.data(as: UserProfile.self), let uid = profile.id {
                            self.profilesCache[uid] = profile
                        }
                    }
                    DispatchQueue.main.async {
                        self.friendsProfiles = Array(self.profilesCache.values)
                            .sorted { $0.displayName < $1.displayName }
                    }
                }
            friendsListeners.append(listener)
        }
    }
    
    /// Starts listening to friends' status updates. Should be called when the SocialView appears.
    func startListeningToFriends() {
        guard !isListeningToFriendsView else { return }
        isListeningToFriendsView = true
        if let uids = currentUserProfile?.friends, !uids.isEmpty {
            listenToFriends(friendUIDs: uids)
        }
    }
    
    /// Stops listening to friends. Called when the SocialView disappears or on deinit.
    func stopListeningToFriends() {
        guard isListeningToFriendsView else { return }
        isListeningToFriendsView = false
        friendsListeners.forEach { $0.remove() }
        friendsListeners.removeAll()
        profilesCache.removeAll()
        friendsProfiles = []
    }
    
    // MARK: - Status Updates
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
    
    // MARK: - Profile Updates
    func updateDisplayName(_ name: String) {
        guard let uid = UserDefaults.standard.string(forKey: "userUID") else { return }
        db.collection(usersCollection).document(uid).updateData(["displayName": name])
    }
    
    // MARK: - Friend Management
    func addFriend(by inviteCode: String) async -> Bool {
        guard let myUid = UserDefaults.standard.string(forKey: "userUID") else { return false }
        do {
            let snapshot = try await db.collection(usersCollection)
                .whereField("inviteCode", isEqualTo: inviteCode.uppercased())
                .getDocuments()
            guard let friendDoc = snapshot.documents.first else { return false }
            let friendUid = friendDoc.documentID
            if friendUid == myUid { return false } // prevent adding self
            try await db.collection(usersCollection).document(myUid).updateData([
                "friends": FieldValue.arrayUnion([friendUid])
            ])
            return true
        } catch {
            print("Error adding friend: \(error)")
            return false
        }
    }
    
    // MARK: - Utilities
    private func generateInviteCode() -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).compactMap { _ in letters.randomElement() })
    }
}
