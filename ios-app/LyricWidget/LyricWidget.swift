//
//  LyricWidget.swift
//  LyricWidgetExtension
//
//  負責 CarPlay 儀表板小工具、iPhone 鎖定畫面及動態島 (Dynamic Island) 渲染
//  極簡黑橘 (Obsidian & Vivid Amber Orange) 配色、純文字逐字染色、滿版大字體
//

import WidgetKit
import SwiftUI
import ActivityKit

public struct LyricLiveActivityWidget: Widget {
    public init() {}

    // 主題配色：深黑底 + 亮活力橘
    private let themeOrange = Color(red: 1.0, green: 0.48, blue: 0.12) // #FF7A1F
    private let darkBg = Color(red: 0.05, green: 0.05, blue: 0.06)     // 純淨極深曜石黑

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricAttributes.self) { context in
            // ==========================================
            // CarPlay 儀表板小工具卡片 & iPhone 鎖定畫面 (黑橘純文字滿版)
            // ==========================================
            VStack(alignment: .leading, spacing: 6) {
                // 頂部歌曲資訊 (簡潔緊湊，將空間留給歌詞滿版)
                HStack(spacing: 6) {
                    Text(context.state.trackName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(themeOrange)
                        .lineLimit(1)
                    Text("• " + context.state.artistName)
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.45))
                        .lineLimit(1)
                    Spacer()
                }

                // 4 行滿版歌詞主體
                VStack(alignment: .leading, spacing: 6) {
                    // 第 1 條：之前唱過的 (低調微淡，字體加大)
                    Text(context.state.prevLyric.isEmpty ? " " : context.state.prevLyric)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.32))
                        .lineLimit(1)

                    // 第 2 條：當下正在唱的 (滿版大字號 20pt、極致加粗、純文字黑橘逐字染色)
                    HStack {
                        KaraokeFocusLine(
                            text: context.state.currentLyric,
                            startTime: context.state.lineStartTime,
                            endTime: context.state.lineEndTime,
                            highlightColor: themeOrange
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("focus-\(context.state.currentLyric)")

                    // 第 3 條：下一句即將唱的 (大字號 16pt、明亮白)
                    Text(context.state.nextLyric1.isEmpty ? " " : context.state.nextLyric1)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.75))
                        .lineLimit(1)

                    // 第 4 條：下下句未來的 (13pt、次微淡)
                    Text(context.state.nextLyric2.isEmpty ? " " : context.state.nextLyric2)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.35))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(darkBg) // 純粹深黑底色，不加任何花俏外框或背景變色區塊

        } dynamicIsland: { context in
            // ==========================================
            // iPhone 動態島 (黑橘風格)
            // ==========================================
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundColor(themeOrange)
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

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.currentLyric)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(themeOrange)
                            .lineLimit(1)
                        Text(context.state.nextLyric1)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundColor(themeOrange)
            } compactTrailing: {
                Text(context.state.currentLyric)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(themeOrange)
                    .frame(maxWidth: 135, alignment: .trailing)
                    .lineLimit(1)
                    .id("compact-\(context.state.currentLyric)")
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundColor(themeOrange)
            }
        }
    }
}

/// 焦點行：只有字體從左至右變為活力橘色，背景完全乾淨透明無任何方塊
struct KaraokeFocusLine: View {
    let text: String
    let startTime: Date
    let endTime: Date
    let highlightColor: Color

    var body: some View {
        ZStack(alignment: .leading) {
            // 底層：預設亮白文字
            Text(text)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            // 頂層染色層：活力亮橘，以 ProgressView 驅動文字遮罩 (Mask)
            Text(text)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(highlightColor)
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

/// 客製化遮罩進度條：平滑推進剪裁寬度
struct ContinuousMaskProgressStyle: ProgressViewStyle {
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let fraction = CGFloat(configuration.fractionCompleted ?? 1.0)
        Rectangle()
            .frame(width: max(0, width * fraction))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
