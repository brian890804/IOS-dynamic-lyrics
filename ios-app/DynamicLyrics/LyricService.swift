//
//  LyricService.swift
//  DynamicLyrics
//
//  負責串接 Lrclib API 抓取同步時間軸歌詞
//  具備多層級 Fallback 機制 (精確比對+時長 -> 結構化搜尋 -> 繁簡轉換 -> 關鍵字搜尋 -> 單曲名+時長)
//

import Foundation

public struct LrclibItem: Codable {
    public let id: Int?
    public let trackName: String?
    public let artistName: String?
    public let albumName: String?
    public let duration: Double?
    public let instrumental: Bool?
    public let syncedLyrics: String?
    public let plainLyrics: String?
}

public class LyricService {
    public static let shared = LyricService()
    private init() {}

    /// 純音樂時回傳的佔位歌詞
    public static let instrumentalPlaceholder = "♪ 純音樂 ♪"

    /// 繁 → 簡：使用系統 ICU Transform，涵蓋所有歌手而非僅寫死的名單
    private func toSimplified(_ s: String) -> String? {
        let converted = s.applyingTransform(StringTransform("Hant-Hans"), reverse: false)
        return (converted != nil && converted != s) ? converted : nil
    }

    /// 移除 Spotify 歌名後綴 (Remastered / feat. / with / Radio Edit)。
    /// 刻意保留 Live / Acoustic / Remix —— 那些版本時間軸不同。
    static func stripTrackDecorations(_ track: String) -> String {
        var t = track
        t = t.replacingOccurrences(
            of: #"\s*[-–]\s*(\d{4}\s+)?(Remaster(ed)?|Radio Edit|Single Version|Mono|Stereo)\b.*$"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(
            of: #"\s*[(\[](feat\.?|ft\.?|with)\s[^)\]]*[)\]]"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? track : trimmed
    }

    /// "A, B" / "A & B" / "A feat. B" → "A"
    static func primaryArtist(_ artist: String) -> String {
        let parts = artist.components(separatedBy: CharacterSet(charactersIn: ",&、"))
        var first = parts.first ?? artist
        if let r = first.range(of: #"\s(feat\.?|ft\.?|x)\s"#, options: [.regularExpression, .caseInsensitive]) {
            first = String(first[..<r.lowerBound])
        }
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 智慧抓取時間軸歌詞
    /// - Parameter durationSec: Spotify 回報的歌曲長度 (秒)。強烈建議傳入，
    ///   否則 lrclib 可能回傳 Live 版等不同長度的時間軸 (實測：五月天《溫柔》會抓到 396s 的 Live 版)
    public func fetchLyrics(trackName: String, artistName: String, durationSec: Double? = nil) async throws -> [LyricLine] {
        let rawTrack = trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTrack = Self.stripTrackDecorations(rawTrack)
        let cleanArtist = Self.primaryArtist(artistName.trimmingCharacters(in: .whitespacesAndNewlines))
        let dur = durationSec.map { Int($0.rounded()) }

        var trackCandidates = [rawTrack]
        if cleanTrack != rawTrack { trackCandidates.append(cleanTrack) }
        var artistCandidates = [cleanArtist]
        if let sim = toSimplified(cleanArtist) { artistCandidates.append(sim) }

        // 策略 1：精確比對 /api/get (帶 duration → lrclib 只回 ±2 秒內版本)
        for track in trackCandidates {
            for artist in artistCandidates {
                var q = [URLQueryItem(name: "track_name", value: track),
                         URLQueryItem(name: "artist_name", value: artist)]
                if let dur = dur { q.append(URLQueryItem(name: "duration", value: String(dur))) }
                guard let item: LrclibItem = try? await request("get", q) else { continue }
                if item.instrumental == true {
                    return [LyricLine(timeMs: 0, text: Self.instrumentalPlaceholder)]
                }
                if let synced = item.syncedLyrics, LrcParser.hasValidTimestamps(in: synced) {
                    return LrcParser.parse(lrcContent: synced)
                }
            }
        }

        // 策略 2：結構化搜尋 /api/search?track_name=&artist_name=
        for artist in artistCandidates {
            let q = [URLQueryItem(name: "track_name", value: cleanTrack),
                     URLQueryItem(name: "artist_name", value: artist)]
            if let items: [LrclibItem] = try? await request("search", q),
               let best = pickBest(items, track: cleanTrack, durationSec: dur) {
                return LrcParser.parse(lrcContent: best)
            }
        }

        // 策略 3：關鍵字搜尋 /api/search?q=歌名 歌手
        for artist in artistCandidates {
            let q = [URLQueryItem(name: "q", value: "\(cleanTrack) \(artist)")]
            if let items: [LrclibItem] = try? await request("search", q),
               let best = pickBest(items, track: cleanTrack, durationSec: dur) {
                return LrcParser.parse(lrcContent: best)
            }
        }

        // 策略 4：僅歌名 (歌手中英名不一致，如 薛之謙 ↔ Joker Xue)。
        // 同名歌太多，必須有時長且誤差 <= 3 秒才接受
        if let dur = dur,
           let items: [LrclibItem] = try? await request("search", [URLQueryItem(name: "q", value: cleanTrack)]) {
            let exact = items.filter { $0.trackName?.lowercased() == cleanTrack.lowercased() }
            if let best = pickBest(exact, track: cleanTrack, durationSec: dur, tolerance: 3) {
                return LrcParser.parse(lrcContent: best)
            }
        }

        return []
    }

    /// 回傳最佳候選的 syncedLyrics：歌名相符 + 有時間軸 + 時長最接近
    private func pickBest(_ items: [LrclibItem], track: String, durationSec: Int?, tolerance: Double = 5) -> String? {
        var candidates = items.filter { item in
            guard let name = item.trackName, name.localizedCaseInsensitiveContains(track),
                  let synced = item.syncedLyrics else { return false }
            return LrcParser.hasValidTimestamps(in: synced)
        }
        if let dur = durationSec.map(Double.init) {
            candidates = candidates
                .filter { ($0.duration).map { abs($0 - dur) <= tolerance } ?? false }
                .sorted { abs(($0.duration ?? 0) - dur) < abs(($1.duration ?? 0) - dur) }
        }
        return candidates.first?.syncedLyrics
    }

    private func request<T: Decodable>(_ endpoint: String, _ queryItems: [URLQueryItem]) async throws -> T? {
        var components = URLComponents(string: "https://lrclib.net/api/\(endpoint)")
        components?.queryItems = queryItems
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("IOS-Dynamic-Lyrics-Client/2.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
