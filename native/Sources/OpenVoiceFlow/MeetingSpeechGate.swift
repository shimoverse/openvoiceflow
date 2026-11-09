import Foundation

/// A conservative, bounded acoustic preflight for *meeting* chunks only. It
/// rejects near-silence and stationary low-level background noise before a
/// decoder can invent words. It does not inspect recognized text: a genuine
/// repeated phrase (including "thank you") remains valid evidence.
///
/// This is deliberately not a general-purpose VAD. Ambiguous/loud audio is
/// decoded rather than discarded; a frame-varying quiet utterance can pass
/// even if its whole-window RMS is tiny. No samples are modified or removed.
enum MeetingSpeechGate {
    static func shouldDecode(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        let frameSize = 320 // 20 ms at the meeting reader's 16 kHz rate
        var levels: [Double] = []
        levels.reserveCapacity((samples.count + frameSize - 1) / frameSize)
        var offset = 0
        while offset < samples.count {
            let end = min(offset + frameSize, samples.count)
            var power = 0.0
            for index in offset..<end {
                let value = Double(samples[index])
                if value.isFinite { power += value * value }
            }
            levels.append(sqrt(power / Double(end - offset)))
            offset = end
        }
        let peak = levels.max() ?? 0
        // Mic dither/quantization and truly empty recordings are not speech.
        guard peak >= 0.0005 else { return false }
        // A final 40–200 ms tail has too few frames to estimate its own
        // background floor reliably. Preserve short speech for the decoder.
        if samples.count <= 3_200 && levels.filter({ $0 >= 0.0007 }).count >= 2 { return true }
        // At this level a stationary room sound is ambiguous. Fail open so
        // sustained/quiet speech without a silence baseline is not erased.
        if peak >= 0.04 { return true }
        // Frame-envelope stationarity is not proof of silence: softly voiced
        // speech can have almost constant RMS. Look for local periodic evidence
        // before the stationary-noise fast path, even in a long noisy import.
        if hasVoicedSubwindow(samples) { return true }
        // A 30-second window can contain a very brief voice that neither the
        // global envelope nor this narrow voiced probe detects. Fail open;
        // never suppress an entire mixed import on a global percentile alone.
        if levels.count >= 500 { return true }
        let ordered = levels.sorted()
        let floor = ordered[ordered.count / 5]
        let threshold = max(0.0007, floor * 1.45)
        // A silent lead-in must not make a long, stationary fan/room-noise
        // plateau look like speech merely because the floor is near zero.
        let activeLevels = levels.filter { $0 >= threshold }.sorted()
        // Only a low-level, flat, *noise-like* signal is skipped. The local
        // sample-correlation probe above admits steady voiced/color-rich audio
        // even when all frame energies are identical; this remains a heuristic.
        if activeLevels.count >= 10 && peak < 0.04 &&
            peak < activeLevels[activeLevels.count / 2] * 1.8 &&
            activeLevels[activeLevels.count * 9 / 10] < activeLevels[activeLevels.count / 10] * 1.45 {
            return false
        }
        var consecutive = 0
        var active = 0
        for level in levels {
            if level >= threshold {
                consecutive += 1
                active += 1
                // 40 ms can carry a short syllable; single-frame clicks cannot.
                if consecutive >= 2 || active >= 3 { return true }
            } else {
                consecutive = 0
            }
        }
        return false
    }

    /// A narrow positive cue, not a speech/noise classifier. Non-periodic
    /// speech is still ambiguous and must not be rejected on this basis.
    private static func hasVoicedSubwindow(_ samples: [Float]) -> Bool {
        let width = 1_600 // 100 ms; hop 50 ms catches a short boundary burst
        guard samples.count >= width else { return false }
        for start in stride(from: 0, through: samples.count - width, by: width / 2) {
            var mean = 0.0
            for index in start..<(start + width) { mean += Double(samples[index]) }
            mean /= Double(width)
            var variance = 0.0
            for index in start..<(start + width) {
                let centered = Double(samples[index]) - mean
                variance += centered * centered
            }
            guard variance / Double(width) > 1e-8 else { continue }
            var adjacent = 0.0
            for index in start..<(start + width - 1) {
                adjacent += (Double(samples[index]) - mean) * (Double(samples[index + 1]) - mean)
            }
            // Quiet colored/voiced audio differs from the nearly uncorrelated
            // stationary-noise fixture; let the decoder resolve ambiguity.
            if adjacent > 0.2 * variance { return true }
            // Human voiced fundamentals roughly 100–260 Hz at 16 kHz. Strong
            // short-time autocorrelation is evidence to decode, not proof of
            // speech; tones and music also pass through to the decoder.
            for lag in stride(from: 60, through: 160, by: 5) {
                var cross = 0.0
                var left = 0.0
                var right = 0.0
                for index in start..<(start + width - lag) {
                    let a = Double(samples[index]) - mean
                    let b = Double(samples[index + lag]) - mean
                    cross += a * b
                    left += a * a
                    right += b * b
                }
                if left > 0 && right > 0 && cross > 0.45 * sqrt(left * right) { return true }
            }
        }
        return false
    }
}
