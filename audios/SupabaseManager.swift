import Foundation
import Supabase

class SupabaseManager {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    // Your Supabase project configuration
    private let supabaseURL = "https://wfxlihpxeeyjlllvoypa.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndmeGxpaHB4ZWV5amxsbHZveXBhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTY3MDM0ODUsImV4cCI6MjA3MjI3OTQ4NX0.wubM4vjBuHxCHqm176fpieSVax0AofdzLYpwcFaSf9k"
    
    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: supabaseURL)!,
            supabaseKey: supabaseAnonKey
        )
    }
    
    // 获取或创建用户
    func getOrCreateUser(deviceId: String) async throws -> UUID {
        do {
            // First try to find existing user
            let response: [User] = try await client
                .from("users")
                .select()
                .eq("device_id", value: deviceId)
                .execute()
                .value
            
            if let existingUser = response.first, let userId = existingUser.id {
                return userId
            }
            
            // Create new user
            let newUser = User(device_id: deviceId)
            let insertResponse: [User] = try await client
                .from("users")
                .insert(newUser)
                .select()
                .execute()
                .value
            
            guard let newUser = insertResponse.first, let newUserId = newUser.id else {
                throw NSError(domain: "SupabaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create user"])
            }
            return newUserId
            
        } catch {
            print("❌ Error getting or creating user: \(error)")
            throw error
        }
    }
    
    // 获取用户的所有卡片
    func fetchCards(for userId: UUID) async throws -> [Card] {
        return []
    }
    
    // 添加新卡片
    func addCard(userId: UUID, title: String, content: [String: Any], index: Int) async throws {
        // Stub implementation
    }
    
    // 实时订阅新卡片
    func subscribeToCards(userId: UUID, onNewCard: @escaping (Card) -> Void) {
        // Stub implementation
    }
    
    // Upload audio recording to Supabase Storage
    func uploadAudioRecording(userId: UUID, fileURL: URL, recording: AudioRecording) async throws -> String {
        do {
            let fileName = "recording_\(recording.id.uuidString).m4a"
            
            // Read audio file data
            let audioData = try Data(contentsOf: fileURL)
            
            // Create file path with user ID for organization
            let filePath = "\(userId.uuidString)/\(fileName)"
            
            print("📤 Uploading audio file: \(fileName)")
            print("📂 From local path: \(fileURL.path)")
            
            // Upload to Supabase Storage (using new API)
            try await client.storage
                .from("audio-files")
                .upload(
                    filePath,
                    data: audioData,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: "audio/mp4",
                        upsert: false
                    )
                )
            
            // Get signed URL (for private bucket) - expires in 1 hour
            let signedURL = try await client.storage
                .from("audio-files")
                .createSignedURL(path: filePath, expiresIn: 3600)
            
            print("✅ Audio uploaded successfully: \(signedURL)")
            return signedURL.absoluteString
            
        } catch {
            print("❌ Upload failed: \(error)")
            throw error
        }
    }
    
    // 保存录音记录到数据库 - returns the created record's ID
    func saveAudioRecording(userId: UUID, recording: AudioRecording, fileURL: String) async throws -> UUID? {
        do {
            let audioRecord = AudioRecord(
                user_id: userId,
                audio_url: fileURL,
                duration: Int(recording.duration),
                file_size: nil
            )
            
            // Insert and get the created record back
            let insertedRecords: [AudioRecord] = try await client
                .from("audio_records")
                .insert(audioRecord)
                .select()
                .execute()
                .value
            
            let recordId = insertedRecords.first?.id
            print("✅ Audio record saved to database with ID: \(String(describing: recordId))")
            return recordId
            
        } catch {
            print("❌ Failed to save audio record: \(error)")
            throw error
        }
    }
    
    // 获取用户的所有录音记录
    func fetchAudioRecordings(userId: UUID) async throws -> [AudioRecord] {
        do {
            let recordings: [AudioRecord] = try await client
                .from("audio_records")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value
            
            print("✅ Fetched \(recordings.count) audio recordings")
            return recordings
            
        } catch {
            print("❌ Failed to fetch audio recordings: \(error)")
            throw error
        }
    }
    
    // 删除录音记录
    func deleteAudioRecording(userId: UUID, recording: AudioRecording) async throws {
        do {
            print("🗑️ Attempting to delete recording - supabaseId: \(String(describing: recording.supabaseId)), remoteURL: \(String(describing: recording.remoteURL))")
            
            // Use supabaseId if available, otherwise fallback to URL matching
            let recordToDelete: AudioRecord
            
            if let supabaseId = recording.supabaseId {
                print("🔍 Looking up by supabaseId: \(supabaseId)")
                // Direct lookup by supabaseId (most reliable)
                let records: [AudioRecord] = try await client
                    .from("audio_records")
                    .select()
                    .eq("id", value: supabaseId)
                    .execute()
                    .value
                
                guard let record = records.first else {
                    print("⚠️ Recording not found in database by ID: \(supabaseId)")
                    return
                }
                recordToDelete = record
                print("✅ Found record to delete by ID")
            } else {
                // Fallback: match by remoteURL
                guard let remoteURL = recording.remoteURL else {
                    print("⚠️ No supabaseId or remoteURL available for deletion")
                    return
                }
                print("🔍 Fallback: Looking up by remoteURL")
                
                let records: [AudioRecord] = try await client
                    .from("audio_records")
                    .select()
                    .eq("user_id", value: userId)
                    .execute()
                    .value
                
                guard let record = records.first(where: { $0.audio_url == remoteURL }) else {
                    print("⚠️ Recording not found in database by URL")
                    return
                }
                recordToDelete = record
            }
            
            // Delete from database FIRST (most important)
            print("🗑️ Attempting database deletion for record ID: \(String(describing: recordToDelete.id))")
            let deleteResponse = try await client
                .from("audio_records")
                .delete()
                .eq("id", value: recordToDelete.id!)  // Use ID instead of URL+user_id
                .execute()
            
            print("✅ Database deletion response: \(deleteResponse)")
            print("✅ Deleted recording from database")
            
            // Then try to delete from storage (less critical - can be cleaned up later)
            if let url = URL(string: recordToDelete.audio_url),
               let pathComponent = url.path.components(separatedBy: "/audio-files/").last {
                
                do {
                    // Delete from storage
                    try await client.storage
                        .from("audio-files")
                        .remove(paths: [pathComponent])
                    
                    print("✅ Deleted file from storage: \(pathComponent)")
                } catch {
                    // Storage deletion failed, but database record is already deleted
                    // File will be orphaned but won't show in app
                    print("⚠️ Failed to delete storage file (will be orphaned): \(error)")
                }
            }
            
        } catch {
            print("❌ Failed to delete recording: \(error)")
            throw error
        }
    }
    
    // 更新音频记录的AI分析结果
    func updateAudioRecordingWithAI(audioUrl: String, summary: String, transcription: String, audioType: String, confidence: Double) async throws {
        do {
            print("🔄 Updating AI analysis for audio URL: \(audioUrl)")
            
            // 🔧 CRITICAL FIX: Use file path pattern matching instead of exact URL match
            guard let url = URL(string: audioUrl),
                  let pathComponent = url.path.components(separatedBy: "/audio-files/").last else {
                throw NSError(domain: "SupabaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio URL format"])
            }
            
            print("🔍 Searching for record with file path: \(pathComponent)")
            
            // Find the correct record using file path pattern with retry
            var records: [AudioRecord] = []
            var retryCount = 0
            let maxRetries = 3
            
            while retryCount < maxRetries {
                do {
                    records = try await client
                        .from("audio_records")
                        .select()
                        .like("audio_url", pattern: "%\(pathComponent)%")
                        .execute()
                        .value
                    break // Success, exit retry loop
                } catch {
                    retryCount += 1
                    print("⚠️ Database query attempt \(retryCount) failed: \(error)")
                    if retryCount < maxRetries {
                        print("🔄 Retrying in 2 seconds...")
                        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
                    } else {
                        throw error // Max retries reached
                    }
                }
            }
            
            guard let targetRecord = records.first else {
                print("❌ No record found for file path: \(pathComponent)")
                throw NSError(domain: "SupabaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No matching record found"])
            }
            
            print("🎯 Found target record ID: \(String(describing: targetRecord.id))")
            
            // Create a proper update object
            struct AudioRecordUpdate: Encodable {
                let summary: String
                let transcription: String
                let audio_type: String
                let confidence: Double
                let analysis_completed_at: String
            }
            
            let updateData = AudioRecordUpdate(
                summary: summary,
                transcription: transcription,
                audio_type: audioType,
                confidence: confidence,
                analysis_completed_at: ISO8601DateFormatter().string(from: Date())
            )
            
            // Update by record ID instead of URL with retry
            retryCount = 0
            while retryCount < maxRetries {
                do {
                    _ = try await client
                        .from("audio_records")
                        .update(updateData)
                        .eq("id", value: targetRecord.id!)
                        .execute()
                    break // Success
                } catch {
                    retryCount += 1
                    print("⚠️ Database update attempt \(retryCount) failed: \(error)")
                    if retryCount < maxRetries {
                        print("🔄 Retrying update in 2 seconds...")
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    } else {
                        throw error // Max retries reached
                    }
                }
            }
            
            print("✅ AI analysis saved to Supabase for record ID: \(String(describing: targetRecord.id))")
            print("📝 Summary: \(summary)")
            print("📝 Transcription: \(transcription)")
            print("🎯 Audio type: \(audioType) | Confidence: \(confidence)")
            
            // Also save to cache for immediate display
            AudioAnalysisCache.shared.saveAnalysis(
                audioUrl: audioUrl,
                summary: summary,
                transcription: transcription,
                audioType: audioType
            )
        } catch {
            print("❌ Failed to update AI analysis in Supabase: \(error)")
            // Still save to cache even if database update fails
            AudioAnalysisCache.shared.saveAnalysis(
                audioUrl: audioUrl,
                summary: summary,
                transcription: transcription,
                audioType: audioType
            )
            throw error
        }
    }
    
    // 根据音频URL查找记录ID（用于AI回调）
    func findRecordByAudioUrl(_ audioUrl: String) async throws -> AudioRecord? {
        do {
            print("🔍 Searching for record with audio_url: \(audioUrl)")
            
            let records: [AudioRecord] = try await client
                .from("audio_records")
                .select()
                .eq("audio_url", value: audioUrl)
                .execute()
                .value
            
            print("📊 Found \(records.count) records for URL")
            if let record = records.first {
                print("✅ Returning record with ID: \(String(describing: record.id))")
                print("📄 Record summary: '\(record.summary ?? "none")'")
                print("📄 Record transcription: '\(record.transcription ?? "none")'")
            } else {
                print("❌ No record found for URL: \(audioUrl)")
            }
            
            return records.first
        } catch {
            print("❌ Failed to find record by audio URL: \(error)")
            throw error
        }
    }
    
    // Generate fresh signed URL for audio playback
    func getFreshAudioURL(for recording: AudioRecording) async throws -> String {
        guard let remoteURL = recording.remoteURL else {
            throw NSError(domain: "SupabaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No remote URL available"])
        }
        
        // Extract file path from existing URL
        guard let url = URL(string: remoteURL),
              let pathComponent = url.path.components(separatedBy: "/audio-files/").last else {
            throw NSError(domain: "SupabaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL format"])
        }
        
        // Generate fresh signed URL (1 hour expiration)
        let freshSignedURL = try await client.storage
            .from("audio-files")
            .createSignedURL(path: pathComponent, expiresIn: 3600)
        
        return freshSignedURL.absoluteString
    }
}

