//
//  SpotifyRemoteManager.swift
//  DynamicLyrics
//
//  透過 Spotify iOS App Remote SDK 與系統廣播獲取最新 Spotify 當前播放進度
//
//  同步模型：Spotify 只在「播放/暫停/拖動/換歌/變速」時推送一次 PlayerState，
//  中間的進度由本機以 baseProgress + (now - baseTimestamp) * playbackSpeed 插值。
//

import Foundation
import Combine

public struct SpotifyTrackState: Equatable {
    public let trackUri: String
    public let trackName: String
    public let artistName: String
    public let durationMs: Int
    public let progressMs: Int
    public let isPlaying: Bool
    /// 1.0 = 正常；Podcast / 有聲書可能為 0.5 ~ 3.5
    public let playbackSpeed: Double
    public let timestamp: Date
}

public class SpotifyRemoteManager: ObservableObject {
    public static let shared = SpotifyRemoteManager()

    @Published public private(set) var currentState: SpotifyTrackState?
    /// 換歌時發出 (trackUri 改變)，供 UI 重新抓歌詞
    public let trackChanged = PassthroughSubject<SpotifyTrackState, Never>()

    private var progressTrackingTimer: Timer?
    private var baseProgressMs: Int = 0
    private var baseTimestamp: Date = Date()
    private var isPlaying: Bool = false
    private var playbackSpeed: Double = 1.0
    private var durationMs: Int = 0

    /// App Remote 事件從 Spotify 送達本 App 的平均延遲補償 (實機量測後微調，預設 0)
    public var latencyCompensationMs: Int = 0

    private init() {}

    /// 當收到 Spotify iOS App Remote 或是 Web API 狀態推播時更新
    /// - Parameter sampledAt: 該進度的取樣時間。Web API 回傳的 `timestamp` 欄位請傳進來，
    ///   App Remote 則用預設的 Date() 即可。
    public func updatePlaybackState(
        trackUri: String? = nil,
        trackName: String,
        artistName: String,
        durationMs: Int,
        progressMs: Int,
        isPlaying: Bool,
        playbackSpeed: Double = 1.0,
        sampledAt: Date = Date()
    ) {
        let uri = trackUri ?? "\(trackName)|\(artistName)"
        let isNewTrack = currentState?.trackUri != uri

        self.baseProgressMs = progressMs + (isPlaying ? latencyCompensationMs : 0)
        self.baseTimestamp = sampledAt
        self.isPlaying = isPlaying
        self.playbackSpeed = playbackSpeed > 0 ? playbackSpeed : 1.0
        self.durationMs = durationMs

        let newState = makeState(uri: uri, trackName: trackName, artistName: artistName)
        self.currentState = newState
        if isNewTrack { trackChanged.send(newState) }

        if isPlaying {
            startLocalInterpolation()
        } else {
            stopLocalInterpolation()
        }
    }

    /// 本地時間戳插值 (Interpolation)：
    /// Spotify 每次暫停/換歌才需要推播一次，中間每毫秒進度由本機系統時間 Date() 動態遞增計算，
    /// 完全零網路耗電！
    public func getCurrentInterpolatedProgressMs() -> Int {
        guard isPlaying else { return baseProgressMs }
        let elapsed = Date().timeIntervalSince(baseTimestamp) * 1000 * playbackSpeed
        let value = baseProgressMs + Int(elapsed)
        return durationMs > 0 ? min(value, durationMs) : value
    }

    private func makeState(uri: String, trackName: String, artistName: String) -> SpotifyTrackState {
        SpotifyTrackState(
            trackUri: uri,
            trackName: trackName,
            artistName: artistName,
            durationMs: durationMs,
            progressMs: getCurrentInterpolatedProgressMs(),
            isPlaying: isPlaying,
            playbackSpeed: playbackSpeed,
            timestamp: Date()
        )
    }

    private func startLocalInterpolation() {
        progressTrackingTimer?.invalidate()
        // 200ms 取樣只在記憶體計算，不打任何網路請求
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying, let current = self.currentState else { return }
            self.currentState = self.makeState(uri: current.trackUri, trackName: current.trackName, artistName: current.artistName)
        }
        // .common：使用者捲動 UI 時 Timer 也不會暫停
        RunLoop.main.add(timer, forMode: .common)
        progressTrackingTimer = timer
    }

    private func stopLocalInterpolation() {
        progressTrackingTimer?.invalidate()
        progressTrackingTimer = nil
    }
}

#if canImport(SpotifyiOS)
import SpotifyiOS

/// 將 Spotify App Remote SDK 的 PlayerState 餵給 SpotifyRemoteManager。
/// 用法：appRemote.playerAPI?.delegate = SpotifyPlayerStateBridge.shared
///       appRemote.playerAPI?.subscribe(toPlayerState: nil)
public final class SpotifyPlayerStateBridge: NSObject, SPTAppRemotePlayerStateDelegate {
    public static let shared = SpotifyPlayerStateBridge()

    public func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let track = playerState.track
        DispatchQueue.main.async {
            SpotifyRemoteManager.shared.updatePlaybackState(
                trackUri: track.uri,
                trackName: track.name,
                artistName: track.artist.name,
                durationMs: Int(track.duration),
                progressMs: playerState.playbackPosition,
                isPlaying: !playerState.isPaused,
                playbackSpeed: Double(playerState.playbackSpeed)
            )
        }
    }
}
#endif
