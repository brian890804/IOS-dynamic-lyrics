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

public struct LyricLiveActivityWidget: Widget {
    public init() {}

    private let themeOrange = Color(red: 1.0, green: 0.48, blue: 0.12) // #FF7A1F
    private let darkBg = Color(red: 0.05, green: 0.05, blue: 0.06)     // 純淨曜石黑

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricAttributes.self) { context in
            // ==========================================
            // CarPlay 儀表板小工具卡片 & iPhone 鎖定畫面
            // ==========================================
            VStack(alignment: .leading, spacing: 8) {
                // 頂部歌曲資訊列：精緻圓角專輯封面 + 歌名/歌手
                HStack(spacing: 10) {
                    // 專輯封面卡片
                    if let artUrl = context.state.albumArtUrl, let url = URL(string: artUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                fallbackAlbumArt
                            }
                        }
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    } else {
                        fallbackAlbumArt
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.state.trackName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(themeOrange)
                            .lineLimit(1)
                        Text(context.state.artistName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.45))
                            .lineLimit(1)
                    }

                    Spacer()
                }

                // 4 行滿版歌詞主體：滑順切換無閃爍、純文字染色絕無背景溢色
                VStack(alignment: .leading, spacing: 7) {
                    // 第 1 條：之前唱過的 (大字 15pt、微淡灰)
                    Text(context.state.prevLyric.isEmpty ? " " : context.state.prevLyric)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.32))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .animation(.easeInOut(duration: 0.35), value: context.state.prevLyric)

                    // 第 2 條：當下演唱主行 (24pt 滿版大字號、極致加粗、純文字逐字橘色染色、無閃爍滑順切換)
                    HStack {
                        KaraokeFocusLine(
                            text: context.state.currentLyric,
                            startTime: context.state.lineStartTime,
                            endTime: context.state.lineEndTime,
                            highlightColor: themeOrange
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut(duration: 0.35), value: context.state.currentLyric)

                    // 第 3 條：下一句即將唱 (大字 17pt、高亮白)
                    Text(context.state.nextLyric1.isEmpty ? " " : context.state.nextLyric1)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .animation(.easeInOut(duration: 0.35), value: context.state.nextLyric1)

                    // 第 4 條：下下句未來預覽 (14pt、次微淡)
                    Text(context.state.nextLyric2.isEmpty ? " " : context.state.nextLyric2)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.35))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .animation(.easeInOut(duration: 0.35), value: context.state.nextLyric2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(darkBg)

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
    }

    private var fallbackAlbumArt: some View {
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

/// 焦點行：超大字體、純文字染色 (絕不渲染背景色塊)、互補遮罩防白邊溢出
struct KaraokeFocusLine: View {
    let text: String
    let startTime: Date
    let endTime: Date
    let highlightColor: Color

    var body: some View {
        ZStack(alignment: .leading) {
            // 右側未唱區域：純白色 (動態向右縮減，已唱區域完全不渲染底層白字，絕無毛邊殘影)
            Text(text)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .mask(alignment: .trailing) {
                    ProgressView(timerInterval: startTime...endTime, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(PureTextMaskProgressStyle(alignment: .trailing))
                }

            // 左側已唱區域：純活力橘色 (動態由左向右推進，底層為純黑背景，飽和度極致通透)
            Text(text)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(highlightColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .mask(alignment: .leading) {
                    ProgressView(timerInterval: startTime...endTime, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(PureTextMaskProgressStyle(alignment: .leading))
                }
        }
    }
}

struct PureTextMaskProgressStyle: ProgressViewStyle {
    var alignment: Alignment = .leading

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geo in
            let fraction = CGFloat(configuration.fractionCompleted ?? 1.0)
            Rectangle()
                .fill(Color.black) // 在 mask 中僅作為不透明度通道揭露文字，不帶任何外顯顏色
                .frame(width: max(0, min(geo.size.width, geo.size.width * fraction)))
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }
}
