@preconcurrency import AVFoundation
import HandyKit

@MainActor
final class AppMicrophoneEngine: MicrophoneEngine {
    private let engine = AVAudioEngine()
    private let buffer = CaptureBuffer()
    private var hasTap = false
    var progress: CaptureProgress { buffer.progress }

    func drainVADSamples() -> [Float] { buffer.drainNewSamples() }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let input = engine.inputNode
            let source = input.outputFormat(forBus: 0)
            let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                       channels: 1, interleaved: false)!
            guard let converter = AVAudioConverter(from: source, to: target) else {
                throw CaptureError.unsupportedFormat
            }
            let buffer = self.buffer
            input.installTap(onBus: 0, bufferSize: 4096, format: source) { input, _ in
                let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16_000 / source.sampleRate)) + 32
                guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
                var supplied = false
                var error: NSError?
                converter.convert(to: output, error: &error) { _, status in
                    if supplied { status.pointee = .noDataNow; return nil }
                    supplied = true
                    status.pointee = .haveData
                    return input
                }
                guard error == nil, let samples = output.floatChannelData?[0] else { return }
                buffer.append(Array(UnsafeBufferPointer(start: samples, count: Int(output.frameLength))))
            }
            hasTap = true
            try engine.start()
        } catch {
            _ = stop()
            throw error
        }
    }

    func stop() -> [Float] {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return buffer.take()
    }
    private enum CaptureError: Error { case unsupportedFormat }
}
