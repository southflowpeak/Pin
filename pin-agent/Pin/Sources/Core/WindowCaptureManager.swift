import Foundation
import ScreenCaptureKit
import CoreGraphics
import AVFoundation
import AppKit

/// Manages window capture using ScreenCaptureKit with AVSampleBufferDisplayLayer
/// Based on Topit's implementation for direct buffer display
@MainActor
final class WindowCaptureManager: NSObject, ObservableObject {

    /// The video layer for displaying captured frames directly
    /// This layer should be added to the mirror window's layer hierarchy
    @Published private(set) var videoLayer = AVSampleBufferDisplayLayer()

    /// Whether capture has encountered an error
    @Published private(set) var captureError: Bool = false

    /// Whether capture is currently active
    @Published private(set) var capturing: Bool = false

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var configuration = SCStreamConfiguration()
    private var filter: SCContentFilter?
    private var targetWindow: SCWindow?

    override init() {
        super.init()
    }

    /// Start capturing the specified window
    func startCapture(display: SCDisplay?, window: SCWindow) async {
        if stream != nil { return }

        do {
            targetWindow = window

            // Configure pixel format and color space
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.colorSpaceName = CGColorSpace.sRGB

            // Get frame rate from screen
            let screen = display?.nsScreen ?? NSScreen.main
            let frameRate = screen?.maximumFramesPerSecond ?? 60
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            configuration.showsCursor = false
            configuration.capturesAudio = false

            // Create content filter for single window
            filter = SCContentFilter(desktopIndependentWindow: window)

            // Set capture size based on macOS version
            if let filter = filter {
                let scale = CGFloat(filter.pointPixelScale)
                configuration.width = Int(filter.contentRect.width * scale)
                configuration.height = Int(filter.contentRect.height * scale)
            }

            // Create stream output handler
            // Following Topit's pattern: always enqueue, don't check capturing flag
            // This ensures sampleBuffer is properly consumed and released
            streamOutput = StreamOutput { [weak self] sampleBuffer in
                DispatchQueue.main.async {
                    // Just enqueue - the layer handles invalid buffers gracefully
                    self?.videoLayer.enqueue(sampleBuffer)
                }
            }

            // Create and configure stream
            guard let filter = filter, let streamOutput = streamOutput else {
                throw AgentError.captureFailure("Failed to create filter or stream output")
            }

            stream = SCStream(filter: filter, configuration: configuration, delegate: nil)

            guard let stream = stream else {
                throw AgentError.captureFailure("Failed to create stream")
            }

            try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: .global())
            try await stream.startCapture()

            capturing = true
            captureError = false

        } catch {
            print("Start capture failed with error: \(error)")
            stream = nil
            capturing = false
            captureError = true
        }
    }

    /// Resume capture with new dimensions
    func resumeCapture(newWidth: CGFloat, newHeight: CGFloat, screen: NSScreen? = nil) async {
        if stream != nil { return }

        updateStreamSize(newWidth: newWidth, newHeight: newHeight, screen: screen)

        do {
            guard let filter = filter else {
                throw AgentError.captureFailure("No filter available for resume")
            }

            // Following Topit's pattern: always enqueue, don't check capturing flag
            streamOutput = StreamOutput { [weak self] sampleBuffer in
                DispatchQueue.main.async {
                    self?.videoLayer.enqueue(sampleBuffer)
                }
            }

            guard let streamOutput = streamOutput else {
                throw AgentError.captureFailure("Failed to create stream output")
            }

            stream = SCStream(filter: filter, configuration: configuration, delegate: nil)

            guard let stream = stream else {
                throw AgentError.captureFailure("Failed to create stream")
            }

            try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: .global())
            try await stream.startCapture()

            capturing = true
            captureError = false

        } catch {
            print("Resume capture failed with error: \(error)")
            stream = nil
            capturing = false
            captureError = true
        }
    }

    /// Update capture configuration (e.g., when window resizes)
    func updateStreamSize(newWidth: CGFloat, newHeight: CGFloat, screen: NSScreen? = nil) {
        let scaleFactor = screen?.backingScaleFactor ?? 2.0
        configuration.width = Int(newWidth * scaleFactor)
        configuration.height = Int(newHeight * scaleFactor)

        let frameRate = screen?.maximumFramesPerSecond ?? 60
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        stream?.updateConfiguration(configuration) { error in
            if let error = error {
                print("Failed to update stream configuration: \(error)")
            }
        }
    }

    /// Stop capturing
    /// Following Topit's exact pattern: all cleanup in stopCapture callback
    func stopCapture() {
        guard stream != nil else { return }

        // Stop the stream - all cleanup happens in callback
        // Note: NOT using [weak self] so self stays alive until callback completes
        // This ensures all pending DispatchQueue.main.async blocks (sampleBuffer enqueues)
        // execute before this cleanup block (FIFO ordering)
        stream?.stopCapture { error in
            DispatchQueue.main.async {
                // All cleanup happens here after stream fully stops
                // and all pending sample buffer enqueues have completed
                self.stream = nil
                self.capturing = false
                self.captureError = false
                self.videoLayer.removeFromSuperlayer()
                self.videoLayer = AVSampleBufferDisplayLayer()
                if let error = error {
                    print("Failed to stop capture: \(error)")
                }
            }
        }
    }

    /// Reset video layer (create new instance)
    func resetVideoLayer() {
        videoLayer.removeFromSuperlayer()
        videoLayer = AVSampleBufferDisplayLayer()
    }
}

// MARK: - Stream Output Handler

/// Simple stream output handler following Topit's pattern
private final class StreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {

    private let onSampleBuffer: (CMSampleBuffer) -> Void

    init(onSampleBuffer: @escaping (CMSampleBuffer) -> Void) {
        self.onSampleBuffer = onSampleBuffer
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        onSampleBuffer(sampleBuffer)
    }
}

// MARK: - NSScreen Extension

extension SCDisplay {
    /// Get the NSScreen corresponding to this SCDisplay
    var nsScreen: NSScreen? {
        NSScreen.screens.first { screen in
            // Compare using displayID
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return false
            }
            return screenNumber == self.displayID
        }
    }
}
