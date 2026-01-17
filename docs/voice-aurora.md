# Spatial Voice notes

This document captures the design goals and the current audio/spatial implementation
for Spatial Voice (FOA) and Aurora Voice (classic) so future changes stay aligned
with the experience.

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

## Visual implementation (Spatial Voice)

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
- A live "Echo Tuning" panel is available in the Spatial Voice UI (slider icon at
  bottom-left). Use it to adjust echo parameters on-device while listening. Settings
  persist across launches.
- The panel includes Master Output (to hard-mute the echo) and a Wet Only toggle
  (to remove dry monitoring from the delay unit).
- "Input Output Ratio" scales the echo output by the input level (0 = constant
  output, 1 = output tracks input volume), helping tune the input/output balance.
- Input Mapping includes a 2D pad (gain vs curve) plus a curve preview so you can
  see how mic level maps into the gate/echo.
- Echo Tail includes a 2D pad (delay vs feedback) for quick decay/spacing tuning.
- "Input Floor" sets the minimum normalized level required before the echo gate
  reacts, so taps and desk noise are ignored.

## Echo audio chain (Spatial Voice / AuroraAudioProcessor)

- Spatial capture runs through `AVCaptureSession` and an `AVCaptureAudioDataOutput`.
- Playback is a separate `AVAudioEngine` chain fed by captured snippets:
  `playerNode -> gateMixer -> delay -> boost -> mainMixer`
- There is no continuous mic monitor path. Instead:
  - Detect a voice onset from band-limited RMS.
  - Capture a short snippet (with pre-roll).
  - Stop feeding mic into the echo chain.
  - Play the snippet once into the delay and let the tail decay.
  - Ignore retriggers until `echoRetriggerInterval` has elapsed.
- `echoHoldDuration` is the capture window for the snippet (not a continuous gate).
- `echoRetriggerInterval` is the lockout window that keeps the speaker bleed from
  re-triggering the echo.
- `echoGateAttack` and `echoGateRelease` are time constants (seconds) used to
  smooth the echo on/off envelope while the tail decays.
- `AVAudioUnitDelay` provides repeat spacing (`echoDelayTime`) and decay (`echoFeedback`).
- `echoBoostDb` keeps the first echo strong.
- Wet mix stays high (85–100) so delayed tails can finish even after the capture
  window closes. When Wet Only is on, Wet Base/Range act as output gain shaping
  rather than wet/dry mix.
- Ducking (`duckingStrength`, `duckingLevelScale`, `duckingResponse`) reduces echo
  when live speech is hot. `duckingDelay` preserves the initial hit before ducking
  engages.

Tuning notes:
- If feedback loops return, reduce `echoFeedback`, increase `echoRetriggerInterval`,
  or raise `echoTriggerRise`.
- If the first echo feels too soft, increase `echoBoostDb` or `echoWetMixBase`.
- If repeats feel too dense, increase `echoDelayTime` and/or lower `echoFeedback`.
- If the echo never gates off, raise `echoInputFloor` or `echoGateThreshold`, or
  set Master Output to 0 to confirm the output is muted.

## Spatial audio capture and direction (Spatial Voice)

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

## Classic mode (Aurora Voice / VoiceAuroraClassicView)

- "Aurora Voice" uses the original voice chat pipeline (`AVAudioEngine` input tap
  + `AVAudioSession` `.voiceChat`) to keep Apple’s echo cancellation and AGC active.
- Waves always emanate from the bottom center, so there is no spatial direction
  logic in this mode.

## Quick troubleshooting checklist

- If all FOA channels are silent, let `AVCaptureSession` configure the audio session
  and avoid `AVAudioSession` mode changes.
- If direction is mirrored, flip the azimuth mapping in `resolveDirectionPoint`.
- If feedback loops are loud, lower `echoFeedback` and/or increase ducking.
