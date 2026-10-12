//
//  LiveActivityManager.swift
//  DynamicLyrics
//
//  負責啟動、更新與結束 iOS ActivityKit (Live Activity)
//  具備有序非同步串列佇列 (Serial FIFO Update Queue) 防止多執行緒亂序與丟幀
//

import Foundation
import ActivityKit
import Combine

@MainActor
public class LiveActivityManager: ObservableObject {
    public static let shared = LiveActivityManager()

    @Published public private(set) var currentActivity: Activity<LyricAttributes>? = nil
    @Published public private(set) var isRunning: Bool = false

    private var pendingUpdateTask: Task<Void, Never>? = nil
    private var lastEmittedLyric: String = ""
    private var lastEmittedIsPlaying: Bool? = nil

    private init() {
        if #available(iOS 16.1, *) {
            self.currentActivity = Activity<LyricAttributes>.activities.first
            self.isRunning = self.currentActivity != nil
        }
    }

    /// 啟動 Live Activity (支援專輯封面與 4 行歌詞)
    public func startActivity(
        songId: String,
        trackName: String,
        artistName: String,
        albumArtUrl: String? = nil,
        prevLyric: String = "",
        currentLyric: String,
        nextLyric1: String,
        nextLyric2: String = "",
        progressMs: Int,
        durationMs: Int,
        lineDurationSec: Double = 4.0
    ) {
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil

        let attributes = LyricAttributes(songId: songId)
        let now = Date()
        let initialContentState = LyricAttributes.ContentState(
            trackName: trackName,
            artistName: artistName,
            albumArtUrl: albumArtUrl,
            prevLyric: prevLyric,
            currentLyric: currentLyric,
            nextLyric1: nextLyric1,
            nextLyric2: nextLyric2,
            progressMs: progressMs,
            durationMs: durationMs,
            isPlaying: true,
            lineStartTime: now,
            lineEndTime: now.addingTimeInterval(lineDurationSec)
        )

        do {
            let activity = try Activity<LyricAttributes>.request(
                attributes: attributes,
                contentState: initialContentState,
                pushType: nil
            )
            self.currentActivity = activity
            self.isRunning = true
            self.lastEmittedLyric = currentLyric
            self.lastEmittedIsPlaying = true
        } catch {
            print("啟動 Live Activity 失敗: \(error.localizedDescription)")
        }
    }

    /// 高頻有序推送更新 (支援專輯封面與 4 行歌詞)
    public func updateLyric(
        trackName: String,
        artistName: String,
        albumArtUrl: String? = nil,
        prevLyric: String = "",
        currentLyric: String,
        nextLyric1: String,
        nextLyric2: String = "",
        progressMs: Int,
        durationMs: Int,
        isPlaying: Bool,
        lineDurationSec: Double = 4.0
    ) {
        guard #available(iOS 16.1, *), let activity = currentActivity else { return }

        if currentLyric == lastEmittedLyric && isPlaying == lastEmittedIsPlaying {
            return
        }
        self.lastEmittedLyric = currentLyric
        self.lastEmittedIsPlaying = isPlaying

        let now = Date()
        let updatedState = LyricAttributes.ContentState(
            trackName: trackName,
            artistName: artistName,
            albumArtUrl: albumArtUrl,
            prevLyric: prevLyric,
            currentLyric: currentLyric,
            nextLyric1: nextLyric1,
            nextLyric2: nextLyric2,
            progressMs: progressMs,
            durationMs: durationMs,
            isPlaying: isPlaying,
            lineStartTime: now,
            lineEndTime: now.addingTimeInterval(lineDurationSec)
        )

        let previousTask = pendingUpdateTask
        pendingUpdateTask = Task {
            _ = await previousTask?.result
            if Task.isCancelled { return }

            if #available(iOS 16.2, *) {
                let staleDate = now.addingTimeInterval(lineDurationSec * 1.5)
                let content = ActivityContent(state: updatedState, staleDate: staleDate)
                await activity.update(content)
            } else {
                await activity.update(using: updatedState)
            }
        }
    }

    public func endActivity() async {
        guard #available(iOS 16.1, *), let activity = currentActivity else { return }
        
        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil
        self.lastEmittedLyric = ""
        self.lastEmittedIsPlaying = nil

        await activity.end(dismissalPolicy: .immediate)
        self.currentActivity = nil
        self.isRunning = false
    }
}
