# ReKazumi Agent Guide

## Mandatory engineering journal

- User directive (2026-08-13, permanent): record every material operation,
  mistake, failed attempt, experiment, observed result, and resulting decision
  in this file. This directive itself must remain in `AGENT.md` and must not be
  removed or weakened.
- Before a risky device, playback, native-runtime, timing, or GPU change,
  append the intended operation and safety boundary to the journal below.
  After the operation, append the actual result, including failures. Never
  rewrite a failed experiment as if it succeeded.
- For routine read-only inspection, related commands may be grouped into one
  journal entry, but their conclusions and any change of direction must still
  be recorded. Build, install, launch, playback, adb, GPU API, model, quality,
  package, Git, and release operations are always material.
- Preserve prior entries. Correct an inaccurate entry by adding a dated
  correction instead of deleting the historical record.

## Engineering journal

### Baseline and retired RIFE path

- Forked the upstream project as ReKazumi and checked it out at
  `C:\ReKazumi`. Changed the Android application id to
  `com.predidit.rekazumi` and the application name to `ReKazumi`.
- Initial RIFE/ncnn playback integration performed inference outside mpv's
  GPU presentation architecture. It also treated model retrieval as a runtime
  concern. Device measurement at 1080p was about 724 ms per frame pair, so
  playback slowed dramatically. Conclusion: retire this path; a model download
  is not a playback architecture and must not be reintroduced silently.
- CPU frequency around 384 MHz was initially suspected from telemetry. This
  was a diagnostic mistake: the measured pipeline latency and data movement,
  not the reported CPU frequency, explained the slow playback. Architecture
  must be measured before reducing quality.

### Source-timed mpv presentation work

- Moved fixed 3x phase scheduling into mpv's VO and kept audio/source PTS as
  the master clock. Disabled display-sync catch-up because a rendering stall
  made the media timeline visibly accelerate afterward.
- Added live counters. One device run reported about `71.9 fps` with phases
  `24/24/24`, 48 generated presentations, and 24 generated pairs per second.
  This proved the 3x scheduler was active; it did not prove generated image
  quality or display-stack safety.
- A negative `GL_QCOM_frame_extrapolation` experiment used the previous and
  current originals with scale factors `-2/3` and `-1/3`. It did not hang the
  display stack and achieved the expected counters, but the image oscillated
  violently. Later architecture review found the main timing mistake: those
  previous-to-current intermediates were presented after the current frame,
  so the displayed sequence moved backward in time twice per source frame.

### Unsafe QCOM frame-extrapolation experiments

- Tested positive `glExtrapolateTex2DQCOM` with full-resolution FP16 sources,
  two generated phases, and blocking `glFinish()` synchronization. Result:
  repeatable phone/display freeze, audio continued, then SystemUI/display
  recovery or lock-screen transition. Do not retry.
- Removed batching and blocking finishes, submitting only one positive job per
  presentation frame. FP16 still caused the same SurfaceFlinger/SystemUI hang.
  Conclusion: neither batching nor `glFinish()` was the sole cause.
- Converted only the extension boundary to dedicated full-resolution RGB8,
  matching Qualcomm's public sample texture format, while keeping the main
  surfaces FP16. The installed artifact was
  `device-build/afme-rgb8-136cf8a/ReKazumi-afme-rgb8-136cf8a-local.apk`
  (APK SHA-256
  `f9cf1df6b13808622b36d4d21158c774714720dd8e46d630518596fd8d45b377`).
  Result: the phone froze again during playback.
- Crash-window inspection showed no ReKazumi Java/native tombstone. Instead,
  SystemUI died, the system emitted two `SF Hang` multimedia reports, and
  SystemUI restarted more than once while ReKazumi/audio remained alive.
  Conclusion: process survival is not safety; every tested positive
  frame-extrapolation route wedges the display stack on this Adreno 830 driver.
  ReKazumi was force-stopped and no equivalent build may be installed again.

### Motion-estimation replacement (current)

- Read the Khronos specifications for `GL_QCOM_frame_extrapolation` and
  `GL_QCOM_motion_estimation`. The former produces a full extrapolated frame;
  the latter accepts block-aligned R8 luma inputs and writes ordinary RGBA16F
  motion vectors for application shaders.
- Read the connected OPlus 13T SurfaceFlinger GLES capability report. It
  advertises both extensions on Adreno 830. This was read-only; the unsafe app
  remained stopped.
