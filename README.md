# BounceBackTrainer

BounceBackTrainer is an advanced iOS application designed to help athletes improve their ball control and accuracy through real-time computer vision analysis. The app uses OpenCV and sophisticated detection algorithms to provide instant feedback on ball trajectories, target hits, and training performance.

## 🎯 Features

### Real-time Computer Vision Analysis
- **Live Camera Mode**: Real-time video processing with instant feedback
- **Video Recording & Analysis**: Record training sessions and analyze them later
- **Multiple Detection Modes**: Traditional and FFT-based ball detection algorithms
- **Target Detection**: Automatic detection and tracking of red bullseye targets
- **Pink Tape Boundary Detection**: Identifies fluorescent pink tape markers for goal area definition

### Advanced Ball Detection
- **FFT-based Detection**: Fast Fourier Transform algorithm for enhanced ball tracking
- **Traditional Detection**: Fallback detection using contour analysis and color filtering
- **Temporal Consistency**: Multi-frame validation to reduce false positives
- **Confidence Scoring**: Real-time confidence metrics for detection accuracy
- **Motion Tracking**: Sophisticated motion detection algorithms

### Smart Feedback System
- **Impact Detection**: Identifies when and where the ball makes contact with targets
- **Zone Analysis**: Divides target areas into zones for precise impact analysis
- **Real-time Feedback**: Instant visual and haptic feedback for successful hits
- **Performance Metrics**: Tracks frame-by-frame data for detailed analysis

### Data Management
- **Session Logging**: Comprehensive data logging of all training sessions
- **Export Capabilities**: Export training data in JSON and CSV formats
- **Performance Analytics**: Detailed statistics on detection accuracy and timing
- **Debug Mode**: Advanced debugging features for development and testing

## 🏗️ Technical Architecture

### Core Components
- **SwiftUI Interface**: Modern, responsive UI built with SwiftUI
- **OpenCV Integration**: Advanced computer vision processing using OpenCV 4.3.0
- **AVFoundation**: Real-time camera capture and video processing
- **CocoaPods**: Dependency management with OpenCV framework

### Key Classes
- **`LiveCameraView`**: Main real-time processing interface
- **`DetectionManager`**: Manages goal and target detection state
- **`BallDetectionManager`**: Handles ball detection and tracking
- **`CameraFeedManager`**: Camera session management and frame processing
- **`DataLogger`**: Comprehensive data logging and export functionality
- **`OpenCVWrapper`**: Bridge between Swift and OpenCV C++ code

### Detection Algorithms
- **Color-based Detection**: HSV color space analysis for target identification
- **Contour Analysis**: Shape detection for circular targets and ball identification
- **FFT Processing**: Frequency domain analysis for enhanced ball detection
- **Motion Detection**: Frame differencing for movement analysis
- **Adaptive Thresholding**: Dynamic color range adjustment based on lighting conditions

## 📱 User Interface

### Main Features
- **Live Camera Mode**: Real-time training with instant feedback
- **Video Recording**: Capture training sessions for later analysis
- **Ball Detection View**: Dedicated interface for ball tracking
- **FFT Ball Detection**: Advanced frequency-based detection mode
- **Video Library Integration**: Import videos from device library

### Visual Feedback
- **Target Overlays**: Visual indicators for detected targets
- **Ball Tracking**: Real-time ball position visualization
- **Impact Feedback**: Haptic and visual feedback for successful hits
- **Status Indicators**: Real-time system status and performance metrics
- **HUD Display**: Heads-up display with frame counters and detection status

## 🔧 Requirements

### Hardware
- iOS device with camera (iPhone/iPad)
- Sufficient lighting for optimal color detection
- Pink fluorescent tape for marking target boundaries
- Red bullseye targets for training

### Software
- iOS 15.0 or later
- Xcode 12.0 or later
- OpenCV 4.3.0 framework
- CocoaPods for dependency management

## 🚀 Setup Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/Bounceapp.git
cd BounceBackTrainer
```

### 2. Install Dependencies
```bash
# Install CocoaPods if not already installed
sudo gem install cocoapods

# Install project dependencies
pod install
```

### 3. Open Project
```bash
# Open the workspace (not the project file)
open BounceBackTrainer.xcworkspace
```

### 4. Build and Run
- Select your target device or simulator
- Build the project (⌘+B)
- Run the application (⌘+R)

## 📖 Usage Guide

### Setting Up Training Environment
1. **Mark Boundaries**: Use fluorescent pink tape to mark the goal area
2. **Place Targets**: Position red bullseye targets in desired locations
3. **Ensure Lighting**: Provide adequate lighting for optimal detection
4. **Position Camera**: Mount device to capture the full training area

### Using Live Camera Mode
1. **Launch App**: Open BounceBackTrainer
2. **Grant Permissions**: Allow camera and photo library access
3. **Start Live Mode**: Tap "Live Camera Mode"
4. **Wait for Goal Detection**: App will automatically detect pink tape boundaries
5. **Lock Targets**: Tap to lock detected red targets
6. **Start Ball Detection**: Activate ball tracking after targets are locked
7. **Begin Training**: Start your training session with real-time feedback

### Using Video Analysis
1. **Record Video**: Use "Record Video" feature or import from library
2. **Select Video**: Choose video from device library
3. **Analyze**: Tap "Analyze Video" to process the recording
4. **View Results**: Watch analyzed video with detection overlays
5. **Export Data**: Save results and export training data

### Understanding Feedback
- **Green Rectangles**: Locked target boundaries
- **Blue Circles**: Detected ball positions
- **Yellow Indicators**: Current target detections
- **Red Dots**: Impact points
- **Status Text**: Real-time detection status and performance metrics

## 🔬 Technical Details

### Color Detection Parameters
```swift
// Pink Tape Detection
HSV Range: (140-170, 100-255, 100-255)

