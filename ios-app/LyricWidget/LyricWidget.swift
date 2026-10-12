//
//  LyricWidget.swift
//  LyricWidgetExtension
//
//  負責 CarPlay 儀表板小工具、iPhone 鎖定畫面及動態島 (Dynamic Island) 渲染
//  支援 4 行歌詞佈局 + 當前行逐字平滑變色渲染 (Karaoke Sweeping Effect)
//

import WidgetKit
import SwiftUI
import ActivityKit

public struct LyricLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricAttributes.self) { context in
            // ==========================================
            // CarPlay 儀表板小工具卡片 & iPhone 鎖定畫面 (4 行架構)
            // ==========================================
            VStack(alignment: .leading, spacing: 5) {
                // 頂部歌曲資訊
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text(context.state.trackName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.green)
                        .lineLimit(1)
                    Text("• " + context.state.artistName)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                    Spacer()
                }

                // 4 行歌詞核心版面
                VStack(alignment: .leading, spacing: 4) {
                    // 第 1 條：之前唱過的 (半透明淡出，小字號)
                    Text(context.state.prevLyric.isEmpty ? " " : context.state.prevLyric)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.35))
                        .lineLimit(1)

                    // 第 2 條：當下正在唱的 (放大、加粗、卡拉OK動態染色焦點行)
                    HStack {
                        KaraokeFocusLine(
                            text: context.state.currentLyric,
                            startTime: context.state.lineStartTime,
                            endTime: context.state.lineEndTime
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("focus-\(context.state.currentLyric)")

                    // 第 3 條：下一句即將唱的 (次加亮預覽)
                    Text(context.state.nextLyric1.isEmpty ? " " : context.state.nextLyric1)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                        .lineLimit(1)

                    // 第 4 條：下下句未來的 (更淡預覽)
                    Text(context.state.nextLyric2.isEmpty ? " " : context.state.nextLyric2)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.3))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0.08, green: 0.09, blue: 0.12))

        } dynamicIsland: { context in
            // ==========================================
            // iPhone 動態島 (Dynamic Island)
            // ==========================================
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundColor(.green)
                        Text(context.state.trackName)
                            .font(.caption2)
                            .bold()
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.artistName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // 動態島展開態：顯示當前焦點行 + 下一句
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.currentLyric)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundColor(.green)
                            .lineLimit(1)
                        Text(context.state.nextLyric1)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundColor(.green)
            } compactTrailing: {
                // 緊湊態只放當前歌詞
                Text(context.state.currentLyric)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
                    .frame(maxWidth: 130, alignment: .trailing)
                    .lineLimit(1)
                    .id("compact-\(context.state.currentLyric)")
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundColor(.green)
            }
        }
    }
}

/// 焦點行：利用 SwiftUI 文字遮罩 (Mask) 與時間軸實現從左至右逐字染色
struct KaraokeFocusLine: View {
    let text: String
    let startTime: Date
    let endTime: Date

    var body: some View {
        ZStack(alignment: .leading) {
            // 底層：預設白色歌詞
            Text(text)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            // 頂層染色層：螢光綠 / 亮青色，利用 Progress 遮罩隨時間由左向右推進
            Text(text)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(Color.green)
                .lineLimit(1)
                .mask(
                    GeometryReader { proxy in
                        ProgressView(timerInterval: startTime...endTime, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(ContinuousMaskProgressStyle(width: proxy.size.width))
                    }
                )
        }
    }
}

/// 客製化遮罩進度條，驅動從左往右的剪裁矩形
struct ContinuousMaskProgressStyle: ProgressViewStyle {
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let fraction = CGFloat(configuration.fractionCompleted ?? 1.0)
        Rectangle()
            .frame(width: max(0, width * fraction))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
