import SwiftUI
import AVKit

struct ContentView: View {
    @State private var inputURL: URL?
    @State private var outputURL: URL?
    @State private var showVideoPlayer = false
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 20) {
            Text("🎯 Bounce Back Trainer").font(.title2)

            Button("📂 Upload Video") {
                showPicker = true
            }

            Button("🚀 Analyze Video") {
                guard let input = inputURL else { return }

                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent("analyzed_output.mp4")

                if input.startAccessingSecurityScopedResource() {
                    defer { input.stopAccessingSecurityScopedResource() }

                    print("Analyzing: \(input.path)")
                    OpenCVWrapper.analyzeVideo(input.path, outputPath: output.path)
                    outputURL = output
                } else {
                    print("Failed to access security-scoped resource")
                }
            }
            .disabled(inputURL == nil)


            Button("🎬 View Output Video") {
                if let url = outputURL {
                    openResizableVideoWindow(for: url)
                }
            }
            .disabled(outputURL == nil)
        }
        .padding()
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                inputURL = urls.first
            case .failure(let error):
                print("File selection error: \(error)")
            }
        }
        
    }
    func openResizableVideoWindow(for url: URL) {
        let view = OutputVideoView(url: url)
        let hosting = NSHostingController(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "Analyzed Output"
        window.makeKeyAndOrderFront(nil)
    }
}
