# ReKazumi Agent Guide

## Product identity

- Repository and application name: ReKazumi.
- Android application id: `com.predidit.rekazumi`.
- Primary Android targets are Snapdragon 8 Gen 2 or newer and Quest 3-class devices.
- The connected reference phone is an OPlus 13T (`PKX110`, arm64, Adreno 830).

## Playback requirements

- Keep source timing unchanged. Do not convert 23.976 fps to 24 fps and do not alter playback speed.
- RIFE output is fixed at 3x: generate only `t=1/3` and `t=2/3` from two original frames.
- Never recursively interpolate generated frames.
- Keep temporal interpolation independent from the display refresh rate. A 120 Hz display must not cause 5x interpolation.
- Duplicate frames and scene cuts may bypass inference, but ordinary motion must retain the requested full-quality interpolation.
- Anime4K is spatial processing and RIFE is temporal processing. Do not silently enable mpv temporal interpolation on top of RIFE.

## Quality policy

- Architecture and data movement must be optimized before considering model or resolution reductions.
- Full-resolution RIFE is the default required path.
- Do not enable RIFE UHD/half-resolution mode as a performance shortcut.
- Do not lower interpolation quality, output resolution, color precision, or interpolation coverage without explicit user approval.
- Performance fixes must be measured instead of inferred from CPU frequency alone.

## RIFE architecture

- Prefer one frame-pair call that produces both 3x intermediate frames.
- Reuse source packing, GPU upload, padding, preprocessing, allocators, and command submission where safe.
- Preserve original frames as the only model inputs.
- Avoid unnecessary CPU-to-GPU and GPU-to-CPU round trips.
- Keep timing logs for preparation, command recording, GPU execution, output copy, and total pair latency during optimization.
- A crash, incorrect frame, or synchronization hazard takes priority over throughput work.

## Model distribution

- Bundle the pinned RIFE 4.25-lite model in the APK under `assets/models/rife-v4.25-lite/`.
- Verify `flownet.param` and `flownet.bin` with their pinned SHA-256 values.
- The Android application must not download the RIFE model from GitHub at runtime.
- Native libmpv build artifacts may be pinned by release URL and SHA-256, but application model availability must remain offline.

## Verification

- Run Dart formatting, Flutter tests, static analysis, and the arm64 Android release build.
- Verify the APK contains `libmpv.so`, `libkazumi_rife.so`, and both bundled model files.
- Test on the connected OPlus device with Anime4K disabled first, then test the combined Anime4K + RIFE pipeline.
- Confirm the mpv log reports the paired RIFE path before recording performance numbers.
- Collect Android native crash logs and `ReKazumiRIFE` stage timings for every architecture iteration.
- Compare media position against wall-clock time; UI `speed=1.0` alone is not a throughput measurement.

## Repository hygiene

- Preserve unrelated user changes and generated device artifacts.
- Keep architecture changes, model-distribution changes, and small CI fixes in focused commits.
- Do not publish or install an APK until its native runtime version and hash are known.
