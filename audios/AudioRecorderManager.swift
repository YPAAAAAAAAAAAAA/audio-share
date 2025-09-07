import Foundation
import AVFoundation
import UIKit

class AudioRecorderManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioRecordings: [AudioRecording] = []
    @Published var isUploading = false
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingSession: AVAudioSession = AVAudioSession.sharedInstance()
    private var currentRecordingURL: URL?
    
    override init() {
        super.init()
        // Only setup recording session if not in preview mode
        #if !DEBUG || !targetEnvironment(simulator)
        setupRecordingSession()
        #else
        if !ProcessInfo.processInfo.environment.keys.contains("XCODE_RUNNING_FOR_PREVIEWS") {
            setupRecordingSession()
        }
        #endif
    }
    
    private func setupRecordingSession() {
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try recordingSession.setActive(true)
            recordingSession.requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    if !allowed {
                        print("Recording permission denied")
                    } else {
                        print("Recording permission granted")
                    }
                }
            }
        } catch {
            print("Failed to set up recording session: \(error)")
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Don't start recording in preview mode
        if ProcessInfo.processInfo.environment.keys.contains("XCODE_RUNNING_FOR_PREVIEWS") {
            print("Recording disabled in preview mode")
            return
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            
            currentRecordingURL = audioFilename
            isRecording = true
            recordingDuration = 0
            
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.recordingDuration += 0.1
            }
            
        } catch {
            print("Could not start recording: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        
        // Create new AudioRecording
        let duration = Int(recordingDuration)
        let title = generateTitle(for: duration)
        let newRecording = AudioRecording(
            duration: duration,
            title: title,
            timestamp: Date()
        )
        
        audioRecordings.insert(newRecording, at: 0)
        
        // Upload to Supabase if we have the file URL
        if let fileURL = currentRecordingURL {
            uploadRecording(newRecording, fileURL: fileURL)
        }
        
        currentRecordingURL = nil
    }
    
    private func uploadRecording(_ recording: AudioRecording, fileURL: URL) {
        Task {
            do {
                isUploading = true
                
                // Get user ID (you might want to pass this in or get it from elsewhere)
                let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
                let userId = try await SupabaseManager.shared.getOrCreateUser(deviceId: deviceId)
                
                // Upload file to Supabase storage
                let uploadedURL = try await SupabaseManager.shared.uploadAudioRecording(
                    userId: userId,
                    fileURL: fileURL,
                    recording: recording
                )
                
                // Save recording metadata to database
                _ = try await SupabaseManager.shared.saveAudioRecording(
                    userId: userId,
                    recording: recording,
                    fileURL: uploadedURL
                )
                
                await MainActor.run {
                    isUploading = false
                    print("Successfully uploaded recording: \(recording.title)")
                }
                
            } catch {
                await MainActor.run {
                    isUploading = false
                    print("Failed to upload recording: \(error)")
                }
            }
        }
    }
    
    private func generateTitle(for duration: Int) -> String {
        let titles = ["语音备忘", "录音记录", "会议记录", "想法记录", "学习笔记", "待办事项"]
        return titles.randomElement() ?? "录音"
    }
}

extension AudioRecorderManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording failed")
        }
    }
}