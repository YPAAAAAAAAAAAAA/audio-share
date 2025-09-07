// EXAMPLE: How to update SupabaseManager.swift after adding package
import Foundation
import Supabase

class SupabaseManager {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    // 🔥 REPLACE THESE WITH YOUR ACTUAL VALUES FROM SUPABASE DASHBOARD
    private let supabaseURL = "https://YOUR-PROJECT-ID.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." // Your actual anon key
    
    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: supabaseURL)!,
            supabaseKey: supabaseAnonKey
        )
    }
    
    // Get or create user based on device ID
    func getOrCreateUser(deviceId: String) async throws -> UUID {
        // First try to find existing user
        let users: [DatabaseUser] = try await client.database
            .from("users")
            .select()
            .eq("device_id", value: deviceId)
            .execute()
            .value
        
        if let existingUser = users.first {
            return existingUser.id
        }
        
        // Create new user if not found
        let newUser = DatabaseUser(device_id: deviceId)
        let createdUsers: [DatabaseUser] = try await client.database
            .from("users")
            .insert(newUser)
            .execute()
            .value
        
        return createdUsers.first!.id
    }
    
    // REAL Supabase Storage Upload
    func uploadAudioRecording(userId: UUID, fileURL: URL, recording: AudioRecording) async throws -> String {
        do {
            // Read audio file data
            let audioData = try Data(contentsOf: fileURL)
            
            // Create file path with user ID for organization
            let fileName = "recording_\(recording.id.uuidString).m4a"
            let filePath = "\(userId.uuidString)/\(fileName)"
            
            print("📤 Uploading audio file: \(filePath)")
            print("📂 File size: \(audioData.count) bytes")
            
            // Upload to Supabase Storage
            try await client.storage
                .from("recordings")
                .upload(
                    path: filePath,
                    file: audioData,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: "audio/mp4",
                        upsert: false
                    )
                )
            
            // Get public URL
            let publicURL = try client.storage
                .from("recordings")
                .getPublicURL(path: filePath)
            
            print("✅ Audio uploaded successfully: \(publicURL)")
            return publicURL.absoluteString
            
        } catch {
            print("❌ Upload failed: \(error)")
            throw error
        }
    }
    
    // Save recording metadata to database
    func saveAudioRecording(userId: UUID, recording: AudioRecording, fileURL: String) async throws {
        let dbRecording = DatabaseRecording(
            id: recording.id,
            user_id: userId,
            title: recording.title,
            duration: recording.duration,
            file_url: fileURL,
            created_at: recording.timestamp
        )
        
        try await client.database
            .from("recordings")
            .insert(dbRecording)
            .execute()
        
        print("✅ Recording metadata saved to database")
    }
    
    // Fetch user's recordings from database
    func fetchRecordings(for userId: UUID) async throws -> [AudioRecording] {
        let dbRecordings: [DatabaseRecording] = try await client.database
            .from("recordings")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        return dbRecordings.map { dbRecording in
            AudioRecording(
                duration: dbRecording.duration,
                title: dbRecording.title,
                timestamp: dbRecording.created_at
            )
        }
    }
}

// Database Models
struct DatabaseUser: Codable {
    let id: UUID = UUID()
    let device_id: String
    let created_at: Date = Date()
}

struct DatabaseRecording: Codable {
    let id: UUID
    let user_id: UUID
    let title: String
    let duration: Int
    let file_url: String
    let created_at: Date
}