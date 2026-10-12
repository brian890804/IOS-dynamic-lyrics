//
//  DynamicLyricsApp.swift
//  DynamicLyrics
//

import SwiftUI
import Combine

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
    @State private var currentLyric: String = "準備就緒"
    @State private var nextLyric: String = ""
    @State private var progressMs: Int = 0
    @State private var loadTask: Task<Void, Never>?
    /// 上次推給 Live Activity 的播放狀態 (用來偵測暫停 / 繼續)
    @State private var lastPushedIsPlaying: Bool?
    /// 目前 lyricLines 屬於哪首歌 (避免換歌瞬間用舊歌詞比對新進度)
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

                // 歌詞預覽卡片 (比照 CarPlay 顯示效果)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CarPlay / Live Activity 預覽")
                        .font(.caption2)
                        .foregroundColor(.gray)

                    HStack {
                        Text(trackName)
                            .font(.caption)
                            .bold()
                            .foregroundColor(.green)
                        Text("• " + artistName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(currentLyric)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .id("preview-curr-\(currentLyric)")
                        .animation(.easeInOut, value: currentLyric)

                    Text(nextLyric)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .id("preview-next-\(nextLyric)")
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

                    Text("提示：開啟播放後將啟動背景保活與有序 ActivityKit 佇列，動態島與 CarPlay 將即時無延遲同步。")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("靈動歌詞")
        }
        // 換歌 → 重新抓歌詞；每次進度插值 / 暫停 / 拖動 → 重新比對當前句
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

    /// 模擬模式：以手動輸入的歌名假裝成 Spotify 推送，走與實機完全相同的同步管線
    private func startSimulation() {
        isSimulating = true
        BackgroundAudioManager.shared.startKeepAlive()
        SpotifyRemoteManager.shared.updatePlaybackState(
            trackUri: "sim:\(UUID().uuidString)",  // 每次都視為新歌 → 觸發 trackChanged 抓歌詞
            trackName: trackName,
            artistName: artistName,
            durationMs: 0,          // 未知 → 抓到歌詞後由 lrclib 時長補上也可
            progressMs: 0,
            isPlaying: true
        )
    }

    /// 換歌：依 Spotify 提供的歌名 / 歌手 / 時長抓歌詞並啟動 Live Activity
    private func loadTrack(_ state: SpotifyTrackState) {
        loadTask?.cancel()
        trackName = state.trackName
        artistName = state.artistName
        lyricLines = []
        currentLyric = "載入歌詞中…"
        nextLyric = ""
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
            let match = LrcParser.findCurrentAndNext(in: lines, progressMs: progress)
            self.currentLyric = match.currentText
            self.nextLyric = match.nextText

            await LiveActivityManager.shared.endActivity()
            LiveActivityManager.shared.startActivity(
                songId: state.trackUri,
                trackName: state.trackName,
                artistName: state.artistName,
                initialLyric: match.currentText,
                nextLyric: match.nextText,
                progressMs: progress,
                durationMs: state.durationMs,
                lineDurationSec: remainingLineSec(match: match, progressMs: progress, speed: state.playbackSpeed)
            )
            self.lastPushedIsPlaying = state.isPlaying
        }
    }

    /// Spotify 狀態 (含 200ms 插值) 每次變動時呼叫：換句、暫停、繼續、拖動都會推 Live Activity
    private func onPlaybackTick(_ state: SpotifyTrackState?) {
        guard let state = state, state.trackUri == loadedTrackUri, !lyricLines.isEmpty else { return }
        progressMs = state.progressMs
        let match = LrcParser.findCurrentAndNext(in: lyricLines, progressMs: state.progressMs)
        let lyricChanged = match.currentText != currentLyric
        let playStateChanged = lastPushedIsPlaying != state.isPlaying
        guard lyricChanged || playStateChanged else { return }

        currentLyric = match.currentText
        nextLyric = match.nextText
        lastPushedIsPlaying = state.isPlaying
        LiveActivityManager.shared.updateLyric(
            trackName: state.trackName,
            artistName: state.artistName,
            currentLyric: match.currentText,
            nextLyric: match.nextText,
            progressMs: state.progressMs,
            durationMs: state.durationMs,
            isPlaying: state.isPlaying,
            lineDurationSec: remainingLineSec(match: match, progressMs: state.progressMs, speed: state.playbackSpeed)
        )
    }

    /// 本句「剩餘」秒數 (拖動到句中時不能用整句長度)，並考慮播放速度
    private func remainingLineSec(match: LyricMatchResult, progressMs: Int, speed: Double) -> Double {
        let nextIdx = match.currentIndex + 1
        let remainingMs: Int
        if nextIdx < lyricLines.count {
            remainingMs = max(500, lyricLines[nextIdx].timeMs - progressMs)
        } else {
            remainingMs = match.lineDurationMs
        }
        return Double(remainingMs) / 1000.0 / max(speed, 0.1)
    }

    private func stopSimulation() {
        loadTask?.cancel()
        isSimulating = false
        lyricLines = []
        loadedTrackUri = nil
        SpotifyRemoteManager.shared.updatePlaybackState(
            trackUri: SpotifyRemoteManager.shared.currentState?.trackUri, trackName: trackName, artistName: artistName,
            durationMs: 0, progressMs: 0, isPlaying: false)
        BackgroundAudioManager.shared.stopKeepAlive()
        Task {
            await LiveActivityManager.shared.endActivity()
        }
    }
}
