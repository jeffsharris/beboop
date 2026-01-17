# Aurora Voice notes

This document captures the design goals and the current audio/spatial implementation
for Aurora Voice (FOA) and the legacy Aurora Voice (classic) so future changes stay
aligned with the experience. The legacy view remains in the codebase but is no longer
exposed in the app UI.

## Design goals

- The water background should feel calm and deep, with subtle color shifts tied to pitch
  and overall level.
- Echo waves should look like they emanate from where the voice comes from, not just
  the bottom edge. The wave rings should feel physical, with overlap that makes colors
  blend rather than flatten.
- The initial echo should be loud and immediate (close to the speech level), then
  the repeats should space out and clearly fade rather than devolving into feedback.
- Spatial direction is more important than perfect accuracy. The goal is to convey
  left vs right and top vs bottom in a pleasing, stable way.

## Visual implementation (Aurora Voice)

- `AuroraAudioProcessor.sourcePoint` is used to pick the nearest edge and edge position
  for each wave.
- The wave spawn rate is capped by `waveCooldown`, and a minimum level gate is enforced
  by `waveMinLevel`.
- Wave appearance is driven by:
  - `amplitude` from the mic level (mapped to thickness and alpha)
  - `pitch` for hue drift
  - `phase` for organic wobble
- The wave band is drawn as a noisy ring segment and then composited with multiple
  gradient stops to keep overlaps luminous (screen blend + blur for glow).
- Echo Lab (admin tuning) is available via a three-finger tap on the Aurora Voice
  screen. It exposes two 2D pads (Phrase x Shield, Space x Decay) and a single
  Echo Level slider, plus A/B slots, calibration, and an advanced foldout.

## Echo audio chain (Aurora Voice / AuroraAudioProcessor)

- Spatial capture runs through `AVCaptureSession` and an `AVCaptureAudioDataOutput`.
- Playback is a separate `AVAudioEngine` chain fed by captured snippets:
  `playerNode -> gateMixer -> delay -> boost -> mainMixer`
- There is no continuous mic monitor path. Instead:
  - Detect a voice onset from band-limited RMS.
  - Capture a snippet with pre-roll.
  - End capture when the gate stays under `endThreshold` for
    `echoEndHangover` or when `echoMaxCaptureDuration` is reached.
  - Play the snippet once into the delay and let the tail decay.
  - Ignore retriggers until the lockout windows allow it again.
- `echoHoldDuration` is kept for compatibility and mirrors the max capture duration.
- `echoRetriggerInterval` is the re-trigger lockout for speaker bleed; `echoHardDeafen`
  is a shorter, stricter soft lockout immediately after a trigger.
- `echoGateAttack` and `echoGateRelease` are time constants (seconds) used to
  smooth the echo on/off envelope while the tail decays.
- `AVAudioUnitDelay` provides repeat spacing (`echoDelayTime`) and decay (`echoFeedback`).
- `echoBoostDb` keeps the first echo strong.
- Wet mix stays high so delayed tails can finish even after the capture window
  closes. When Wet Only is on, Wet Base/Range act as output gain shaping rather
  than wet/dry mix.
- Ducking (`duckingStrength`, `duckingLevelScale`, `duckingResponse`) reduces echo
  when live speech is hot. `duckingDelay` preserves the initial hit before ducking
  engages.
- Output mask uses the wet tap (out dB) + learned bleed delta + `echoSnrMarginDB`
  to block self-triggering during tails.
- Freeze event gain snapshots `echoMasterOutput` and `echoOutputRatio` at trigger
  time so mid-tail slider moves do not swell the active echo.

Tuning notes:
- If feedback loops return, reduce `echoFeedback`, increase `echoRetriggerInterval`,
  or raise `echoTriggerRise`.
- If the first echo feels too soft, increase `echoBoostDb` or `echoWetMixBase`.
- If repeats feel too dense, increase `echoDelayTime` and/or lower `echoFeedback`.
- If the echo never gates off, raise `echoInputFloor` or `echoGateThreshold`, or
  set Master Output to 0 to confirm the output is muted.

## Echo Lab controls (macro mapping)

- Phrase x Shield:
  - Phrase sets pre-roll, max capture duration, and end-of-speech hangover.
  - Shield raises retrigger intervals, hard deafen time, SNR margin, and gate
    thresholds to avoid speaker bleed.
- Space x Decay:
  - Space maps to `echoDelayTime`.
  - Decay maps to a target tail duration, converting to feedback percent so longer
    spacing keeps a consistent tail length.
- Echo Level:
  - Sets `echoMasterOutput`, Wet Base/Range, and Output Ratio for perceived loudness.
- A/B slots let you store two macro positions and flip instantly.
- Calibration:
  - Silence calibrates input floor + gate threshold using a short noise sample.
  - Bleed calibration measures out dB vs mic dB during a tail to auto-tune
    `echoSnrMarginDB`.

## Spatial audio capture and direction (Aurora Voice)

- FOA capture is iOS 26+ only.
- The capture pipeline must use:
  - `AVCaptureDeviceInput.multichannelAudioMode = .firstOrderAmbisonics`
  - `AVCaptureAudioDataOutput.spatialAudioChannelLayoutTag =
     (kAudioChannelLayoutTag_HOA_ACN_SN3D | 4)`
- The session should be allowed to configure the app audio session:
  `automaticallyConfiguresApplicationAudioSession = true`.
  In earlier attempts, forcing our own session config caused FOA channels to be silent.
- The FOA channel order in ACN/SN3D is W, Y, Z, X. Direction is estimated via the
  intensity vector from cross terms with W:
  - XW, YW, ZW -> azimuth/elevation
- Left/right is intentionally flipped in `resolveDirectionPoint` so the on-screen
  origin matches the device orientation during typical use.
- Direction is smoothed (`sourceSmoothing`) and gated by a confidence threshold to
  avoid jitter when the signal is weak.

## API learnings and gotchas

- `AVAudioEngine` input taps do not provide FOA. Use `AVCaptureSession` for spatial
  capture buffers.
- FOA buffers may be float or integer PCM, interleaved or non-interleaved. The capture
  handler must handle all of those cases.
- FOA only applies to the built-in mic. External mics will ignore
  `multichannelAudioMode`.
- After the capture session starts, apply only minimal playback overrides (speaker
  output, preferred input channel count). Avoid forcing voice processing or custom
  audio session modes that can collapse FOA.
- The gate level uses a simple high-pass filter (~180 Hz) before RMS, which makes
  desk taps less likely to trigger the echo.
- Stable capture in speaker mode benefits from a layered defense:
  - Soft lockout immediately after trigger (`echoHardDeafen`).
  - Output mask (out dB + learned bleed delta + `echoSnrMarginDB`).
  - Frozen event gain so slider changes do not swell active tails.

## Legacy mode (VoiceAuroraClassicView)

- The legacy mode uses the original voice chat pipeline (`AVAudioEngine` input tap
  + `AVAudioSession` `.voiceChat`) to keep Apple’s echo cancellation and AGC active.
- Waves always emanate from the bottom center, so there is no spatial direction
  logic in this mode.
- This view is retained in the codebase but hidden from the app UI.

## Quick troubleshooting checklist

- If all FOA channels are silent, let `AVCaptureSession` configure the audio session
  and avoid `AVAudioSession` mode changes.
- If direction is mirrored, flip the azimuth mapping in `resolveDirectionPoint`.
- If feedback loops are loud, lower `echoFeedback` and/or increase ducking.
