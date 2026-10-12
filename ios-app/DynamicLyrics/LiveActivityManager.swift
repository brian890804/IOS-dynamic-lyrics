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

    // 專屬更新佇列任務與最後推送狀態
    private var pendingUpdateTask: Task<Void, Never>? = nil
    private var lastEmittedLyric: String = ""
    private var lastEmittedIsPlaying: Bool? = nil

    private init() {
        if #available(iOS 16.1, *) {
            self.currentActivity = Activity<LyricAttributes>.activities.first
            self.isRunning = self.currentActivity != nil
        }
    }

    /// 啟動 Live Activity (支援 4 行歌詞)
    public func startActivity(
        songId: String,
        trackName: String,
        artistName: String,
        prevLyric: String = "",
        currentLyric: String,
        nextLyric1: String,
        nextLyric2: String = "",
        progressMs: Int,
        durationMs: Int,
        lineDurationSec: Double = 4.0
    ) {
        guard #available(iOS 16.1, *) else {
            print("Live Activities require iOS 16.1+")
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("使用者未開啟 Live Activities 權限")
            return
        }

        // 先清理既有任務
        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil

        let attributes = LyricAttributes(songId: songId)
        let now = Date()
        let initialContentState = LyricAttributes.ContentState(
            trackName: trackName,
            artistName: artistName,
            albumArtUrl: nil,
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
            print("成功啟動 Live Activity ID: \(activity.id)")
        } catch {
            print("啟動 Live Activity 失敗: \(error.localizedDescription)")
        }
    }

    /// 高頻有序推送更新 (支援 4 行歌詞)
    public func updateLyric(
        trackName: String,
        artistName: String,
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

        // 如果目前這句歌詞與上一句完全相同，且播送狀態未變，避免重複推播被系統節流
        if currentLyric == lastEmittedLyric && isPlaying == lastEmittedIsPlaying {
            return
        }
        self.lastEmittedLyric = currentLyric
        self.lastEmittedIsPlaying = isPlaying

        let now = Date()
        let updatedState = LyricAttributes.ContentState(
            trackName: trackName,
            artistName: artistName,
            albumArtUrl: nil,
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

        // 串列式推播：等待上一個 update 完成後再推送最新的，避免亂序 (Out-of-order)
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

    /// 結束活動
    public func endActivity() async {
        guard #available(iOS 16.1, *), let activity = currentActivity else { return }
        
        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil
        self.lastEmittedLyric = ""
        self.lastEmittedIsPlaying = nil

        await activity.end(dismissalPolicy: .immediate)
        self.currentActivity = nil
        self.isRunning = false
        print("已結束 Live Activity")
    }
}
