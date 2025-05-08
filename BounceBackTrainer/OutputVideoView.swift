// OutputVideoView.swift
import SwiftUI
import AVKit

struct OutputVideoView: View {
    let url: URL

    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
            .frame(minWidth: 800, minHeight: 600) // Initial size
    }
}