// Red Target Detection (dual ranges for color wrap-around)
HSV Range 1: (0-10, 100-255, 100-255)
HSV Range 2: (160-179, 100-255, 100-255)

// Ball Detection Colors
White: (0-180, 0-30, 200-255)
Orange: (10-20, 100-255, 100-255)
```

### Detection Thresholds
- **Minimum Contour Area**: 500 pixels
- **Frame Difference Threshold**: 25
- **Ball Confidence Minimum**: 0.3
- **Target Validation Frames**: 5 consecutive frames
- **Temporal Consistency Distance**: 80 pixels

### Performance Optimizations
- **Adaptive Lighting**: Dynamic HSV range adjustment
- **Frame Rate Optimization**: Configurable processing modes
- **Memory Management**: Efficient frame buffer handling
- **Background Processing**: Non-blocking UI with async processing

## 📊 Data Export

### Available Formats
- **JSON Export**: Complete session data with timestamps
- **CSV Export**: Tabular data for spreadsheet analysis

### Exported Data
- Frame-by-frame ball positions
- Target detection coordinates
- Impact events and timing
- Performance metrics and statistics
- Session duration and summary data

## 🛠️ Development

### Project Structure
```
BounceBackTrainer/
├── BounceBackTrainer/          # Main app source
│   ├── Views/                  # SwiftUI view components
│   ├── Managers/               # Core functionality classes
│   ├── OpenCV/                 # Computer vision integration
│   └── Resources/              # Assets and configuration
├── BounceBackTrainerTests/     # Unit tests
├── BounceBackTrainerUITests/   # UI tests
└── Pods/                       # CocoaPods dependencies
```

### Key Files
- `ContentView.swift`: Main app interface
- `LiveCameraView.swift`: Real-time processing view
- `OpenCVWrapper.mm`: OpenCV integration bridge
- `DetectionManager.swift`: Detection state management
- `DataLogger.swift`: Data logging and export

### Debugging Features
- **Debug Mode Toggle**: Enable detailed logging
- **Frame Saving**: Save frames for analysis
- **Performance Monitoring**: Real-time processing metrics
- **Console Logging**: Comprehensive debug output

## 🤝 Contributing

We welcome contributions! Please follow these guidelines:

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Commit your changes**: `git commit -m 'Add amazing feature'`
4. **Push to the branch**: `git push origin feature/amazing-feature`
5. **Open a Pull Request**

### Development Setup
- Ensure OpenCV is properly linked
- Test on both simulator and physical device
- Follow SwiftUI best practices
- Maintain backward compatibility

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **OpenCV Community**: For the powerful computer vision framework
- **Apple**: For SwiftUI and AVFoundation frameworks
- **Contributors**: All developers who have contributed to this project
- **Testers**: Users who provided valuable feedback and testing

## 📞 Support

For support and questions:
- **Issues**: Open an issue in the GitHub repository
- **Documentation**: Check the inline code documentation
- **Community**: Join our development discussions

## 📌 Recent Updates

- Introduced a unified ball detection method (`detectBallUnified`) that sequentially tries soccer-specific, shape (Hough), color, and motion detection for better robustness.
- Kept the FFT pipeline (`detectBallByFFT`) fully implemented, but commented out calls by default. You can re-enable where needed.
- Added a 2-second processing delay in live camera processing to reduce CPU load and improve stability on device.
- Tuned OpenCV thresholds (area, circularity, contrast) and relaxed HoughCircles parameters for better real-world performance.
- Improved logging and error handling in the OpenCV bridge for easier debugging.

## 🧭 Device Deployment (Recommended)

OpenCV in this project is provided by the `OpenCV2` CocoaPod which ships iOS device binaries. Prefer deploying and testing on a physical iPhone.

Steps:
1. Connect your iPhone via USB.
2. In Xcode, choose your iPhone as the run destination.
3. Build (⌘B) and Run (⌘R).

Terminal alternative:
```bash
xcrun xctrace list devices
xcodebuild \
  -workspace BounceBackTrainer.xcworkspace \
  -scheme BounceBackTrainer \
  -destination 'platform=iOS,id=<DEVICE_ID>' install
```

## 🧰 Troubleshooting

- Pods_BounceBackTrainer not found
  - Run `pod install`, open `BounceBackTrainer.xcworkspace` (not `.xcodeproj`)
  - Clean build folder (Shift+⌘+K) and rebuild

- Linker error about opencv2 built for iOS when building for iOS-simulator
  - Use a physical device, or switch to a simulator-compatible OpenCV build

- Bridging issues
  - Ensure `BounceBackTrainer-Bridging-Header.h` imports "OpenCVWrapper.h"

- Permissions
  - `Info.plist` includes camera and photo library usage descriptions. Ensure you grant permissions at runtime.

## 🔄 Version History

### Current Version: 1.0
- Real-time ball detection and tracking
- Target detection and impact analysis
- Live camera mode with instant feedback
- Video recording and analysis capabilities
- Comprehensive data logging and export
- Advanced FFT-based detection algorithms

---

**BounceBackTrainer** - Elevate your training with computer vision-powered feedback


