import AVFoundation
import Combine

@MainActor
final class PreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var track: Track?
    @Published private(set) var playing = false
    @Published var volume: Float = 0.7 { didSet { player?.volume = volume } }
    private var player: AVAudioPlayer?
    func play(_ track: Track, url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        let next = try AVAudioPlayer(contentsOf: url)
        next.delegate = self; next.volume = volume
        guard next.play() else { throw CocoaError(.fileReadCorruptFile) }
        player?.stop(); player = next; self.track = track; playing = true
    }
    func toggle() { guard let player else { return }; if playing { player.pause() } else { player.play() }; playing = player.isPlaying }
    func stop() { player?.stop(); player = nil; track = nil; playing = false }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false }
    }
}