- Replaced the unbuilt working implementation with current-to-next original
  pairing, bidirectional hardware motion estimation, full-resolution GLES
  inverse warping, and forward/backward consistency weights. This removes all
  runtime calls to `glExtrapolateTex2DQCOM`; build and device validation are
  still pending and must be recorded separately.
- Planned next operation: run patch-application and native compile validation
  in GitHub Actions before producing an APK. Do not install anything if the
  native compile, symbol inspection, runtime hash pin, or APK packaging check
  fails. A successful build will still not authorize automatic playback;
  installation and launch must be recorded, then wait for the user to start
  video manually while system and mpv logs are collected.
- Staged only `AGENT.md`, the native README, and the mpv patch; explicitly left
  the user's `pubspec.lock`, `device-build/`, and `work/` changes out. Created
  commit `ed04d8c` (`fix: replace unsafe Adreno frame extrapolation`) and pushed
  branch `feat/anime4k-rife-3x` through the configured `mixed:10808` proxy.
  Next operation is read-only monitoring of the triggered native workflow; no
  APK installation is allowed until its compile result is recorded here.
- GitHub Actions run `31685851809` completed successfully in 11m17s: patch
  application and arm64 libmpv compilation passed and the artifact-upload step
  passed. The release-publication step was skipped, so the existing release
  asset was not overwritten. The only annotations were action-runtime
  deprecation warnings, not compiler warnings. Planned next operation: download
  this run's artifact into a new commit-specific `device-build` directory,
  calculate its SHA-256, and inspect the packaged `libmpv.so` for the new motion
  symbol and absence of the unsafe extrapolation symbol before pinning it.
- First artifact download attempt through `mixed:10808` timed out after about
  124 seconds. Inspection showed `device-build/ame-ed04d8c` was empty, so no
  partial file was accepted or used. This is a transfer failure, not a native
  build failure. Planned retry: use the same GitHub run and artifact with a
  longer timeout; keep the same empty destination and verify the archive/JAR
  before any subsequent operation.
- Second download command also reached its timeout, after about 364 seconds,
  but left a 9,115,591-byte `rekazumi-afme-arm64-v8a.jar` in the destination.
  Because the command did not report success, treat this file as untrusted
  until JAR structure, CRC/extraction, SHA-256, and contained `libmpv.so`
  strings/symbols pass. Do not pin, package, or install it merely because a
  file exists.
- The downloaded JAR passed validation despite the CLI timeout: `jar tf` and
  full extraction succeeded; it contains arm64 `libmpv.so` (21,735,648 bytes)
  and `libmediakitandroidhelper.so` (386,584 bytes). JAR SHA-256 is
  `5aa8e5bda748f93f6531900d4c27bb75b15379f3a8148b6b149f9c3e4e3660d7`.
  Binary string inspection found `GL_QCOM_motion_estimation`,
  `glTexEstimateMotionQCOM`, and the new `Adreno AFME/AME` logs; it found
  neither `GL_QCOM_frame_extrapolation` nor `glExtrapolateTex2DQCOM`.
  Conclusion: this is the correct safe candidate native artifact. Planned next
  operation is to inspect the project's runtime pin mechanism and bind this
  exact local JAR/hash without publishing over the old release asset.
- Runtime-pin inspection found the arm64 dependency still pointed at the old
  RGB8 release JAR with SHA-256 `404c76fd...107c66`, which is the build that
  reproduced the latest SurfaceFlinger hang. Updated the expected arm64 hash
  to the verified motion-estimation JAR SHA-256
  `5aa8e5bda748f93f6531900d4c27bb75b15379f3a8148b6b149f9c3e4e3660d7`
  and updated the local plugin description. Planned external write: replace
  only the single `afme-runtime-v1/rekazumi-afme-arm64-v8a.jar` release asset
  with this byte-for-byte verified local JAR through `mixed:10808`; then
  download/hash the remote asset independently before committing the pin.
- `gh release upload --clobber` completed successfully for exactly
  `afme-runtime-v1/rekazumi-afme-arm64-v8a.jar`; no other release asset or tag
  was changed. Planned verification: download that named asset into a separate
  `device-build/ame-ed04d8c-remote-check` directory and require its SHA-256 to
  match `5aa8e5bd...e3660d7` before the runtime-pin commit or APK build.
- The named remote asset downloaded successfully to the independent check
  directory. The first local comparison command contained an invalid
  PowerShell generic-method expression for `SequenceEqual[byte]` and stopped
  with a parser error before performing comparison. This was a diagnostic
  command mistake and changed no file. Retry uses independently computed file
  sizes and SHA-256 values; matching cryptographic hashes are sufficient and
  avoid loading both 9 MB files into PowerShell arrays.
