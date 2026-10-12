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
            VStack(spacing: 20) {
                // 音樂設定
                VStack(alignment: .leading, spacing: 8) {
                    Text("歌曲設定 (自動抓取高畫質專輯封面)")
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

                Spacer()
            }
            .padding()
            .navigationTitle("靈動歌詞")
        }
        .onReceive(SpotifyRemoteManager.shared.trackChanged.receive(on: RunLoop.main)) { state in
            loadTrack(state)
        }
        .onReceive(SpotifyRemoteManager.shared.$currentState.receive(on: RunLoop.main)) { state in
            onPlaybackTick(state)
        }
    }

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

        loadTask = Task {
            // 同步獲取專輯封面
            let artUrl = await ArtworkService.shared.fetchArtworkUrl(trackName: state.trackName, artistName: state.artistName)
            if Task.isCancelled { return }
            self.albumArtUrl = artUrl

            let durationSec = state.durationMs > 0 ? Double(state.durationMs) / 1000 : nil
            let lines = (try? await LyricService.shared.fetchLyrics(
                trackName: state.trackName, artistName: state.artistName, durationSec: durationSec)) ?? []
            if Task.isCancelled { return }
            self.lyricLines = lines
            self.loadedTrackUri = state.trackUri

            let progress = SpotifyRemoteManager.shared.getCurrentInterpolatedProgressMs()
            let match = LrcParser.find4Lines(in: lines, progressMs: progress)
            self.prevLyric = match.prevText
            self.currentLyric = match.currentText
            self.nextLyric1 = match.nextText1
            self.nextLyric2 = match.nextText2

            await LiveActivityManager.shared.endActivity()
            LiveActivityManager.shared.startActivity(
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
