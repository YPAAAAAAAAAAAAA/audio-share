import SwiftUI
import AVFoundation
import UIKit

struct AudioOnlyTest: View {
    @State private var recordings: [String] = []
    @State private var audioRecorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var currentRecordingURL: URL?
    
    var body: some View {
        TabView {
            // Recording Tab with AVFoundation
            recordingView
                .tabItem {
                    Image(systemName: "mic")
                    Text("Record")
                }
            
            // Simple Playback Tab
            playbackView
                .tabItem {
                    Image(systemName: "play.circle")
                    Text("Playback")
                }
        }
        .onAppear {
            setupAudioSession()
        }
    }
    
    private var recordingView: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Text("Audio Recording Test")
                    .font(.title)
                
                Button(action: {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color.black)
                            .frame(width: 80, height: 80)
                        
                        if isRecording {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 20, height: 20)
                                .cornerRadius(4)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }
                }
                
                if isRecording {
                    Text("Recording: \(formatTime(recordingTime))")
                        .font(.headline)
                        .foregroundColor(.red)
                } else {
                    Text("Tap to Record")
                        .font(.headline)
                }
                
                // Show recordings
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(recordings, id: \.self) { recording in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 60)
                                .overlay(
                                    Text(recording)
                                        .font(.body)
                                )
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
    }
    
    private var playbackView: some View {
        VStack {
            Text("Local Recordings")
                .font(.title)
                .padding()
            
            if recordings.isEmpty {
                VStack {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No recordings yet")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(recordings, id: \.self) { recording in
                    HStack {
                        Button(action: {
                            print("Would play: \(recording)")
                        }) {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        
                        Text(recording)
                            .font(.body)
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // MARK: - Audio Functions
    
    private func setupAudioSession() {
        #if targetEnvironment(simulator)
        return
        #endif
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            session.requestRecordPermission { granted in
                if !granted {
                    print("Microphone permission denied")
                }
            }
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    private func startRecording() {
        #if targetEnvironment(simulator)
        // Simulator fake recording
        isRecording = true
        recordingTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
        }
        return
        #endif
        
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording_\(UUID().uuidString).m4a")
        currentRecordingURL = audioFilename
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            isRecording = true
            recordingTime = 0
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingTime += 0.1
            }
        } catch {
            print("Could not start recording: \(error)")
        }
    }
    
    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        
        #if targetEnvironment(simulator)
        isRecording = false
        recordings.append("Simulated Recording \(recordings.count + 1) - \(formatTime(recordingTime))")
        return
        #endif
        
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        
        // Add to local list (no Supabase)
        recordings.append("Recording \(recordings.count + 1) - \(formatTime(recordingTime))")
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, milliseconds)
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}

#Preview {
    AudioOnlyTest()
}