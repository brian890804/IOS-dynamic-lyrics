//
//  SpotifyAuthManager.swift
//  DynamicLyrics
//
//  Spotify OAuth 2.0 (Authorization Code + PKCE) 登入：
//  不需要 Client Secret，使用者只要在 App 內貼上自己在 Spotify Developer Dashboard
//  申請的 Client ID，並在 Dashboard 登記 Redirect URI = dynamiclyrics://spotify-callback
//

import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit

public enum SpotifyAuthError: LocalizedError {
    case missingClientId
    case notConnected
    case cancelled
    case tokenRequestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingClientId: return "請先輸入 Spotify Client ID"
        case .notConnected: return "尚未登入 Spotify"
        case .cancelled: return "已取消登入"
        case .tokenRequestFailed(let msg): return "Spotify 授權失敗：\(msg)"
        }
    }
}

@MainActor
public final class SpotifyAuthManager: NSObject, ObservableObject {
    public static let shared = SpotifyAuthManager()

    public static let redirectUri = "dynamiclyrics://spotify-callback"
    private static let callbackScheme = "dynamiclyrics"
    private static let scopes = "user-read-currently-playing user-read-playback-state"
    private static let clientIdDefaultsKey = "spotify.clientId"
    private static let refreshTokenKeychainKey = "spotify.refreshToken"

    @Published public var clientId: String {
        didSet { UserDefaults.standard.set(clientId, forKey: Self.clientIdDefaultsKey) }
    }
    @Published public private(set) var isConnected: Bool

    private var accessToken: String?
    private var accessTokenExpiry: Date = .distantPast
    private var refreshTask: Task<String, Error>?
    private var authSession: ASWebAuthenticationSession?

    private override init() {
        // 使用者在 App 內輸入過就用輸入值，否則用 Info.plist 內建的 SpotifyClientID
        let saved = UserDefaults.standard.string(forKey: Self.clientIdDefaultsKey) ?? ""
        let bundled = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
        self.clientId = saved.isEmpty ? bundled : saved
        self.isConnected = Keychain.read(Self.refreshTokenKeychainKey) != nil
        super.init()
    }

    // MARK: - 登入 / 登出

    public func connect() async throws {
        let clientId = self.clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientId.isEmpty else { throw SpotifyAuthError.missingClientId }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectUri),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state)
        ]

        let callbackUrl = try await presentAuthSession(url: components.url!)
        let items = URLComponents(url: callbackUrl, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw SpotifyAuthError.tokenRequestFailed(error)
        }
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw SpotifyAuthError.tokenRequestFailed("回傳資料不正確")
        }

        try await requestToken(params: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectUri,
            "client_id": clientId,
            "code_verifier": verifier
        ])
        isConnected = true
    }

    public func disconnect() {
        Keychain.delete(Self.refreshTokenKeychainKey)
        accessToken = nil
        accessTokenExpiry = .distantPast
        isConnected = false
    }

    // MARK: - Access Token

    /// 取得可用的 Access Token；過期前 60 秒自動以 Refresh Token 換新
    public func validAccessToken() async throws -> String {
        if let token = accessToken, Date() < accessTokenExpiry.addingTimeInterval(-60) {
            return token
        }
        if let task = refreshTask { return try await task.value }

        guard let refreshToken = Keychain.read(Self.refreshTokenKeychainKey) else {
            throw SpotifyAuthError.notConnected
        }
        let task = Task { () throws -> String in
            try await self.requestToken(params: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": self.clientId.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch SpotifyAuthError.tokenRequestFailed(let msg) where msg.contains("invalid_grant") {
            // Refresh Token 被撤銷 (使用者在 Spotify 移除授權)，需要重新登入
            disconnect()
            throw SpotifyAuthError.notConnected
        }
    }

    /// API 回 401 時呼叫，下一次會強制換新 Token
    public func invalidateAccessToken() {
        accessToken = nil
        accessTokenExpiry = .distantPast
    }

    @discardableResult
    private func requestToken(params: [String: String]) async throws -> String {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw SpotifyAuthError.tokenRequestFailed(body)
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int
            let refresh_token: String?
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(token.expires_in))
        // Spotify 換新時可能會輪替 Refresh Token
        if let refresh = token.refresh_token {
            Keychain.save(refresh, for: Self.refreshTokenKeychainKey)
        }
        return token.access_token
    }

    // MARK: - ASWebAuthenticationSession

    private func presentAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { callbackUrl, error in
                if let callbackUrl = callbackUrl {
                    continuation.resume(returning: callbackUrl)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: SpotifyAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? SpotifyAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }

    // MARK: - PKCE

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64Url(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        base64Url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64Url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }
}

extension SpotifyAuthManager: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Keychain (只存 Refresh Token)

private enum Keychain {
    private static let service = "DynamicLyrics.Spotify"

    static func save(_ value: String, for key: String) {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            // 鎖定畫面開車時背景仍需換 Token
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
