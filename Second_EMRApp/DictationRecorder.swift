import Foundation
import SwiftUI
import Combine

#if os(iOS)
import AVFoundation
import Speech

enum DictationEngine: String, CaseIterable {
    case whisper = "Whisper"
    case apple = "Apple / Claude"
}

@MainActor
final class DictationRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {

    // MARK: - State

    enum State: Equatable {
        case idle
        case recording
        case transcribing
    }

    @Published var state: State = .idle
    @Published var lastError: String?
    @Published var engine: DictationEngine = {
        if let saved = UserDefaults.standard.string(forKey: "DictationEngine"),
           let eng = DictationEngine(rawValue: saved) {
            return eng
        }
        return .whisper
    }()

    private var recorder: AVAudioRecorder?
    private var recordedURL: URL?

    private let transcriber = OpenAIWhisperTranscriber(model: "whisper-1")

    // MARK: - Public API

    func toggleDictation(onResult: @escaping (String) -> Void) {
        lastError = nil

        switch state {
        case .idle:
            Task { await startRecordingWithPermission() }

        case .recording:
            stopAndTranscribe(onResult: onResult)

        case .transcribing:
            break
        }
    }

    func setEngine(_ eng: DictationEngine) {
        engine = eng
        UserDefaults.standard.set(eng.rawValue, forKey: "DictationEngine")
    }

    // MARK: - Permission

    private func startRecordingWithPermission() async {
        let session = AVAudioSession.sharedInstance()

        let granted = await withCheckedContinuation { cont in
            session.requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }

        guard granted else {
            lastError = "Microphone permission denied. Enable it in Settings."
            state = .idle
            return
        }

        // For Apple Speech, also request speech recognition permission
        if engine == .apple {
            let speechGranted = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
            guard speechGranted else {
                lastError = "Speech recognition permission denied. Enable it in Settings."
                state = .idle
                return
            }
        }

        startRecording()
    }

    // MARK: - Recording

    private func startRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker]
            )
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("dictation-\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            recordedURL = url

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            rec.prepareToRecord()
            rec.record()

            recorder = rec
            state = .recording

        } catch {
            lastError = "Mic start failed: \(error.localizedDescription)"
            state = .idle
        }
    }

    // MARK: - Stop + Transcribe

    private func stopAndTranscribe(onResult: @escaping (String) -> Void) {
        recorder?.stop()
        recorder = nil

        guard let url = recordedURL else {
            lastError = "No recording found."
            state = .idle
            return
        }

        state = .transcribing

        Task {
            do {
                let text: String
                switch engine {
                case .whisper:
                    text = try await transcriber.transcribe(fileURL: url)
                case .apple:
                    text = try await appleTranscribe(fileURL: url)
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    lastError = "No speech detected. Try speaking louder or longer."
                } else {
                    onResult(trimmed)
                }
                state = .idle
            } catch {
                lastError = "Transcribe failed: \(error.localizedDescription)"
                state = .idle
            }
        }
    }

    // MARK: - Apple Speech Recognition

    private func appleTranscribe(fileURL: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw NSError(domain: "Speech", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Speech recognizer not available for this language."
            ])
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                if let result = result, result.isFinal {
                    cont.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
#endif
