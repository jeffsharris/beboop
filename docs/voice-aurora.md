# Voice Aurora notes

This document captures the design goals and the current audio/spatial implementation
for Voice Aurora so future changes stay aligned with the experience.

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

## Visual implementation (VoiceAuroraView)

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
- A live "Echo Tuning" panel is available in the Voice Aurora UI (slider icon at
  bottom-left). Use it to adjust echo parameters on-device while listening.

## Echo audio chain (AuroraAudioProcessor)

- Spatial capture runs through `AVCaptureSession` and an `AVCaptureAudioDataOutput`.
- Playback is a separate `AVAudioEngine` chain fed with the FOA W channel:
  `playerNode -> gateMixer -> delay -> boost -> mainMixer`
- Loud-first, controlled-fade strategy:
- The echo gate only triggers on rising input energy and enforces a retrigger
  cooldown (`echoTriggerRise`, `echoRetriggerInterval`) to prevent feedback
  from re-arming the echo.
- Keep `echoRetriggerInterval` longer than `echoDelayTime` to avoid the speaker
  echo re-triggering itself.
- The gate holds open for `echoHoldDuration` so a full word gets into the delay
  buffer before the gate closes.
- `AVAudioUnitDelay` provides repeat spacing (`echoDelayTime`) and decay (`echoFeedback`).
- `echoBoostDb` keeps the first echo strong.
- Wet mix stays high (85–100) so delayed tails can finish even after the gate closes.
- Ducking (`duckingStrength`, `duckingLevelScale`, `duckingResponse`) reduces echo
  when live speech is hot. `duckingDelay` preserves the initial hit before ducking
  engages.

Tuning notes:
- If feedback loops return, reduce `echoFeedback`, increase `echoRetriggerInterval`,
  or raise `echoTriggerRise`.
- If the first echo feels too soft, increase `echoBoostDb` or `echoWetMixBase`.
- If repeats feel too dense, increase `echoDelayTime` and/or lower `echoFeedback`.

## Spatial audio capture and direction

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

## Quick troubleshooting checklist

- If all FOA channels are silent, let `AVCaptureSession` configure the audio session
  and avoid `AVAudioSession` mode changes.
- If direction is mirrored, flip the azimuth mapping in `resolveDirectionPoint`.
- If feedback loops are loud, lower `echoFeedback` and/or increase ducking.
