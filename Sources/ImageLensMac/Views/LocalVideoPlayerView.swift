import AppKit
import AVFoundation
import Observation
import SwiftUI

@MainActor
@Observable
final class VideoPlaybackController {
    private(set) var player: AVPlayer?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var currentTime = 0.0
    private(set) var duration = 0.0
    var isMuted = false {
        didSet { player?.isMuted = isMuted }
    }

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failureObserver: NSObjectProtocol?
    @ObservationIgnored private var appObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    func toggle(resolveURL: @escaping @Sendable () async throws -> URL) async {
        if isPlaying {
            pause()
            return
        }
        if player == nil {
            await prepare(resolveURL: resolveURL)
        }
        guard errorMessage == nil, let player else { return }
        if duration > 0, currentTime >= duration - 0.05 {
            player.seek(
                to: .zero,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { _ in }
            currentTime = 0
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = min(max(0, seconds), max(duration, 0))
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { _ in }
        currentTime = clamped
    }

    func stopAndRelease() {
        pause()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        if let appObserver { NotificationCenter.default.removeObserver(appObserver) }
        endObserver = nil
        failureObserver = nil
        appObserver = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
        isLoading = false
        currentTime = 0
        duration = 0
    }

    private func prepare(resolveURL: @escaping @Sendable () async throws -> URL) async {
        isLoading = true
        errorMessage = nil
        do {
            let url = try await resolveURL()
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = isMuted
            self.player = player
            installObservers(player: player, item: item)
        } catch {
            errorMessage = "视频文件不可用"
        }
        isLoading = false
    }

    private func installObservers(player: AVPlayer, item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite { self.currentTime = max(0, seconds) }
                let itemDuration = item.duration.seconds
                if itemDuration.isFinite { self.duration = max(0, itemDuration) }
            }
        }
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .failed {
                    self.errorMessage = "无法播放此视频"
                    self.pause()
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.duration
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.errorMessage = "无法播放此视频"
                self.pause()
            }
        }
        appObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        }
    }
}

struct LocalVideoRenderView: View {
    let controller: VideoPlaybackController
    let scale: Double

    var body: some View {
        ZStack {
            VideoRenderView(player: controller.player)
                .background(Color.black.opacity(0.92))

            if controller.player == nil {
                VStack(spacing: 7 * scale) {
                    Image(systemName: controller.errorMessage == nil ? "film.stack" : "exclamationmark.triangle")
                        .font(.system(size: max(12, 32 * scale)))
                    if scale >= 0.6 {
                        Text(controller.errorMessage ?? (controller.isLoading ? "正在载入…" : "视频素材"))
                            .font(.system(size: 11 * scale, weight: .medium))
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct VideoPlaybackControlRail: View {
    let controller: VideoPlaybackController
    let scale: Double
    let onTogglePlayback: () -> Void

    var body: some View {
        HStack(spacing: 8 * scale) {
            Button(action: onTogglePlayback) {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18 * scale, height: 18 * scale)
            }
            .help(controller.isPlaying ? "暂停视频" : "播放视频")

            Slider(
                value: Binding(
                    get: { controller.currentTime },
                    set: { controller.seek(to: $0) }
                ),
                in: 0 ... max(controller.duration, 0.01)
            )
            .disabled(controller.player == nil || controller.duration <= 0)
            .accessibilityLabel("视频播放进度")
            .accessibilityValue(timeLabel)

            if scale >= 0.72 {
                Text(timeLabel)
                    .font(.system(size: 9 * scale, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                controller.isMuted.toggle()
            } label: {
                Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18 * scale, height: 18 * scale)
            }
            .disabled(controller.player == nil)
            .help(controller.isMuted ? "取消静音" : "静音")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10 * scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9 * scale, style: .continuous))
    }

    private var timeLabel: String {
        "\(format(controller.currentTime)) / \(format(controller.duration))"
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct VideoRenderView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

private final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = playerLayer
        playerLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
