import Foundation
import AVFoundation

final class SoundEngine {
    var isEnabled = true

    private let engine = AVAudioEngine()
    private var clickPlayers: [AVAudioPlayerNode] = []
    private var motorPlayer = AVAudioPlayerNode()
    private var bellPlayer = AVAudioPlayerNode()
    private var clickBuffer: AVAudioPCMBuffer?
    private var motorBuffer: AVAudioPCMBuffer?
    private var bellBuffer: AVAudioPCMBuffer?
    private var clickIndex = 0
    private var motorRunning = false
    private var started = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)

    init() {
        guard let format else { return }
        for _ in 0..<5 {
            let player = AVAudioPlayerNode()
            clickPlayers.append(player)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        engine.attach(motorPlayer)
        engine.connect(motorPlayer, to: engine.mainMixerNode, format: format)
        engine.attach(bellPlayer)
        engine.connect(bellPlayer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.55
        clickBuffer = makeClickBuffer(format: format)
        motorBuffer = makeMotorBuffer(format: format)
        bellBuffer = makeBellBuffer(format: format)
        startEngineIfNeeded()
    }

    private func startEngineIfNeeded() {
        guard !started, isEnabled else { return }
        do {
            try engine.start()
            started = true
        } catch {
            started = false
        }
    }

    func keyClick() {
        guard isEnabled else { return }
        startEngineIfNeeded()
        guard started, let clickBuffer, !clickPlayers.isEmpty else { return }
        let player = clickPlayers[clickIndex % clickPlayers.count]
        clickIndex += 1
        player.stop()
        player.scheduleBuffer(clickBuffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }

    func rotorStep() {
        keyClick()
    }

    func startMotor() {
        guard isEnabled, let motorBuffer else { return }
        startEngineIfNeeded()
        guard started, !motorRunning else { return }
        motorRunning = true
        motorPlayer.scheduleBuffer(motorBuffer, at: nil, options: .loops, completionHandler: nil)
        motorPlayer.play()
    }

    func stopMotor() {
        guard motorRunning else { return }
        motorRunning = false
        motorPlayer.stop()
    }

    func stopBell() {
        guard isEnabled, let bellBuffer else { return }
        startEngineIfNeeded()
        guard started else { return }
        bellPlayer.stop()
        bellPlayer.scheduleBuffer(bellBuffer, at: nil, options: .interrupts, completionHandler: nil)
        bellPlayer.play()
    }

    private func makeClickBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = 0.055
        let frames = AVAudioFrameCount(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func random() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) & 0x7FFFFFFF) / Float(0x7FFFFFFF)
        }
        for frame in 0..<Int(frames) {
            let t = Double(frame) / format.sampleRate
            let envelope = exp(-t * 85)
            let noise = Double(random() * 2 - 1) * 0.22
            let metallic = sin(2 * .pi * 1_650 * t) * 0.18 + sin(2 * .pi * 2_430 * t) * 0.08
            channel[frame] = Float((noise + metallic) * envelope)
        }
        return buffer
    }

    private func makeMotorBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = 2.0
        let frames = AVAudioFrameCount(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var seed: UInt64 = 0x243F6A8885A308D3
        func random() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) & 0x7FFFFFFF) / Float(0x7FFFFFFF)
        }
        var filteredNoise: Float = 0
        for frame in 0..<Int(frames) {
            let t = Double(frame) / format.sampleRate
            let hum = sin(2 * .pi * 50 * t) * 0.11 + sin(2 * .pi * 100 * t) * 0.05 + sin(2 * .pi * 150 * t) * 0.022
            filteredNoise = filteredNoise * 0.985 + (random() * 2 - 1) * 0.015
            let whirr = sin(2 * .pi * 430 * t + sin(2 * .pi * 2 * t)) * 0.008
            channel[frame] = Float(hum * 0.45) + filteredNoise * 0.32 + Float(whirr)
        }
        return buffer
    }

    private func makeBellBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = 0.9
        let frames = AVAudioFrameCount(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            let t = Double(frame) / format.sampleRate
            let attack = min(1, t * 80)
            let envelope = attack * exp(-t * 5.2)
            let tone = sin(2 * .pi * 880 * t) * 0.20 + sin(2 * .pi * 1_320 * t) * 0.08 + sin(2 * .pi * 2_640 * t) * 0.025
            channel[frame] = Float(tone * envelope)
        }
        return buffer
    }
}
