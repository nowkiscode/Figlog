import Foundation
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String?
    var displayName: String
    var inviteCode: String
    var status: String // "tracking", "idle", "offline"
    var todayFocusTime: TimeInterval
    var friends: [String]
    var lastUpdatedAt: Date
}

@MainActor
final class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    
    @Published var currentUserProfile: UserProfile?
    @Published var friendsProfiles: [UserProfile] = []
    @Published var debugError: String = ""
    
    private var db = Firestore.firestore()
    private var auth = Auth.auth()
    private var friendsListener: ListenerRegistration?
    private var myProfileListener: ListenerRegistration?
    
    private let usersCollection = "users"
    
    private init() {}
    
    // 1. 익명 로그인 및 내 프로필 초기화
    func signInAnonymously() async {
        do {
            let authResult = try await auth.signInAnonymously()
            let user = authResult.user
            print("Firebase signed in: \(user.uid)")
            
            await setupUserProfile(uid: user.uid)
            listenToMyProfile(uid: user.uid)
        } catch {
            let errorMsg = "Auth Error: \(error.localizedDescription)"
            print(errorMsg)
            self.debugError = errorMsg
        }
    }
    
    private func setupUserProfile(uid: String) async {
        let docRef = db.collection(usersCollection).document(uid)
        
        do {
            let document = try await docRef.getDocument()
            if !document.exists {
                // 첫 가입 시 초기 프로필 생성
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
    
    private func listenToMyProfile(uid: String) {
        myProfileListener?.remove()
        myProfileListener = db.collection(usersCollection).document(uid)
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self, let document = documentSnapshot else { return }
                do {
                    self.currentUserProfile = try document.data(as: UserProfile.self)
                    self.listenToFriends(friendUIDs: self.currentUserProfile?.friends ?? [])
                } catch {
                    print("Error decoding my profile: \(error)")
                }
            }
    }
    
    // 2. 실시간 내 상태 업데이트 (FocusTracker에서 호출)
    func updateMyStatus(status: String, todayFocusTime: TimeInterval) {
        guard let uid = auth.currentUser?.uid else { return }
        
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
    
    // 닉네임 변경
    func updateDisplayName(_ name: String) {
        guard let uid = auth.currentUser?.uid else { return }
        db.collection(usersCollection).document(uid).updateData(["displayName": name])
    }
    
    // 3. 친구 추가 로직 (초대 코드 입력)
    func addFriend(by inviteCode: String) async -> Bool {
        guard let myUid = auth.currentUser?.uid else { return false }
        
        do {
            // 초대 코드로 유저 찾기
            let snapshot = try await db.collection(usersCollection)
                .whereField("inviteCode", isEqualTo: inviteCode.uppercased())
                .getDocuments()
            
            guard let friendDoc = snapshot.documents.first else {
                print("Friend not found with code: \(inviteCode)")
                return false
            }
            
            let friendUid = friendDoc.documentID
            if friendUid == myUid { return false } // 나 자신 추가 방지
            
            // 내 친구 목록에 추가
            try await db.collection(usersCollection).document(myUid).updateData([
                "friends": FieldValue.arrayUnion([friendUid])
            ])
            return true
            
        } catch {
            print("Error adding friend: \(error)")
            return false
        }
    }
    
    // 4. 친구들 실시간 상태 구독
    private func listenToFriends(friendUIDs: [String]) {
        friendsListener?.remove()
        
        guard !friendUIDs.isEmpty else {
            self.friendsProfiles = []
            return
        }
        
        // 최대 10명까지만 in 쿼리 가능 (Firestore 제한)
        let chunkedUIDs = Array(friendUIDs.prefix(10))
        
        friendsListener = db.collection(usersCollection)
            .whereField(FieldPath.documentID(), in: chunkedUIDs)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self, let documents = querySnapshot?.documents else { return }
                
                self.friendsProfiles = documents.compactMap { doc -> UserProfile? in
                    try? doc.data(as: UserProfile.self)
                }
            }
    }
    
    // 유틸: 랜덤 초대코드 생성
    private func generateInviteCode() -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in letters.randomElement()! })
    }
}
