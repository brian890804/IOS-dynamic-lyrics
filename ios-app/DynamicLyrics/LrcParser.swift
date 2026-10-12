//
//  LrcParser.swift
//  DynamicLyrics
//
//  解析標準與毫秒級 LRC 格式歌詞，支援 4 行視圖與多重複時間標籤
//

import Foundation

public struct LyricLine: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public let timeMs: Int
    public let text: String

    public init(timeMs: Int, text: String) {
        self.timeMs = timeMs
        self.text = text
    }
}

public struct LyricMatch4Lines {
    public let prevText: String
    public let currentText: String
    public let nextText1: String
    public let nextText2: String
    public let currentLineDurationMs: Int
    public let currentIndex: Int

    public init(
        prevText: String,
        currentText: String,
        nextText1: String,
        nextText2: String,
        currentLineDurationMs: Int,
        currentIndex: Int
    ) {
        self.prevText = prevText
        self.currentText = currentText
        self.nextText1 = nextText1
        self.nextText2 = nextText2
        self.currentLineDurationMs = currentLineDurationMs
        self.currentIndex = currentIndex
    }
}

public class LrcParser {
    public static func hasValidTimestamps(in content: String) -> Bool {
        let pattern = "\\[\\d{2}:\\d{2}(?:\\.\\d{2,3})?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.firstMatch(in: content, range: range) != nil
    }

    public static func cleanText(_ rawText: String) -> String {
        var cleaned = rawText
        cleaned = cleaned.replacingOccurrences(of: "\u{FFFD}", with: "")
        cleaned = cleaned.components(separatedBy: .controlCharacters).joined(separator: " ")
        let parts = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 解析 LRC 內容，支援同一行多個時間戳 (如副歌重複 [01:20][02:30] 歌詞)
    public static func parse(lrcContent: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let rawLines = lrcContent.components(separatedBy: .newlines)
        
        // 正則匹配時間戳
        let timePattern = "\\[(\\d{2}):(\\d{2})(?:\\.(\\d{2,3}))?\\]"
        guard let timeRegex = try? NSRegularExpression(pattern: timePattern, options: []) else {
            return []
        }

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let nsRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            let matches = timeRegex.matches(in: trimmed, options: [], range: nsRange)
            guard !matches.isEmpty else { continue }

            // 提取時間戳後面的歌詞純文字
            var text = trimmed
            for match in matches.reversed() {
                if let r = Range(match.range, in: text) {
                    text.removeSubrange(r)
                }
            }
            let cleanedLyric = cleanText(text)
            guard !cleanedLyric.isEmpty else { continue }

            // 依序將多個時間標籤各自展開為獨立行
            for match in matches {
                let minRange = match.range(at: 1)
                let secRange = match.range(at: 2)
                let msRange = match.range(at: 3)

                let minutes = Int((trimmed as NSString).substring(with: minRange)) ?? 0
                let seconds = Int((trimmed as NSString).substring(with: secRange)) ?? 0

                var milliseconds = 0
                if msRange.location != NSNotFound {
                    let msStr = (trimmed as NSString).substring(with: msRange)
                    milliseconds = msStr.count == 2 ? (Int(msStr) ?? 0) * 10 : (Int(msStr) ?? 0)
                }

                let totalMs = minutes * 60 * 1000 + seconds * 1000 + milliseconds
                lines.append(LyricLine(timeMs: totalMs, text: cleanedLyric))
            }
        }

        return lines.sorted { $0.timeMs < $1.timeMs }
    }

    /// 根據歌詞字數與兩行時間差計算自然演唱時長 (避免間奏過長導致逐字推進過慢)
    public static func calculateLineDuration(text: String, gapMs: Int) -> Int {
        let clean = text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let charCount = max(4, clean.count)
        // 中文標準流行語速：每字約 320ms ~ 350ms
        let naturalSingingMs = charCount * 330

        if gapMs > naturalSingingMs + 1000 {
            // 兩句之間有間奏或過門音樂：以自然演唱時間為主，唱完停留在 100% 亮橘色
            return min(naturalSingingMs, max(1600, gapMs - 800))
        } else if gapMs > 1200 {
            // 正常句間換氣：在下一句前留 200ms 空檔
            return max(1200, min(naturalSingingMs, gapMs - 200))
        } else {
            // 快節奏連續演唱
            return max(800, Int(Double(gapMs) * 0.9))
        }
    }

    /// 根據毫秒進度匹配 4 行歌詞：
    /// Line 1: 上一句 (已唱過)
    /// Line 2: 當前句 (正唱中)
    /// Line 3: 下一句 (即將唱)
    /// Line 4: 下下句 (未來預覽)
    public static func find4Lines(in lines: [LyricLine], progressMs: Int) -> LyricMatch4Lines {
        guard !lines.isEmpty else {
            return LyricMatch4Lines(prevText: "", currentText: "無時間軸歌詞", nextText1: "", nextText2: "", currentLineDurationMs: 4000, currentIndex: -1)
        }

        // 前奏階段
        if progressMs < lines[0].timeMs {
            let duration = max(1000, lines[0].timeMs - progressMs)
            let next1 = lines[0].text
            let next2 = lines.count > 1 ? lines[1].text : ""
            return LyricMatch4Lines(
                prevText: "⋯⋯ (前奏)",
                currentText: next1,
                nextText1: next2,
                nextText2: lines.count > 2 ? lines[2].text : "",
                currentLineDurationMs: duration,
                currentIndex: -1
            )
        }

        var currentIndex = 0
        for (index, line) in lines.enumerated() {
            if line.timeMs <= progressMs {
                currentIndex = index
            } else {
                break
            }
        }

        let prev = (currentIndex > 0) ? lines[currentIndex - 1].text : "⋯⋯"
        let current = lines[currentIndex].text
        let next1 = (currentIndex + 1 < lines.count) ? lines[currentIndex + 1].text : "（尾奏結束）"
        let next2 = (currentIndex + 2 < lines.count) ? lines[currentIndex + 2].text : ""

        let rawGapMs: Int
        if currentIndex + 1 < lines.count {
            rawGapMs = max(500, lines[currentIndex + 1].timeMs - lines[currentIndex].timeMs)
        } else {
            rawGapMs = 4000
        }
        let durationMs = calculateLineDuration(text: current, gapMs: rawGapMs)

        return LyricMatch4Lines(
            prevText: prev,
            currentText: current,
            nextText1: next1,
            nextText2: next2,
            currentLineDurationMs: durationMs,
            currentIndex: currentIndex
        )
    }
}
