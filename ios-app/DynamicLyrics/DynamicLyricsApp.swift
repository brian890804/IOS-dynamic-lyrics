//
//  DynamicLyricsApp.swift
//  DynamicLyrics
//

import SwiftUI

@main
struct DynamicLyricsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var liveActivityManager = LiveActivityManager.shared
    @StateObject private var spotifyAuth = SpotifyAuthManager.shared
    @StateObject private var spotifyPoller = SpotifyWebPoller.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var spotifyError: String?
    @State private var isConnectingSpotify = false
    @State private var trackName: String = "一路向北"
    @State private var artistName: String = "周杰倫"
    @State private var albumArtUrl: String? = nil
    @State private var isSimulating: Bool = false
    @State private var lyricLines: [LyricLine] = []
    
    @State private var prevLyric: String = ""
    @State private var currentLyric: String = "準備就緒"
    @State private var nextLyric1: String = ""
    @State private var nextLyric2: String = ""
    
    @State private var progressMs: Int = 0
    @State private var loadTask: Task<Void, Never>?
    @State private var lastPushedIsPlaying: Bool?
    @State private var loadedTrackUri: String?

    private let playlist = [
        ("一路向北", "周杰倫"),
        ("夜曲", "周杰倫"),
        ("晴天", "周杰倫"),
        ("稻香", "周杰倫")
    ]
    @State private var playlistIndex: Int = 0

    private let themeOrange = Color(red: 1.0, green: 0.48, blue: 0.12)

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    spotifySection

                    // 音樂設定
                    VStack(alignment: .leading, spacing: 8) {
                        Text("模擬模式 (未連線 Spotify 時測試用)")
                            .font(.caption)
                            .foregroundColor(.gray)

                        HStack {
                            TextField("歌名", text: $trackName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            TextField("歌手", text: $artistName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                    // 現代感預覽卡片
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            if let artUrl = albumArtUrl, let url = URL(string: artUrl) {
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(width: 44, height: 44)
                                .cornerRadius(8)
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(themeOrange.opacity(0.3))
                                    .frame(width: 44, height: 44)
                                    .overlay(Image(systemName: "music.note").foregroundColor(themeOrange))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(trackName)
                                    .font(.headline)
                                    .bold()
                                    .foregroundColor(themeOrange)
                                Text(artistName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(prevLyric.isEmpty ? " " : prevLyric)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary.opacity(0.5))
                                .lineLimit(1)

                            Text(currentLyric)
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(themeOrange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Text(nextLyric1.isEmpty ? " " : nextLyric1)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(nextLyric2.isEmpty ? " " : nextLyric2)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(14)

                    // 核心播放控制列：上一首、播放/暫停、下一首
                    VStack(spacing: 12) {
                        HStack(spacing: 40) {
                            Button(action: playPrevious) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(.primary)
                            }

                            Button(action: toggleSimulation) {
                                Image(systemName: isSimulating ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(themeOrange)
                            }

                            Button(action: playNext) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.vertical, 4)

                        Text(isSimulating ? "播放中：靈動歌詞與動態島持續同步" : "已暫停：點選播放啟動靈動歌詞")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                    .disabled(spotifyPoller.isRunning)
                    .opacity(spotifyPoller.isRunning ? 0.4 : 1)
                }
                .padding()
            }
            .navigationTitle("靈動歌詞")
        }
        .onAppear {
            if spotifyAuth.isConnected { startSpotifySync() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Live Activity 最長 8 小時或被使用者滑掉後就會結束，回到前景時補建
            if phase == .active && spotifyPoller.isRunning { ensureLiveActivity() }
        }
        .onReceive(SpotifyRemoteManager.shared.trackChanged.receive(on: RunLoop.main)) { state in
            loadTrack(state)
        }
        .onReceive(SpotifyRemoteManager.shared.$currentState.receive(on: RunLoop.main)) { state in
            onPlaybackTick(state)
        }
    }

    // MARK: - Spotify

    private var spotifySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundColor(.green)
                Text("Spotify 即時同步")
                    .font(.headline)
                Spacer()
            }

            if spotifyAuth.isConnected {
                Text(spotifyPoller.status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack {
                    Button(spotifyPoller.isRunning ? "暫停同步" : "開始同步") {
                        if spotifyPoller.isRunning { spotifyPoller.stop() } else { startSpotifySync() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeOrange)

                    Spacer()

                    Button("登出 Spotify", role: .destructive) {
                        spotifyPoller.stop()
                        spotifyAuth.disconnect()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                TextField("貼上 Spotify Client ID", text: $spotifyAuth.clientId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))

                Text("Redirect URI 請在 Spotify Dashboard 填：\(SpotifyAuthManager.redirectUri)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)

                Button {
                    connectSpotify()
                } label: {
                    HStack {
                        if isConnectingSpotify { ProgressView() }
                        Text("登入 Spotify")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isConnectingSpotify || spotifyAuth.clientId.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let spotifyError = spotifyError {
                Text(spotifyError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func connectSpotify() {
        spotifyError = nil
        isConnectingSpotify = true
        Task {
            defer { isConnectingSpotify = false }
            do {
                try await spotifyAuth.connect()
                startSpotifySync()
            } catch {
                spotifyError = error.localizedDescription
            }
        }
    }

    private func startSpotifySync() {
        // 不呼叫 stopSimulation()：它會非同步 endActivity，可能把下面剛建立的 Activity 關掉
        if isSimulating {
            loadTask?.cancel()
            isSimulating = false
            BackgroundAudioManager.shared.stopKeepAlive()
        }
        spotifyPoller.start()
        ensureLiveActivity()
    }

    /// iOS 只允許前景建立 Live Activity：趁 App 還在前景先建好，之後開車鎖屏換歌都只做 update
    private func ensureLiveActivity() {
        guard liveActivityManager.currentActivity?.activityState != .active else { return }
        let state = SpotifyRemoteManager.shared.currentState
        let hasTrack = loadedTrackUri != nil && state != nil
        liveActivityManager.startActivity(
            songId: state?.trackUri ?? "spotify",
            trackName: hasTrack ? trackName : "等待 Spotify 播放",
            artistName: hasTrack ? artistName : "靈動歌詞",
            prevLyric: hasTrack ? prevLyric : "",
            currentLyric: hasTrack ? currentLyric : "♪",
            nextLyric1: hasTrack ? nextLyric1 : "",
            nextLyric2: hasTrack ? nextLyric2 : "",
            progressMs: state?.progressMs ?? 0,
            durationMs: state?.durationMs ?? 0
        )
    }

    // MARK: - 模擬模式

    private func playPrevious() {
        playlistIndex = (playlistIndex - 1 + playlist.count) % playlist.count
        let song = playlist[playlistIndex]
        trackName = song.0
        artistName = song.1
        startSimulation()
    }

    private func playNext() {
        playlistIndex = (playlistIndex + 1) % playlist.count
        let song = playlist[playlistIndex]
        trackName = song.0
        artistName = song.1
        startSimulation()
    }

    private func toggleSimulation() {
        if isSimulating {
            stopSimulation()
        } else {
            startSimulation()
        }
    }

    private func startSimulation() {
        isSimulating = true
        BackgroundAudioManager.shared.startKeepAlive()
        SpotifyRemoteManager.shared.updatePlaybackState(
            trackUri: "sim:\(UUID().uuidString)",
            trackName: trackName,
            artistName: artistName,
            durationMs: 295000,
            progressMs: 0,
            isPlaying: true
        )
    }

    private func loadTrack(_ state: SpotifyTrackState) {
        loadTask?.cancel()
        trackName = state.trackName
        artistName = state.artistName
        lyricLines = []
        currentLyric = "載入中…"
        nextLyric1 = ""
        nextLyric2 = ""
        prevLyric = ""
        lastPushedIsPlaying = nil
        loadedTrackUri = nil

        // 換歌當下立刻顯示新歌名，避免歌詞抓取期間 CarPlay 還停在上一首
        LiveActivityManager.shared.showTrack(
            songId: state.trackUri,
            trackName: state.trackName,
            artistName: state.artistName,
            currentLyric: "載入歌詞中…",
            nextLyric1: "",
            progressMs: state.progressMs,
            durationMs: state.durationMs,
            isPlaying: state.isPlaying
        )

        loadTask = Task {
            // 封面與歌詞並行抓取，歌詞不必等封面
            let durationSec = state.durationMs > 0 ? Double(state.durationMs) / 1000 : nil
            async let artUrlResult = ArtworkService.shared.fetchArtworkUrl(trackName: state.trackName, artistName: state.artistName)
            async let linesResult = try? LyricService.shared.fetchLyrics(
                trackName: state.trackName, artistName: state.artistName, durationSec: durationSec)
            let artUrl = await artUrlResult
            let lines = await linesResult ?? []
            if Task.isCancelled { return }
            self.albumArtUrl = artUrl
            self.lyricLines = lines
            self.loadedTrackUri = state.trackUri

            let progress = SpotifyRemoteManager.shared.getCurrentInterpolatedProgressMs()
            let match = LrcParser.find4Lines(in: lines, progressMs: progress)
            self.prevLyric = match.prevText
            self.currentLyric = match.currentText
            self.nextLyric1 = match.nextText1
            self.nextLyric2 = match.nextText2

            LiveActivityManager.shared.showTrack(
                songId: state.trackUri,
                trackName: state.trackName,
                artistName: state.artistName,
                albumArtUrl: artUrl,
                prevLyric: match.prevText,
                currentLyric: match.currentText,
                nextLyric1: match.nextText1,
                nextLyric2: match.nextText2,
                progressMs: progress,
                durationMs: state.durationMs,
                isPlaying: state.isPlaying,
                lineDurationSec: remainingLineSec(match: match, progressMs: progress, speed: state.playbackSpeed)
            )
            self.lastPushedIsPlaying = state.isPlaying
        }
    }

    private func onPlaybackTick(_ state: SpotifyTrackState?) {
        guard let state = state, state.trackUri == loadedTrackUri, !lyricLines.isEmpty else { return }
        progressMs = state.progressMs
        let match = LrcParser.find4Lines(in: lyricLines, progressMs: state.progressMs)
        let lyricChanged = match.currentText != currentLyric
        let playStateChanged = lastPushedIsPlaying != state.isPlaying
        guard lyricChanged || playStateChanged else { return }

        withAnimation(.easeInOut(duration: 0.35)) {
            prevLyric = match.prevText
            currentLyric = match.currentText
            nextLyric1 = match.nextText1
            nextLyric2 = match.nextText2
        }
        lastPushedIsPlaying = state.isPlaying

        LiveActivityManager.shared.updateLyric(
            trackName: state.trackName,
            artistName: state.artistName,
            albumArtUrl: albumArtUrl,
            prevLyric: match.prevText,
            currentLyric: match.currentText,
            nextLyric1: match.nextText1,
            nextLyric2: match.nextText2,
            progressMs: state.progressMs,
            durationMs: state.durationMs,
            isPlaying: state.isPlaying,
            lineDurationSec: remainingLineSec(match: match, progressMs: state.progressMs, speed: state.playbackSpeed)
        )
    }

    private func remainingLineSec(match: LyricMatch4Lines, progressMs: Int, speed: Double) -> Double {
        let currentStart = lyricLines.indices.contains(match.currentIndex) ? lyricLines[match.currentIndex].timeMs : progressMs
        let elapsed = max(0, progressMs - currentStart)
        let naturalDuration = match.currentLineDurationMs
        let remainingMs = max(400, naturalDuration - elapsed)
        return Double(remainingMs) / 1000.0 / max(speed, 0.1)
    }

    private func stopSimulation() {
        loadTask?.cancel()
        isSimulating = false
        BackgroundAudioManager.shared.stopKeepAlive()
        SpotifyRemoteManager.shared.updatePlaybackState(
            trackUri: loadedTrackUri ?? "",
            trackName: trackName,
            artistName: artistName,
            durationMs: 0,
            progressMs: progressMs,
            isPlaying: false
        )
        Task {
            await LiveActivityManager.shared.endActivity()
        }
    }
}
