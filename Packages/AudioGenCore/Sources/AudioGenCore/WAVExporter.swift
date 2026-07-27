import AVFoundation
import Foundation

public enum WAVExportError: Error, LocalizedError, Sendable {
    case cannotCreateFile(URL)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cannotCreateFile(let url):
            return "WAVファイルを作成できません: \(url.path)"
        case .writeFailed(let message):
            return "WAV書き出しに失敗: \(message)"
        }
    }
}

public struct WAVExporter: Sendable {
    public init() {}

    /// Writes a PCM buffer to a 32-bit float WAV (AVAudioFile).
    @discardableResult
    public func export(buffer: AVAudioPCMBuffer, to url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: Int(buffer.format.channelCount),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true,
        ]

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw WAVExportError.cannotCreateFile(url)
        }

        do {
            try file.write(from: buffer)
        } catch {
            throw WAVExportError.writeFailed(error.localizedDescription)
        }

        return url
    }

    public static func documentsDirectory() throws -> URL {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw WAVExportError.writeFailed("Documentsディレクトリを取得できません")
        }
        return url
    }
}
