//
//  LyricWidget.swift
//  LyricWidgetExtension
//
//  負責 CarPlay 儀表板小工具、iPhone 鎖定畫面及動態島 (Dynamic Island) 渲染
//  極簡黑橘 (Obsidian & Amber Orange)、圓角黑膠專輯封面、現代感排版、自適應大字體
//

import WidgetKit
import SwiftUI
import ActivityKit

@main
struct LyricWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyricLiveActivityWidget()
    }
}

public struct LyricLiveActivityWidget: Widget {
    public init() {}

    private let themeOrange = Color(red: 1.0, green: 0.48, blue: 0.12) // #FF7A1F
    private let darkBg = Color(red: 0.05, green: 0.05, blue: 0.06)     // 純淨曜石黑

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricAttributes.self) { context in
            // ==========================================
            // CarPlay (.small) & iPhone 鎖定畫面 (.medium)
            // ==========================================
            LyricActivityView(state: context.state, themeOrange: themeOrange, darkBg: darkBg)
                .activityBackgroundTint(darkBg)
                .activitySystemActionForegroundColor(themeOrange)

        } dynamicIsland: { context in
            // ==========================================
            // iPhone 動態島 (黑橘現代感)
            // ==========================================
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
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
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(themeOrange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(context.state.nextLyric1)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .padding(.top, 4)
                    .animation(.easeInOut(duration: 0.35), value: context.state.currentLyric)
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
                    .animation(.easeInOut(duration: 0.3), value: context.state.currentLyric)
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundColor(themeOrange)
            }
        }
        // .small：CarPlay (iOS 26+) 與 Apple Watch 智慧型疊放使用的精簡版面
        .supplementalActivityFamilies([.small, .medium])
    }
}

/// 依 activityFamily 切換版面：CarPlay 為 .small，iPhone 鎖定畫面為 .medium
private struct LyricActivityView: View {
    @Environment(\.activityFamily) private var activityFamily

    let state: LyricAttributes.ContentState
    let themeOrange: Color
    let darkBg: Color

    var body: some View {
        switch activityFamily {
        case .small:
            smallLayout
        default:
            mediumLayout
        }
    }

    /// CarPlay 儀表板：空間小、需一眼可讀，只顯示當前句 + 下一句
    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.trackName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.5))
                .lineLimit(1)

            Text(state.currentLyric.isEmpty ? " " : state.currentLyric)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(themeOrange)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.35), value: state.currentLyric)

            Text(state.nextLyric1.isEmpty ? " " : state.nextLyric1)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(darkBg)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 頂部歌曲資訊列：精緻圓角專輯封面 + 歌名/歌手
            HStack(spacing: 10) {
                // Live Activity 無法下載網路圖片 (AsyncImage 在 Widget 中不會載入)，固定使用主題封面
                LyricFallbackArt(themeOrange: themeOrange)

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.trackName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(themeOrange)
                        .lineLimit(1)
                    Text(state.artistName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer()
            }

            // 4 行滿版歌詞主體：滑順切換無閃爍、純文字染色絕無背景溢色
            VStack(alignment: .leading, spacing: 7) {
                // 第 1 條：之前唱過的 (大字 15pt、微淡灰)
                Text(state.prevLyric.isEmpty ? " " : state.prevLyric)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.32))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .animation(.easeInOut(duration: 0.35), value: state.prevLyric)

                // 第 2 條：當下演唱主行 (24pt 滿版大字號、極致加粗、經典純橘色、無閃爍滑順切換)
                Text(state.currentLyric.isEmpty ? " " : state.currentLyric)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(themeOrange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.35), value: state.currentLyric)

                // 第 3 條：下一句即將唱 (大字 17pt、高亮白)
                Text(state.nextLyric1.isEmpty ? " " : state.nextLyric1)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .animation(.easeInOut(duration: 0.35), value: state.nextLyric1)

                // 第 4 條：下下句未來預覽 (14pt、次微淡)
                Text(state.nextLyric2.isEmpty ? " " : state.nextLyric2)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .animation(.easeInOut(duration: 0.35), value: state.nextLyric2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(darkBg)
    }
}

private struct LyricFallbackArt: View {
    let themeOrange: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [themeOrange.opacity(0.8), Color.black], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "music.note")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 38, height: 38)
    }
}
