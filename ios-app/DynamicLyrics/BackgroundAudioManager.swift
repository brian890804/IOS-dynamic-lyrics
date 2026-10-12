//
//  BackgroundAudioManager.swift
//  DynamicLyrics
//
//  iOS 背景保活 (Keep-Alive) 核心機制：
//  利用 AVAudioSession (Playback category) 播放極短循環的靜音音檔，
//  確保 App 在使用者鎖定螢幕或切換至 CarPlay / 其他 App 時，
//  背景執行緒不會被 iOS 系統凍結（Suspend），能夠持續接收計時器與 Spotify 狀態。
//

import Foundation
import AVFoundation

public class BackgroundAudioManager: NSObject, AVAudioPlayerDelegate {
    public static let shared = BackgroundAudioManager()

    private var audioPlayer: AVAudioPlayer?
    private var isKeepingAlive = false

    private override init() {
        super.init()
    }

    /// 設定音訊模式並開始背景保活
    public func startKeepAlive() {
        guard !isKeepingAlive else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            // 啟用 Playback 模式，並允許與其他音樂播放器 (如 Spotify) 混音 (MixWithOthers)
            // ⚠️ 不可加 .duckOthers：靜音音檔無限循環 → Spotify 音量會在整段期間被持續壓低
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setActive(true)

            // 生成或加載靜音音訊 (WAV 格式無聲資料)
            if let silentData = generateSilentAudioData() {
                audioPlayer = try AVAudioPlayer(data: silentData)
                audioPlayer?.numberOfLoops = -1 // 無限循環
                audioPlayer?.volume = 0.01 // 極低音量，不干擾音樂
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                isKeepingAlive = true
                print("[BackgroundAudio] 背景保活 Session 啟動成功 (MixWithOthers)")
            }
        } catch {
            print("[BackgroundAudio] 啟動失敗: \(error.localizedDescription)")
        }
    }

    public func stopKeepAlive() {
        audioPlayer?.stop()
        audioPlayer = nil
        isKeepingAlive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[BackgroundAudio] 背景保活 Session 已關閉")
    }

    /// 本地動態生成 1 秒 PCM 靜音 WAV 檔，無需額外外部 mp3 資源
    private func generateSilentAudioData() -> Data? {
        let sampleRate: Int32 = 44100
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = sampleRate * Int32(channels * bitsPerSample / 8)
        let blockAlign = channels * bitsPerSample / 8
        let dataSize: Int32 = sampleRate * Int32(blockAlign) // 1 秒長度
        let totalChunkSize = 36 + dataSize

        var data = Data()
        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: totalChunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        data.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
        data.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Array($0) }) // Subchunk1Size
        data.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) })  // AudioFormat (PCM)
        data.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        // 填入 0 (靜音)
        data.append(contentsOf: [UInt8](repeating: 0, count: Int(dataSize)))

        return data
    }
}
