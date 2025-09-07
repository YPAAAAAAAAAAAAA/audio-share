import SwiftUI

struct SimpleTestView: View {
    @State private var recordings: [String] = []
    
    var body: some View {
        TabView {
            // Test Record Tab
            VStack {
                Text("Recording Test")
                    .font(.title)
                    .padding()
                
                Button("Add Test Recording") {
                    recordings.append("Test Recording \(recordings.count + 1)")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                Spacer()
            }
            .tabItem {
                Image(systemName: "mic")
                Text("Record")
            }
            
            // Test Playback Tab
            VStack {
                Text("Playback Test")
                    .font(.title)
                    .padding()
                
                List(recordings, id: \.self) { recording in
                    Text(recording)
                }
                
                if recordings.isEmpty {
                    Text("No recordings yet")
                        .foregroundColor(.gray)
                        .padding()
                }
                
                Spacer()
            }
            .tabItem {
                Image(systemName: "play.circle")
                Text("Playback")
            }
        }
    }
}

#Preview {
    SimpleTestView()
}