//
//  LyricAttributes.swift
//  DynamicLyrics
//
//  Created for iOS Dynamic Lyrics (CarPlay & Dynamic Island)
//

import Foundation
import ActivityKit

/// 定義 Live Activity 的靜態屬性與即時動態狀態
public struct LyricAttributes: ActivityAttributes {
    public var songId: String

    public init(songId: String) {
        self.songId = songId
    }

    /// 每次歌詞推進時更新的動態狀態 (支援 4 行視圖與逐字卡拉OK時間區間)
    public struct ContentState: Codable, Hashable {
        public var trackName: String
        public var artistName: String
        public var albumArtUrl: String?
        
        // 4 行歌詞架構：
        // Line 1: 上一句 (已唱過)
        public var prevLyric: String
        // Line 2: 當前句 (正唱中，支援逐字染色)
        public var currentLyric: String
        // Line 3: 下一句 (即將唱)
        public var nextLyric1: String
        // Line 4: 下下句 (未來預覽)
        public var nextLyric2: String
        
        public var progressMs: Int
        public var durationMs: Int
        public var isPlaying: Bool
        
        // 當前句時間區間 (SwiftUI timerInterval 驅動漸層染色)
        public var lineStartTime: Date
        public var lineEndTime: Date

        public init(
            trackName: String,
            artistName: String,
            albumArtUrl: String? = nil,
            prevLyric: String = "",
            currentLyric: String = "",
            nextLyric1: String = "",
            nextLyric2: String = "",
            progressMs: Int = 0,
            durationMs: Int = 0,
            isPlaying: Bool = true,
            lineStartTime: Date = Date(),
            lineEndTime: Date = Date().addingTimeInterval(4)
        ) {
            self.trackName = trackName
            self.artistName = artistName
            self.albumArtUrl = albumArtUrl
            self.prevLyric = prevLyric
            self.currentLyric = currentLyric
            self.nextLyric1 = nextLyric1
            self.nextLyric2 = nextLyric2
            self.progressMs = progressMs
            self.durationMs = durationMs
            self.isPlaying = isPlaying
            self.lineStartTime = lineStartTime
            self.lineEndTime = lineEndTime
        }
    }
}