// Database Models
struct User: Codable {
    let id: UUID?
    let device_id: String
    let username: String?
    let created_at: Date?
    
    init(device_id: String, username: String? = nil) {
        self.id = nil
        self.device_id = device_id
        self.username = username
        self.created_at = nil
    }
}

struct AudioRecord: Codable, Identifiable {
    let id: UUID?
    let user_id: UUID
    let audio_url: String
    let duration: Int?
    let file_size: Int?
    let created_at: Date?
    // AI analysis fields
    var summary: String?
    var transcription: String?
    var audio_type: String?
    var confidence: Double?
    var analysis_completed_at: Date?
    
    init(user_id: UUID, audio_url: String, duration: Int?, file_size: Int?) {
        self.id = nil
        self.user_id = user_id
        self.audio_url = audio_url
        self.duration = duration
        self.file_size = file_size
        self.created_at = nil
        self.summary = nil
        self.transcription = nil
        self.audio_type = nil
        self.confidence = nil
        self.analysis_completed_at = nil
    }
}

// Simple in-memory AI analysis storage (until database schema is updated)
class AudioAnalysisCache {
    static let shared = AudioAnalysisCache()
    private var analysisCache: [String: (summary: String, transcription: String, audioType: String)] = [:]
    
    func saveAnalysis(audioUrl: String, summary: String, transcription: String, audioType: String) {
        analysisCache[audioUrl] = (summary, transcription, audioType)
    }
    
    func getAnalysis(audioUrl: String) -> (summary: String, transcription: String, audioType: String)? {
        return analysisCache[audioUrl]
    }
}

// 卡片数据模型
struct Card {
    let title: String
    let index: Int
    let content: Any?
}