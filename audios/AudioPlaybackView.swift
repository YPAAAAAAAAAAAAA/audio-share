import SwiftUI
import AVFoundation
import UIKit

struct AudioPlaybackView: View {
    @State private var recordings: [AudioRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var currentlyPlayingId: UUID?
    @State private var userId: UUID?
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading recordings...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if recordings.isEmpty {
                    VStack {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No recordings yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Make some recordings first!")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(recordings, id: \.id) { recording in
                        AudioRecordingRow(
                            recording: recording,
                            isPlaying: currentlyPlayingId == recording.id,
                            onPlayTapped: {
                                Task {
                                    await playRecording(recording)
                                }
                            },
                            onStopTapped: {
                                stopPlayback()
                            }
                        )
                    }
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle("My Recordings")
            .onAppear {
                Task {
                    await loadRecordings()
                }
            }
            .refreshable {
                Task {
                    await loadRecordings()
                }
            }
        }
    }
    
    private func loadRecordings() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Get or create user first
            let deviceId = await getDeviceId()
            let fetchedUserId = try await SupabaseManager.shared.getOrCreateUser(deviceId: deviceId)
            self.userId = fetchedUserId
            
            // Fetch recordings
            recordings = try await SupabaseManager.shared.fetchAudioRecordings(userId: fetchedUserId)
        } catch {
            errorMessage = "Failed to load recordings: \(error.localizedDescription)"
            print("❌ Error loading recordings: \(error)")
        }
        
        isLoading = false
    }
    
    private func playRecording(_ recording: AudioRecord) async {
        do {
            // Stop current playback
            stopPlayback()
            
            // Download audio from signed URL
            guard let url = URL(string: recording.audio_url) else {
                errorMessage = "Invalid audio URL"
                return
            }
            
            // Download audio data
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Create audio player
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            currentlyPlayingId = recording.id
            
            print("▶️ Playing recording: \(recording.id?.uuidString ?? "unknown")")
            
        } catch {
            errorMessage = "Failed to play recording: \(error.localizedDescription)"
            print("❌ Error playing recording: \(error)")
        }
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentlyPlayingId = nil
    }
    
    private func getDeviceId() async -> String {
        #if targetEnvironment(simulator)
        return "simulator-device-id"
        #else
        if let deviceId = await UIDevice.current.identifierForVendor?.uuidString {
            return deviceId
        }
        return "unknown-device"
        #endif
    }
}

struct AudioRecordingRow: View {
    let recording: AudioRecord
    let isPlaying: Bool
    let onPlayTapped: () -> Void
    let onStopTapped: () -> Void
    
    var body: some View {
        HStack {
            Button(action: isPlaying ? onStopTapped : onPlayTapped) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(isPlaying ? .red : .blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Recording \(formattedDate)")
                    .font(.headline)
                
                if let duration = recording.duration {
                    Text("Duration: \(duration)s")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Text("Created: \(recording.created_at?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var formattedDate: String {
        if let createdAt = recording.created_at {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM dd, HH:mm"
            return formatter.string(from: createdAt)
        }
        return "Unknown"
    }
}

#Preview {
    AudioPlaybackView()
}