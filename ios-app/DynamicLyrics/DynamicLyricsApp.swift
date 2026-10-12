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
    @State private var isSimulating: Bool = false
    @State private var lyricLines: [LyricLine] = []
    
    // 4 行歌詞預覽
    @State private var prevLyric: String = ""
    @State private var currentLyric: String = "準備就緒"
    @State private var nextLyric1: String = ""
    @State private var nextLyric2: String = ""
    
    @State private var progressMs: Int = 0
    @State private var loadTask: Task<Void, Never>?
    @State private var lastPushedIsPlaying: Bool?
    @State private var loadedTrackUri: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // 音樂輸入區域
                VStack(alignment: .leading, spacing: 8) {
                    Text("歌曲設定 (支援 Spotify / Lrclib)")
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

                // 4 行歌詞預覽卡片 (比照 CarPlay 顯示效果)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(trackName)
                            .font(.caption)
                            .bold()
                            .foregroundColor(.green)
                        Text("• " + artistName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("CarPlay 4 行即時預覽")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // 第 1 條：之前唱過的
                        Text(prevLyric.isEmpty ? " " : prevLyric)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.5))
                            .lineLimit(1)

                        // 第 2 條：當下正在唱的
                        Text(currentLyric)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(.green)
                            .lineLimit(1)
                            .id("curr-\(currentLyric)")

                        // 第 3 條：下一句
                        Text(nextLyric1.isEmpty ? " " : nextLyric1)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        // 第 4 條：下下句
                        Text(nextLyric2.isEmpty ? " " : nextLyric2)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)

                // 控制按鈕
                VStack(spacing: 12) {
                    Button(action: toggleSimulation) {
                        HStack {
                            Image(systemName: isSimulating ? "stop.fill" : "play.fill")
                            Text(isSimulating ? "停止播放與靈動歌詞" : "開始播放並啟動靈動歌詞")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isSimulating ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .font(.headline)
                    }

                    Text("提示：開啟播放後將啟動背景保活與 4 行卡拉OK逐字渲染，CarPlay 與動態島將自動同步。")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
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
        currentLyric = "載入歌詞中…"
        nextLyric1 = ""
        nextLyric2 = ""
        prevLyric = ""
        lastPushedIsPlaying = nil
        loadedTrackUri = nil

        loadTask = Task {
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
