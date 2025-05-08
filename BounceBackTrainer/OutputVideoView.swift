import SwiftUI
import AVKit

struct OutputVideoView: View {
    let url: URL
    @State private var player: AVPlayer? = nil

    var body: some View {
        VideoPlayer(player: player)
            .frame(minWidth: 800, minHeight: 600)
            .onAppear {
                player = AVPlayer(url: url)
                player?.play() // Optional: auto-play
            }
            .onDisappear {
                player?.pause()
                player = nil // Clean up
            }
    }
}
