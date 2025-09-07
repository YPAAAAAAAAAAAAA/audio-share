import SwiftUI

struct SafeContentView2: View {
    @State private var recordings: [String] = []
    @State private var isRecording = false
    
    var body: some View {
        TabView {
            // Recording Tab - Simplified
            recordingView
                .tabItem {
                    Image(systemName: "mic")
                    Text("Record")
                }
            
            // Playback Tab - Simplified  
            playbackView
                .tabItem {
                    Image(systemName: "play.circle")
                    Text("Playback")
                }
        }
    }
    
    private var recordingView: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Text("Recording Interface")
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
                
                Text(isRecording ? "Recording..." : "Tap to Record")
                    .font(.headline)
                
                // Show fake recordings
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
            Text("Playback Interface")
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
                            // Simulate play
                            print("Playing: \(recording)")
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
    
    private func startRecording() {
        isRecording = true
        
        // Simulate recording for 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if isRecording {
                stopRecording()
            }
        }
    }
    
    private func stopRecording() {
        isRecording = false
        recordings.append("Recording \(recordings.count + 1) - \(Date().formatted(date: .omitted, time: .shortened))")
    }
}

#Preview {
    SafeContentView2()
}