- Local and independently re-downloaded remote JARs are both 9,115,591 bytes
  and both hash to
  `5aa8e5bda748f93f6531900d4c27bb75b15379f3a8148b6b149f9c3e4e3660d7`.
  The release replacement is therefore verified byte-for-byte by SHA-256.
  Planned next operation: stage only this journal, the arm64 runtime hash, and
  its README; commit and push the pin. Then perform an Android package build
  through the proxy, without installing it, and verify the APK's embedded
  `libmpv.so` before any device action.
- Staged only the journal, local Android runtime README, and Gradle hash pin;
  commit `f1c75a3` (`build: pin motion-estimation libmpv runtime`) was created
  and pushed through `mixed:10808`. Unrelated `pubspec.lock`, `device-build/`,
  and `work/` remained excluded. Planned build: use the existing Flutter
  release path for arm64, with proxy variables set for dependency retrieval;
  do not install automatically. If compilation succeeds, copy the APK to a new
  commit-specific directory and inspect its package id, native library, unsafe
  symbol absence, and SHA-256.
- The combined Flutter-version/output/status preflight command timed out after
  about 30 seconds without returning output. It did not start the requested APK
  build and must not be counted as a build result. Planned recovery: confirm no
  stale Flutter/Gradle process and no unexpected source change with separate
  lightweight checks, then run the arm64 release build with `--no-pub` and a
  realistic long timeout.
- No stale Flutter process or unexpected source edit was found; the only Java
  process predated this operation. `flutter build apk --release
  --target-platform android-arm64 --no-pub` then succeeded in 92.1 seconds and
  produced a 47.2 MB `build/app/outputs/flutter-apk/app-release.apk`. Gradle
  warned that the app uses NDK 27.2 while the `jni` plugin requests NDK 28.2
  (and several plugins request NDK 27.0); it still completed successfully.
  Treat this as technical debt, not as a failed build, and do not change NDK
  versions during this frame-generation validation. Planned next operation:
  copy the APK to a new `device-build/ame-f1c75a3` directory, compute SHA-256,
  inspect package/application identity and embedded arm64 `libmpv.so`, and
  prove the unsafe extension strings are absent. Do not install yet.
- Copied the APK to
  `device-build/ame-f1c75a3/ReKazumi-ame-f1c75a3-local.apk`; it is 49,488,582
  bytes with SHA-256
  `3da4d0332d8e8f7423fd7075c01d85819d2d4d649abcdff602ee4325b089e06e`.
  The combined check command then returned nonzero because neither `aapt` nor
  `apkanalyzer` was on the current PATH. Copying and hashing had already
  succeeded; package inspection did not run. Planned recovery: locate the
  configured Android SDK build-tools explicitly, then inspect this same APK;
  do not rebuild or install because of a PATH-only diagnostic failure.
