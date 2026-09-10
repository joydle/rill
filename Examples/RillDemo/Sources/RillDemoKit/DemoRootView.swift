import SwiftUI
import RillCore
import RillUI

/// The demo's root SwiftUI screen: a chunked-streaming simulator feeding a live
/// ``MarkdownSource``, a theme switcher, the showcase document, and the analytics
/// HUD overlay.
///
/// Tapping **Stream** replays ``ShowcaseDocument`` through a ``StreamingSimulator``
/// at the chosen chunk size and speed, appending each chunk to the source so the
/// renderer commits finished blocks and only re-lexes the dirty tail. The
/// ``HUDAnalyticsSink`` records ``ParseMetrics``/``RenderMetrics`` along the way,
/// and ``HUDView`` shows them live. Switching the theme re-renders the same
/// document with a different ``RillTheme``.
@MainActor
public struct DemoRootView: View {

    /// The streaming source that the simulator feeds and the view renders.
    @State private var source = MarkdownSource(analytics: HUDAnalyticsSink.shared)

    /// The analytics sink backing the HUD.
    @State private var hud = HUDAnalyticsSink.shared

    /// The index of the selected theme in ``ThemeCatalog/all``.
    @State private var themeIndex = 0

    /// Characters emitted per streamed chunk.
    @State private var chunkSize: Double = 6

    /// Milliseconds the playback loop waits between chunks.
    @State private var delayMilliseconds: Double = 20

    /// Whether a streaming playback is currently running.
    @State private var isStreaming = false

    /// The in-flight playback task, cancelled when the user stops or restarts.
    @State private var playbackTask: Task<Void, Never>?

    /// Creates the root demo view.
    public init() {}

    /// The currently selected theme.
    private var theme: RillTheme { ThemeCatalog.all[themeIndex].theme }

    public var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollView {
                StreamingMarkdownView(source, theme: theme, analytics: hud)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            Divider()
            HUDView(snapshot: hud.snapshot)
                .padding(12)
        }
        .onAppear {
            // Opt-in auto-start for screenshots / UI tests; no effect on normal use.
            if ProcessInfo.processInfo.environment["RILL_DEMO_AUTOSTREAM"] == "1", !isStreaming {
                start()
            }
        }
    }

    /// The top control bar: theme switcher, chunk/speed sliders, and playback.
    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Theme", selection: $themeIndex) {
                ForEach(Array(ThemeCatalog.all.enumerated()), id: \.element.id) { index, named in
                    Text(named.name).tag(index)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 16) {
                labeledSlider("Chunk \(Int(chunkSize))", value: $chunkSize, range: 1...40)
                labeledSlider("Delay \(Int(delayMilliseconds))ms", value: $delayMilliseconds, range: 0...100)
            }

            HStack {
                Button(isStreaming ? "Stop" : "Stream") {
                    if isStreaming { stop() } else { start() }
                }
                .buttonStyle(.borderedProminent)

                Button("Reset") { reset() }
                    .buttonStyle(.bordered)
                    .disabled(isStreaming)

                Spacer()
            }
        }
        .padding(12)
    }

    /// A slider with a leading caption.
    private func labeledSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: range, step: 1)
        }
    }

    /// Starts replaying the showcase document into the source chunk by chunk.
    private func start() {
        reset()
        isStreaming = true
        let simulator = StreamingSimulator(
            text: ShowcaseDocument.markdown,
            chunkSize: Int(chunkSize),
            delay: .milliseconds(Int(delayMilliseconds))
        )
        let chunks = simulator.chunks()
        let delay = simulator.delay
        playbackTask = Task { @MainActor in
            for chunk in chunks {
                if Task.isCancelled { break }
                source.append(chunk)
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }
            }
            isStreaming = false
        }
    }

    /// Cancels any in-flight playback.
    private func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        isStreaming = false
    }

    /// Stops playback and clears the rendered document and HUD metrics.
    private func reset() {
        stop()
        source = MarkdownSource(analytics: hud)
        hud.reset()
    }
}
