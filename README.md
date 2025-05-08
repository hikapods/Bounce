# Bounce Back Trainer

Bounce Back Trainer is a macOS SwiftUI app that analyzes soccer training videos using computer vision. It detects the ball's impact relative to a colored target and provides visual feedback to improve shot accuracy.

## Features

- Upload and analyze pre-recorded `.mp4` videos
- Detects orange target rectangle and red bullseye using OpenCV
- Locates motion-based ball impacts
- Displays real-time feedback like "Kick lower!" or "Great shot!"
- Outputs an annotated video with overlays

## Tech Stack

- SwiftUI + AVKit (macOS)
- OpenCV (via Objective-C++ bridge)
- Xcode 15+

## Usage

1. Run the app.
2. Click **Upload Video** and select a `.mp4` file.
3. Click **Analyze Video** to process it.
4. Click **View Output Video** to see results.


