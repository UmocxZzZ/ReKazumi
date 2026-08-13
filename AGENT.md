# ReKazumi Agent Guide

## Product identity

- Repository and application name: ReKazumi.
- Android application id: `com.predidit.rekazumi`.
- Primary Android targets are Snapdragon 8 Gen 2 or newer and Quest 3-class devices.
- The connected reference phone is an OPlus 13T (`PKX110`, arm64, Adreno 830).

## Playback requirements

- Keep source timing unchanged. Do not convert 23.976 fps to 24 fps and do not alter playback speed.
- Frame generation is fixed at 3x: generate only `t=1/3` and `t=2/3` from two original frames.
- Use Qualcomm Adreno Frame Motion Engine (`GL_QCOM_frame_extrapolation`) in the mpv OpenGL ES presentation path on supported devices.
- Never recursively use generated frames as temporal inputs.
- Keep temporal interpolation independent from the display refresh rate. A 120 Hz display must not cause 5x interpolation.
- Duplicate frames and scene cuts may bypass inference, but ordinary motion must retain the requested full-quality interpolation.
- Anime4K is spatial processing and AFME is temporal processing. Do not run mpv's pixel-blending temporal scaler on top of AFME.

## Quality policy

- Architecture and data movement must be optimized before considering resolution reductions.
- AFME consumes and produces GPU-resident OpenGL textures; do not add CPU readback or ncnn inference to the active path.
- Do not lower interpolation quality, output resolution, color precision, or interpolation coverage without explicit user approval.
- Performance fixes must be measured instead of inferred from CPU frequency alone.

## Frame-generation architecture

- Use the two most recent original mpv GPU render surfaces as AFME inputs: previous first, current second.
- Generate both 3x future textures once per original frame pair with scale factors `+1/3` and `+2/3`, following the extension's intended extrapolation path. Device testing showed the negative interpolation path produced severe temporal oscillation on Adreno 830.
- Cache the two generated textures while the 120 Hz presentation loop holds or repeats them.
- Preserve original frames as the only temporal inputs.
- Keep `video-sync=audio` and `display-fps-override=0`. Display-sync was rejected by device testing because a render stall makes mpv catch up and visibly accelerates the media timeline.
- Drive the fixed original/1/3/2/3 phases inside the VO from each source frame's realtime PTS and duration. Generated phases that miss their deadline must be dropped rather than submitted in a catch-up burst.
- Request at least one future original frame from mpv without enabling its temporal interpolation. The renderer uses only that original pair as AFME inputs.
- Treat AFME as potentially asynchronous on Adreno. Complete each extension call before reusing its inputs or issuing the second job; correctness and driver isolation take priority over throughput.
- Force the AFME backend to `vo=gpu`, `gpu-api=opengl`, and `gpu-context=android`; `gpu-next` is Vulkan and cannot call the GLES extension.
- If the extension or compatible texture format is unavailable, hold original frames and report that AFME is unavailable. Never silently fall back to the retired RIFE filter.
- A crash, incorrect frame, or synchronization hazard takes priority over throughput work.

## Model policy

- The active frame-generation backend has no model files and no runtime downloads.
- RIFE/ncnn is retired from the playback path because measured 1080p inference took about 724 ms per pair on the reference phone.
- Native libmpv build artifacts may be pinned by release URL and SHA-256.

## Verification

- Run Dart formatting, Flutter tests, static analysis, and the arm64 Android release build.
- Verify the APK contains the AFME-patched `libmpv.so` and does not contain RIFE model files.
- Test on the connected OPlus device with Anime4K disabled first, then test the combined Anime4K + AFME pipeline.
- Confirm the mpv log reports both `Adreno AFME frame-generation extension detected` and `fixed 3x frame generation is active`.
- Collect Android native crash logs and mpv render timing for every architecture iteration.
- Compare media position against wall-clock time; UI `speed=1.0` alone is not a throughput measurement.

## Repository hygiene

- Preserve unrelated user changes and generated device artifacts.
- Keep architecture changes, model-distribution changes, and small CI fixes in focused commits.
- Do not publish or install an APK until its native runtime version and hash are known.
