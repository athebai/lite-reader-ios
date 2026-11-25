import AVFoundation

final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private var stoppedManually = false

    var onFinish: (() -> Void)?
    var onRange: ((NSRange) -> Void)?

    var isSpeaking: Bool { return synthesizer.isSpeaking }
    var isPaused: Bool { return synthesizer.isPaused }

    override init() {
        super.init()
        synthesizer.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback,
                                                          mode: .spokenAudio,
                                                          options: [.duckOthers])
    }

    func speak(_ text: String, rate: Float, language: String = "zh-CN") {
        stop()
        guard !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.12

        stoppedManually = false
        synthesizer.speak(utterance)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func stop() {
        stoppedManually = true
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        try? AVAudioSession.sharedInstance().setActive(false,
                                                        options: [.notifyOthersOnDeactivation])
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        if stoppedManually { return }
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        onRange?(characterRange)
    }
}