- The first SDK-tool lookup incorrectly inferred the SDK root from standalone
  `C:\platform-tools\adb.exe`, then timed out after 30 seconds without finding
  build tools. This was another read-only diagnostic mistake. Do not recursively
  scan from `C:\`; check only standard Android SDK locations and Flutter's
  configured SDK metadata.
- Standard SDK inspection found Android SDK build-tools 37.0.0 and the latest
  command-line tools. `aapt` and `apkanalyzer` verified the candidate APK has
  package id `com.predidit.rekazumi`, application label `ReKazumi`, version
  2.2.7 (code 20207), and an arm64 native ABI. Its embedded arm64 `libmpv.so`
  is 21,735,648 bytes and hashes to
  `733fd76df03a7d1ff47b46d5f6f9719985227c0e24699907d71ce43ccceca0ec`,
  exactly matching the verified native JAR's `libmpv.so`. Binary inspection
  again found only `GL_QCOM_motion_estimation` / `glTexEstimateMotionQCOM` and
  no QCOM frame-extrapolation string. Planned next operation: inspect the APK
  entry list for retired RIFE/model payloads and run focused repository
  validation before deciding whether this APK is eligible for installation.
- The first APK payload search was too broad: generic `.bin` and `model`
  patterns matched Flutter's `AssetManifest.bin`, Kotlin metadata, and Apache
  Tika's unrelated `tika-example.nnmodel`. These are not RIFE artifacts, so the
  broad result is not a failure. The same command mistakenly passed
  PowerShell's `-ErrorAction` to `rg`, which rejected it as an encoding flag.
  Planned correction: match only exact retired RIFE/ncnn library, directory,
  and model-name patterns, and run repository test discovery as a separate
  valid command.
- The corrected exact-name scan found no retired RIFE/ncnn libraries,
  directories, or named model files in the APK. Test discovery found the
  focused `test/frame_interpolation_mode_test.dart` and the Android validation
  workflow. `rg` returned nonzero only because the repository has no
  `integration_test` directory; this is not a test failure. Planned next
  operation: run the focused Flutter test and static analysis of the changed
  Dart/Gradle integration surface without modifying dependencies.
- `flutter test --no-pub test/frame_interpolation_mode_test.dart` completed in
  13.7 seconds with both tests passing: fixed 3x remains opt-in, and unknown
  persisted values safely disable interpolation. Planned next operation: run
  Flutter static analysis; record pre-existing warnings separately from any new
  error, and do not install if analysis reports an error in the frame-generation
  path.
- `flutter analyze --no-pub` completed in 88.6 seconds with exit code 1 because
  it reported 18 `info`-severity issues: existing private-type API notices,
  missing type inference, production `print` calls, and deprecated Flutter
  theme properties. It reported no error or warning and nothing in the
  frame-generation path. Conclusion: analysis is not clean, but it found no
  blocker for this candidate. Do not misreport this as zero issues. Planned
  next operation: commit/push the accumulated journal only, then install the
  already-verified APK with adb replacement semantics. Do not auto-launch or
  auto-play; confirm installation identity and wait for manual user playback
  while collecting logs.

### GitHub reference review

- Searched GitHub for existing Android and mpv frame-generation projects.
  `FrankBarretta/LSFG-Android` is a working Android port verified by its authors
  on Adreno 7xx-class devices and newer. Useful architecture lessons are:
  Android `AHardwareBuffer` GPU sharing, explicit image synchronization,
  duplicate-frame dropping before frame generation, GPU blitting instead of
  CPU copies, bounded queues, vsync pacing with slack, and visible real/total
  FPS diagnostics.
- LSFG-Android captures other apps with MediaProjection and overlays a Vulkan
  swapchain, which would add unnecessary capture latency inside ReKazumi. Its
  LSFG shaders come from a user-supplied purchased `Lossless.dll`, and the app
  repository has a restrictive custom license. Do not copy or redistribute
  those shaders/code; borrow only general architecture ideas permitted by the
  license.
- Inspected LSFG-Android commit `b84754199823615d32d65fe33ea59481dca88dcf`
  read-only. Its render loop specifically warns that posting twice into one
  vsync slot can stall SurfaceFlinger, bounds its pending-frame queue and drops
  stale work, keeps per-swapchain-image synchronization objects, avoids
  reconfiguring `ANativeWindow` geometry every frame, and automatically
  bypasses generation after a Vulkan device-lost result. Applied conclusion to
  ReKazumi: generate only into offscreen textures, make exactly one final mpv
  screen post per presentation, retain textures until consumption, drop late
  phases instead of bursting, and fail closed to the original frame on any GL
  error. AHardwareBuffer import is unnecessary inside ReKazumi because decode,
  Anime4K, motion analysis, synthesis, and presentation already share mpv's
  GLES context.
- `HopperLogger/mpv-frame-interpolator` confirms the relevant algorithm shape:
  calculate motion between an exact source pair, warp both directions, blend
  them, and keep optical-flow analysis resolution independent from output
  resolution. It is desktop OpenCL, not directly reusable on Android.
- `nihui/rife-ncnn-vulkan` is a proven interpolation engine but remains model
  inference; the previously measured Android runtime is unsuitable here.
  Tencent ncnn's newer Android-HardwareBuffer import path is useful evidence
  for zero-copy Vulkan integration but does not remove RIFE inference cost.

## Product identity

- Repository and application name: ReKazumi.
- Android application id: `com.predidit.rekazumi`.
- Primary Android targets are Snapdragon 8 Gen 2 or newer and Quest 3-class devices.
- The connected reference phone is an OPlus 13T (`PKX110`, arm64, Adreno 830).

## Playback requirements

- Keep source timing unchanged. Do not convert 23.976 fps to 24 fps and do not alter playback speed.
- Frame generation is fixed at 3x: generate only `t=1/3` and `t=2/3` from two original frames.
- Use Qualcomm's hardware motion estimator (`GL_QCOM_motion_estimation`) in the mpv OpenGL ES presentation path on supported devices, then synthesize intermediate frames in an ordinary GLES shader.
- Never recursively use generated frames as temporal inputs.
- Keep temporal interpolation independent from the display refresh rate. A 120 Hz display must not cause 5x interpolation.
- Duplicate frames and scene cuts may bypass inference, but ordinary motion must retain the requested full-quality interpolation.
- Anime4K is spatial processing and AFME is temporal processing. Do not run mpv's pixel-blending temporal scaler on top of AFME.

## Quality policy

- Architecture and data movement must be optimized before considering resolution reductions.
- Motion estimation and synthesis consume and produce GPU-resident OpenGL textures; do not add CPU readback or ncnn inference to the active path.
- Do not lower interpolation quality, output resolution, color precision, or interpolation coverage without explicit user approval.
- Performance fixes must be measured instead of inferred from CPU frequency alone.

## Frame-generation architecture

- Use the current and next original mpv GPU render surfaces as temporal inputs. Generate `t=1/3` and `t=2/3` between that exact pair; do not place previous-to-current intermediates after the current frame.
- Keep mpv, Anime4K, and synthesized presentation surfaces in their original full-resolution FP16 path. Create block-aligned R8 luma copies only for motion analysis, because `GL_QCOM_motion_estimation` requires R8 inputs, and keep its RGBA16F motion fields on the GPU.
- Compute forward and backward motion fields and use ordinary GLES inverse warping plus forward/backward consistency weights for occlusion handling.
- Never call positive `glExtrapolateTex2DQCOM` on the OPlus 13T/Adreno 830. FP16 and RGB8 outputs, batched and one-per-presentation submissions, and blocking and nonblocking variants all caused repeatable SurfaceFlinger hangs and SystemUI restarts. The process remaining alive does not make this path safe.
- The retired negative `glExtrapolateTex2DQCOM` experiment did not hang the display stack, but generated previous-to-current intermediates that were presented after current, producing severe temporal oscillation. Do not restore it as a release path.
- Cache the two generated textures while the 120 Hz presentation loop holds or repeats them.
- Preserve original frames as the only temporal inputs.
- Keep `video-sync=audio` and `display-fps-override=0`. Display-sync was rejected by device testing because a render stall makes mpv catch up and visibly accelerates the media timeline.
- Drive the fixed original/1/3/2/3 phases inside the VO from each source frame's realtime PTS and duration. Generated phases that miss their deadline must be dropped rather than submitted in a catch-up burst.
- Request at least one future original frame from mpv without enabling its temporal interpolation. The renderer uses only that original pair as AFME inputs.
- Treat motion estimation as asynchronous on Adreno. Preserve the R8 inputs and RGBA16F motion fields until ordered GLES sampling is complete; rely on GLES command ordering rather than `glFinish()`.
- Force the AFME backend to `vo=gpu`, `gpu-api=opengl`, and `gpu-context=android`; `gpu-next` is Vulkan and cannot call the GLES extension.
- If the motion-estimation extension or compatible texture formats are unavailable, hold original frames and report that hardware frame generation is unavailable. Never silently fall back to the retired RIFE filter or the unsafe frame-extrapolation extension.
- A crash, incorrect frame, or synchronization hazard takes priority over throughput work.

## Model policy

- The active frame-generation backend has no model files and no runtime downloads.
- RIFE/ncnn is retired from the playback path because measured 1080p inference took about 724 ms per pair on the reference phone.
- Native libmpv build artifacts may be pinned by release URL and SHA-256.

## Verification

- Run Dart formatting, Flutter tests, static analysis, and the arm64 Android release build.
- Verify the APK contains the AFME-patched `libmpv.so` and does not contain RIFE model files.
- Test on the connected OPlus device with Anime4K disabled first, then test the combined Anime4K + AFME pipeline.
- Confirm the mpv log reports both `Adreno AFME/AME motion-estimation extension detected` and `fixed 3x motion-compensated frame generation is active`.
- Collect Android native crash logs and mpv render timing for every architecture iteration.
- A process that remains alive is not proof of safety: also inspect SurfaceFlinger hang reports and SystemUI restarts after AFME tests.
- Compare media position against wall-clock time; UI `speed=1.0` alone is not a throughput measurement.

## Repository hygiene

- Preserve unrelated user changes and generated device artifacts.
- Keep architecture changes, model-distribution changes, and small CI fixes in focused commits.
- Do not publish or install an APK until its native runtime version and hash are known.
