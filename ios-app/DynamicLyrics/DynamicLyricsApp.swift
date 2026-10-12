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

                // 控制按鈕
                VStack(spacing: 12) {
                    Button(action: toggleSimulation) {
                        HStack {
                            Image(systemName: isSimulating ? "stop.fill" : "play.fill")
                            Text(isSimulating ? "停止播放與靈動歌詞" : "開始播放並啟動靈動歌詞")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isSimulating ? Color.red : themeOrange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .font(.headline)
                    }

                    Text("提示：專輯封面會同步呈現在 CarPlay 車機儀表板小工具左上方。")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

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

        prevLyric = match.prevText
        currentLyric = match.currentText
        nextLyric1 = match.nextText1
        nextLyric2 = match.nextText2
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
        let nextIdx = match.currentIndex + 1
        let remainingMs: Int
        if nextIdx >= 0 && nextIdx < lyricLines.count {
            remainingMs = max(500, lyricLines[nextIdx].timeMs - progressMs)
        } else {
            remainingMs = match.currentLineDurationMs
        }
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
