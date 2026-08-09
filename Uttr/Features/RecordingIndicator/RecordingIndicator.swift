import AppKit
import SwiftUI

// MARK: - View model

/// Drives the indicator UI. Updated by `RecordingIndicatorController`.
@MainActor
@Observable
final class RecordingIndicatorModel {
    enum Phase: Equatable {
        case recording
        case working(label: String) // transcribing / polishing / pasting
    }

    var phase: Phase = .recording
    /// Smoothed input level 0...1 for the waveform.
    var level: Float = 0
}

// MARK: - Indicator view

/// Compact floating capsule shown while a dictation is in flight:
/// pulsing dot + voice-responsive waveform while recording, then a spinner
/// with a status label while transcribing/pasting. Design follows the common
/// macOS dictation-pill pattern; purely decorative, never accepts clicks.
struct RecordingIndicatorView: View {
    /// Fixed window/content size. The panel is deliberately NOT sized from
    /// SwiftUI content: content-driven window sizing (`preferredContentSize`)
    /// plus safe-area invalidation formed a constraint-update cycle that the
    /// macOS 26 SDK's new loop detector aborts on
    /// ("more Update Constraints in Window passes than there are views").
    /// Everything the pill displays fits comfortably in this envelope.
    static let windowSize = NSSize(width: 230, height: 44)

    let model: RecordingIndicatorModel
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .recording:
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .opacity(pulsing ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
                    .onAppear { pulsing = true }
                WaveformBars(level: model.level)
                Text("Listening")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            case .working(let label):
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        // Pin the hosting view's ideal size so it can never disagree with
        // the fixed window frame (see windowSize above).
        .frame(
            width: Self.windowSize.width,
            height: Self.windowSize.height
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Uttr recording indicator")
        .accessibilityValue(model.phase == .recording ? "Listening" : "Working")
        .allowsHitTesting(false)
    }
}

/// Five bars that scale with the input level, with slight per-bar variation
/// so the movement reads as a waveform rather than a single VU meter.
struct WaveformBars: View {
    let level: Float
    private static let barWeights: [Float] = [0.55, 0.85, 1.0, 0.75, 0.5]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.barWeights.count, id: \.self) { index in
                Capsule()
                    .fill(.red)
                    .frame(width: 3, height: barHeight(index))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
        .frame(height: 18)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        Self.height(level: level, weight: Self.barWeights[index])
    }

    /// Pure height mapping: 4 pt floor at silence, 18 pt ceiling at full level.
    static func height(level: Float, weight: Float) -> CGFloat {
        let weighted = min(1, max(0, level) * weight)
        return CGFloat(4 + weighted * 14)
    }
}

// MARK: - Panel

/// Borderless, non-activating panel hosting the indicator. Joins all Spaces,
/// floats above normal windows, ignores mouse events, and never steals focus
/// from the app the user is dictating into.
final class RecordingIndicatorPanel: NSPanel {
    init(model: RecordingIndicatorModel) {
        super.init(
            contentRect: NSRect(origin: .zero, size: RecordingIndicatorView.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // the SwiftUI capsule draws its own shadow
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: RecordingIndicatorView(model: model))
        // Fixed-size window, fixed-size content — the hosting view must never
        // drive window sizing or safe-area updates. Content-driven sizing
        // (`sizingOptions = [.preferredContentSize]`) combined with safe-area
        // invalidation on this borderless panel created a constraint-update
        // cycle that macOS 26's stricter AppKit aborts with an uncaught
        // NSGenericException (verified on macOS 26.5.2 / Xcode 26.6 build).
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(origin: .zero, size: RecordingIndicatorView.windowSize)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    /// Centers the panel near the bottom of the screen the cursor is on —
    /// where the user's attention is when they trigger dictation. Pure frame
    /// math on the fixed size; deliberately no layout passes here.
    func positionOnActiveScreen() {
        let screen = screenUnderMouse()
        let size = RecordingIndicatorView.windowSize
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.minY + 84 // above the Dock, out of the caret's way
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
            ?? NSScreen()
    }
}

// MARK: - Controller

/// Owns the indicator panel and keeps it in sync with `AppState`:
/// shows on `.recording`, switches phases through transcribe/polish/paste,
/// hides on `.idle`/other states. While recording, polls the recorder's
/// input level ~20 Hz to drive the waveform.
@MainActor
final class RecordingIndicatorController {
    private let model = RecordingIndicatorModel()
    private var panel: RecordingIndicatorPanel?
    private var levelTask: Task<Void, Never>?
    private let recorder: AudioRecording

    init(recorder: AudioRecording) {
        self.recorder = recorder
    }

    /// Call whenever the dictation state changes.
    func stateChanged(_ state: DictationState) {
        switch state {
        case .recording:
            model.phase = .recording
            show()
            startLevelPolling()
        case .transcribing:
            stopLevelPolling()
            model.phase = .working(label: "Transcribing…")
            show()
        case .polishing:
            model.phase = .working(label: "Polishing…")
            show()
        case .prompting:
            stopLevelPolling()
            model.phase = .working(label: "Asking AI…")
            show()
        case .pasting:
            model.phase = .working(label: "Pasting…")
            show()
        case .idle, .awaitingHotkey, .blocked:
            stopLevelPolling()
            hide()
        }
    }

    // MARK: - Private

    private func show() {
        if panel == nil {
            panel = RecordingIndicatorPanel(model: model)
        }
        guard let panel, !panel.isVisible else { return }
        panel.positionOnActiveScreen()
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
        model.level = 0
    }

    private func startLevelPolling() {
        stopLevelPolling()
        levelTask = Task { [weak self, recorder] in
            while !Task.isCancelled {
                let raw = await recorder.currentAudioLevel()
                guard let self, !Task.isCancelled else { return }
                // Perceptual mapping: mic RMS for speech is roughly 0.01–0.2,
                // so scale into 0...1 and smooth (fast attack, slow release)
                // so the bars feel live without flickering.
                let scaled = min(1, raw * 8)
                let previous = self.model.level
                self.model.level = scaled > previous
                    ? scaled
                    : previous * 0.75 + scaled * 0.25
                try? await Task.sleep(nanoseconds: 50_000_000) // ~20 Hz
            }
        }
    }

    private func stopLevelPolling() {
        levelTask?.cancel()
        levelTask = nil
    }
}
