//
//  ArtworkService.swift
//  DynamicLyrics
//
//  負責拉取歌曲高解析度專輯封面 (Album Artwork)
//  支援 iTunes Search API 公開端點 (免 Spotify 金鑰，即時獲取高畫質封面圖)
//

import Foundation

public class ArtworkService {
    public static let shared = ArtworkService()
    private var cache: [String: String] = [:]

    private init() {}

    /// 取得歌曲專輯封面 URL
    public func fetchArtworkUrl(trackName: String, artistName: String) async -> String? {
        let key = "\(trackName)-\(artistName)".lowercased()
        if let cached = cache[key] {
            return cached
        }

        let query = "\(trackName) \(artistName)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            struct iTunesResult: Decodable {
                struct Item: Decodable {
                    let artworkUrl100: String?
                }
                let results: [Item]
            }

            let decoded = try JSONDecoder().decode(iTunesResult.self, from: data)
            if let first = decoded.results.first, let art = first.artworkUrl100 {
                // 將 100x100 替換為更高清的 300x300
                let highRes = art.replacingOccurrences(of: "100x100bb", with: "300x300bb")
                cache[key] = highRes
                return highRes
            }
        } catch {
            print("[ArtworkService] 抓取封面失敗: \(error)")
        }

        return nil
    }
}
