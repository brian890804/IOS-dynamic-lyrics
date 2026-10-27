//
//  SpotifyWebPoller.swift
//  DynamicLyrics
//
//  透過 Spotify Web API `GET /v1/me/player/currently-playing` 取得真實播放狀態，
//  餵給 SpotifyRemoteManager 做本地插值。
//
//  同步模型：每 3 秒輪詢一次；只有在「換歌 / 播放暫停切換 / 進度偏差超過門檻 (使用者拖動)」
//  時才重設插值基準，避免網路延遲抖動讓歌詞來回跳行。
//  背景執行靠 BackgroundAudioManager 的靜音保活維持。
//

import Foundation

@MainActor
public final class SpotifyWebPoller: ObservableObject {
    public static let shared = SpotifyWebPoller()

    @Published public private(set) var isRunning = false
    @Published public private(set) var status: String = "未連線"

    private var pollTask: Task<Void, Never>?
    private let playingInterval: TimeInterval = 3
    private let idleInterval: TimeInterval = 5
    /// 本地插值與 Spotify 回報差距超過此值才重新校正 (毫秒)
    private let resyncThresholdMs = 1200

    private init() {}

    public func start() {
        guard pollTask == nil else { return }
        isRunning = true
        status = "連線中…"
        BackgroundAudioManager.shared.startKeepAlive()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                let delay = await self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        isRunning = false
        status = "已停止"
        BackgroundAudioManager.shared.stopKeepAlive()
    }

    /// 回傳下一次輪詢前要等待的秒數
    private func pollOnce() async -> TimeInterval {
        do {
            let token = try await SpotifyAuthManager.shared.validAccessToken()
            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 8

            let sentAt = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            let receivedAt = Date()
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            switch statusCode {
            case 200:
                let payload = try JSONDecoder().decode(CurrentlyPlaying.self, from: data)
                guard let item = payload.item else {
                    // 廣告或 Podcast 等沒有 track 資料
                    status = "Spotify 播放中 (非歌曲內容)"
                    return idleInterval
                }
                // 以請求來回的中點當作 progress_ms 的取樣時間
                let sampledAt = sentAt.addingTimeInterval(receivedAt.timeIntervalSince(sentAt) / 2)
                apply(item: item, progressMs: payload.progress_ms ?? 0, isPlaying: payload.is_playing, sampledAt: sampledAt)
                status = payload.is_playing ? "同步中：\(item.name)" : "Spotify 已暫停"
                return payload.is_playing ? playingInterval : idleInterval

            case 204:
                status = "Spotify 目前沒有播放"
                markPausedIfNeeded()
                return idleInterval

            case 401:
                SpotifyAuthManager.shared.invalidateAccessToken()
                return 1

            case 429:
                let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) } ?? 10
                status = "Spotify 請求過於頻繁，\(Int(retryAfter)) 秒後重試"
                return max(retryAfter, playingInterval)

            default:
                status = "Spotify 回應錯誤 (HTTP \(statusCode))"
                return idleInterval
            }
        } catch SpotifyAuthError.notConnected {
            status = "請重新登入 Spotify"
            return 15
        } catch {
            status = "網路錯誤：\(error.localizedDescription)"
            return idleInterval
        }
    }

    private func apply(item: CurrentlyPlaying.Item, progressMs: Int, isPlaying: Bool, sampledAt: Date) {
        let remote = SpotifyRemoteManager.shared
        if let current = remote.currentState,
           current.trackUri == item.uri,
           current.isPlaying == isPlaying {
            let estimatedNow = progressMs + (isPlaying ? Int(Date().timeIntervalSince(sampledAt) * 1000) : 0)
            if abs(estimatedNow - remote.getCurrentInterpolatedProgressMs()) < resyncThresholdMs {
                return
            }
        }

        remote.updatePlaybackState(
            trackUri: item.uri,
            trackName: item.name,
            artistName: item.artists?.first?.name ?? "",
            durationMs: item.duration_ms,
            progressMs: progressMs,
            isPlaying: isPlaying,
            sampledAt: sampledAt
        )
    }

    private func markPausedIfNeeded() {
        let remote = SpotifyRemoteManager.shared
        guard let current = remote.currentState, current.isPlaying else { return }
        remote.updatePlaybackState(
            trackUri: current.trackUri,
            trackName: current.trackName,
            artistName: current.artistName,
            durationMs: current.durationMs,
            progressMs: remote.getCurrentInterpolatedProgressMs(),
            isPlaying: false
        )
    }
}

private struct CurrentlyPlaying: Decodable {
    let is_playing: Bool
    let progress_ms: Int?
    let item: Item?

    struct Item: Decodable {
        let uri: String
        let name: String
        let duration_ms: Int
        let artists: [Artist]?
    }

    struct Artist: Decodable {
        let name: String
    }
}
