import Foundation
import AVFoundation
import SwiftUI
import Combine

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

    private var recorder: AVAudioRecorder?
    private var recordedURL: URL?

    private let transcriber = OpenAIWhisperTranscriber(
        model: "gpt-4o-mini-transcribe"
    )

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
                let text = try await transcriber.transcribe(fileURL: url)
                onResult(text.trimmingCharacters(in: .whitespacesAndNewlines))
                state = .idle
            } catch {
                lastError = "Transcribe failed: \(error.localizedDescription)"
                state = .idle
            }
        }
    }
}
