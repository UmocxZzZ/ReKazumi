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
- Committed the 81-line accumulated journal as `a8f6c03` (`docs: record
  frame-generation validation journal`) and pushed it through `mixed:10808`;
  unrelated files remained excluded. The exact next device operation is
  `adb install -r` of APK SHA-256 `3da4d033...89e06e` to connected device
  `6cb239de`. Safety boundary: installation only, then verify package metadata;
  do not launch, navigate, or start video automatically.
- `adb -s 6cb239de install -r` of the verified candidate completed successfully
  (`Performing Streamed Install`, `Success`). The app was not launched. Planned
  read-only checks: query installed package version/path and process state to
  confirm identity and prove it is not running; then wait for the user to open
  the app and start playback manually before log capture.
- Installed-package inspection confirmed code path under
  `com.predidit.rekazumi`, primary ABI arm64-v8a, version code 20207, and version
  name 2.2.7. The following `pidof com.predidit.rekazumi` produced no PID and
  therefore made the combined shell command return exit code 1; this is the
  expected proof that ReKazumi was not running, not an installation failure.
  Current state: candidate installed and stopped. Required next event is manual
  user launch and playback; do not question the selected 3x option. Once the
  user reports playback started, collect mpv counters plus SurfaceFlinger,
  SystemUI, GPU, and process-health logs without changing settings mid-test.

### Motion-estimation device failure (2026-08-13)

- User manually launched the installed motion-estimation candidate and started
  playback. Observed result: playback froze, the display then became corrupted
  (花屏), and the app/system presentation crashed. This immediately invalidates
  `GL_QCOM_motion_estimation` as a safe active backend on the reference Adreno
  830 driver; successful compilation and correct extension advertisement did
  not prove runtime safety.
- Emergency operation: ran `adb shell am force-stop
  com.predidit.rekazumi`, then queried `pidof`. No PID was returned; the
  combined command exit code 1 comes from expected `pidof` absence and confirms
  ReKazumi is stopped. Do not restart, reinstall, or retry either QCOM motion
  extension during evidence collection.
- Planned read-only evidence collection: snapshot current clock/uptime, Android
  crash buffers, recent main/system log lines for ReKazumi, Adreno/GPU,
  SurfaceFlinger `SF Hang`, SystemUI restarts, low-memory kills, and display
  corruption; then inspect package/process state. No settings, refresh rate,
  playback option, or app data may be changed.
- First evidence command had two Android-shell compatibility mistakes: the
  device's `date` rejected the supplied format string, and `logcat -T` rejected
  the human phrase `30 minutes ago`. Only `uptime` succeeded, reporting 8 days
  22:16 uptime and high load averages 17.15/15.82/15.34. No valid filtered crash
  window was obtained from that attempt. Retry uses plain `date`, fixed recent
  line counts, and the same read-only filters.
- Compatible retry succeeded at device time 17:55:30. It captured the relevant
  transition near 17:54, including ReKazumi PID 24168 and subsequent display
  transitions into DOZE/OFF around 17:54:35-17:54:37. SystemUI was still PID
  31144 afterward, so this snapshot does not show a SystemUI restart. The
  filtered output was nevertheless dominated by display/WindowManager noise
  and truncated, so it is insufficient to determine the actual crash cause.
  Planned refinement: query exact PID/fatal/GPU/SF-Hang patterns with a narrow
  result limit and read Android `activity exit-info` for the package.

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

### Motion-estimation failure evidence and permanent safety decision (2026-08-13)

- Exact Android `ApplicationExitInfo` shows ReKazumi PID 24168 exited at
  17:54:34.657 with reason `USER REQUESTED`, subreason `FORCE STOP`, and
  description `stop com.predidit.rekazumi due to from pid 11521`. This is the
  diagnostic `adb am force-stop` issued after the user reported the freeze and
  corruption; it is not evidence of an autonomous application crash.
- The matching log window shows the app starting at 17:53:25.317, the diagnostic
  force-stop and SIGKILL at 17:54:34.655, then client-surface teardown. No Java
  fatal exception, native tombstone, OOM kill, SurfaceFlinger restart, or
  SystemUI restart was captured before that forced stop. Exit RSS was about
  506 MB. Absence of a tombstone does not contradict the observed graphics
  failure because a wedged or corrupted GPU/display path can leave the process
  alive until it is externally stopped.
- User-observed outcome remains authoritative for safety: playback froze, the
  image became corrupted, and the app/display became unusable. The active
  `GL_QCOM_motion_estimation` experiment is therefore rejected even though the
  process did not autonomously terminate in Android's exit record.
- Both tested proprietary QCOM GLES routes are now permanently prohibited on
  the OPlus 13T / Adreno 830 reference device:
  `GL_QCOM_frame_extrapolation` caused repeatable display-stack hangs and
  SystemUI restarts; `GL_QCOM_motion_estimation` caused a freeze followed by
  visible frame corruption. Do not retry either extension, do not reinterpret
  the missing tombstone as permission to retry, and do not ship either path.
- This decision supersedes the earlier playback requirement that selected
  `GL_QCOM_motion_estimation` as the implementation. The product requirement
  remains full-quality 3x frame generation, but the implementation must use a
  proven, explicitly synchronized Android/Vulkan frame-generation architecture
  or another safe backend. Until that exists, fail closed to original-frame
  playback and report frame generation unavailable.
- Immediate safety work: keep the installed package stopped; change the native
  runtime so the QCOM entry points cannot be called; build and publish a safe
  replacement for the currently pinned experimental runtime before any further
  device playback test. No reinstall or playback retry is authorized during
  this rollback.
- Safety implementation intent: remove QCOM extension discovery from native
  initialization so its function pointer remains null, gate the VO's 3x phase
  scheduler on an actually available safe backend, and reset any persisted
  Flutter 3x selection to Off before player construction. The settings page
  must refuse re-enabling the rejected backend and explain that it is disabled
  after device instability. This preserves ordinary source-rate playback and
  Anime4K while making the dangerous path unreachable at both UI and native
  layers.
- Patch-integrity correction: the first fail-closed edit added two wrapped
  condition lines in `gl_video_configure_queue` but initially left that unified
  diff hunk's new-line count at 11. Corrected it to 13 before attempting any
  native build. This was a source-patch metadata mistake, not a device action.
- First syntax-only `git apply --numstat` still rejected the patch at the next
  hunk because the initialization hunk count omitted its added blank line. The
  correct new count is 12, not 11. Corrected it and repeated syntax validation;
  no build, publication, installation, or device playback occurred.
- After both metadata corrections, syntax-only parsing succeeded and reported
  the expected four patched mpv files. Planned validation now clones the pinned
  local clean mpv base into `device-build/mpv-failclosed-patch-check` without
  hardlinks and runs `git apply --check` there. This is an isolated, disposable
  local validation copy; it does not change the connected device or the source
  repository's unrelated files.
- The first isolated-clone validation did not start: Git treated the local
  source repository's `.git` directory as a second dubious-ownership path even
  though the worktree path was allowed command-locally. The clone destination
  was not created, so the following apply-check also failed because it had no
  directory. Retry supplies command-local safe-directory entries for both the
  worktree and its `.git`; no global Git configuration is changed.
- The isolated clean-base clone and `git apply --check` succeeded at pinned mpv
  commit `32a164cc017acab50389f2194f720ccfd0b01a28`. Updated native/plugin
  documentation and workflow labels so they no longer claim the rejected QCOM
  backend is active. Artifact filenames and release tag remain stable solely to
  replace the dangerous pinned asset atomically after the safe build completes.
- Planned local verification: apply the patch inside the isolated clean clone,
  confirm QCOM function discovery is absent and the fail-closed queue gate is
  present, then format only the three changed Dart files and run focused Flutter
  analysis/tests. These checks do not access the phone.
- The user interrupted the combined local verification while it was running.
  Follow-up inspection found no remaining Dart, Flutter, or Git process. The
  isolated mpv clone had already accepted the patch, and its source contains
  the fail-closed warning and guarded scheduler; the only
  `glTexEstimateMotionQCOM` text left is an unavailable diagnostic inside an
  unreachable path, not extension discovery. Main-repository `git diff --check`
  passes. Resume formatting and tests as separate bounded commands so their
  completion is unambiguous.
- Standalone `dart format` produced no output for more than 60 seconds and was
  terminated. No source error was reported, and no device action occurred.
  Before retrying, inspect which Dart executable is being resolved and use the
  repository's Flutter SDK toolchain explicitly; do not leave a hung formatter
  running.
- Running the same formatter with permission to use the external Flutter SDK
  completed in 4.3 seconds; all three files were already formatted. The earlier
  hang was therefore a tooling/sandbox execution issue, not malformed Dart.
- Centralized safety availability in `FrameInterpolationMode.available` instead
  of duplicating the rejected-backend identity in settings and player setup.
  Added a focused test proving Off remains available while the stored 3x mode
  is recognized but unavailable. This keeps migration deterministic and makes a
  future backend re-enable an explicit code decision.
- Verification results: formatting completed; focused Flutter tests passed 3/3,
  including persisted-value fallback and rejected-backend availability; focused
  static analysis of the three production files plus the test reported no
  issues. `git diff --check` remains clean.
- Planned publication sequence: commit only the fail-closed source, docs,
  workflow, test, and this journal (exclude the user's unrelated
  `pubspec.lock` and all `device-build/`/`work/` artifacts); push the branch to
  build a safe arm64 JAR; publish it over the experimental release asset; then
  pin its new SHA-256 in a separate commit. Do not install an APK during this
  sequence.
- Created commit `4905eb9` (`fix: disable unstable QCOM frame generation`)
  containing exactly the nine staged safety files. The unrelated modified
  `pubspec.lock` and untracked `device-build/`/`work/` directories were not
  staged or committed. Next operation is a branch push through the configured
  local HTTP proxy at `127.0.0.1:10808`, which will start the native workflow.
- Push succeeded: remote branch advanced from `a8f6c03` to `4905eb9`. The push
  trigger builds an artifact but does not publish the release because workflow
  input `publish_release` is absent on push. Start one explicit workflow run at
  the same commit with `publish_release=true` through the same proxy; monitor
  both runs but use only the publishing run for the replacement asset.
- Explicit publishing workflow dispatch succeeded. Two filtered `gh run list`
  attempts returned an empty result despite exit code 0 because GitHub still
  identifies this workflow by its default-branch display name rather than the
  edited branch name/filter. A general run listing confirmed manual publishing
  run `31689802185`, push native-build run `31689768377`, and validation run
  `31689768352` are all in progress at commit `4905eb9`. Do not cancel the
  duplicate non-publishing build; monitor the manual run as the authoritative
  release replacement.
- Publishing run `31689802185` completed successfully at commit
  `4905eb94c3b713fa9b26a73b8a308e1c882fad2b`: native build, artifact upload,
  and release publication all passed. Release `afme-runtime-v1` now targets that
  commit, is named `ReKazumi safe arm64 runtime v1`, and exposes one asset of
  9,116,111 bytes with GitHub digest
  `3b84002a1ebd49854c3e66e3778ac522ca67ba803062e6271690b2b60c67fa6b`.
  This differs from the rejected asset digest. Planned independent validation:
  download into new directory `device-build/afme-safe-4905eb9`, recompute the
  hash locally, list JAR contents, extract `libmpv.so`, and verify its embedded
  fail-closed diagnostic before pinning the dependency.
- Independent download verification passed. Local JAR SHA-256 exactly matches
  GitHub's digest:
  `3b84002a1ebd49854c3e66e3778ac522ca67ba803062e6271690b2b60c67fa6b`.
  The JAR contains only `libmediakitandroidhelper.so` and arm64 `libmpv.so`;
  the latter hashes to
  `7deb3537ac6de412185a1dc95900a4b2ebf74737937652bde7cd780c4cab095a`.
  Binary inspection finds the fail-closed diagnostic `Adreno AFME/AME disabled
  after device instability` and no former `motion-estimation extension
  detected` string. The remaining `glTexEstimateMotionQCOM is unavailable`
  string belongs to the guarded fallback diagnostic; extension discovery and
  function resolution are absent.
- Updated the arm64 dependency pin from rejected JAR digest
  `5aa8e5b...e3660d7` to safe JAR digest `3b8400...c67fa6b`. Next verify the
  plugin downloader and build an APK without installing it.
- The plugin cache path
  `packages/media_kit_libs_android_video/build/afme-runtime-v1/` is absent, so
  there is no stale JAR to delete or overwrite. Seed that reproducible build
  cache from the independently verified local safe JAR, then run the standard
  arm64 release build with `--no-pub`. This avoids another network transfer and
  still exercises the plugin's SHA-256 verification task.
- Seeded cache JAR hash matched the safe digest, then ran the standard arm64
  release build without installation. Gradle reached Java compilation, proving
  dependency verification accepted the new JAR, but the build failed after
  79.5 seconds because committed/generated
  `GeneratedPluginRegistrant.java` tries to instantiate
  `net.jonhanson.flutter_native_splash.FlutterNativeSplashPlugin`, whose Android
  class is absent from the resolved build. The NDK 27/28 mismatch shown above
  it is a warning, not the failing task. Diagnose generated plugin metadata and
  repair it without modifying or discarding the user's unrelated
  `pubspec.lock` change; no APK was produced or installed.
- Repository inspection shows `.flutter-plugins-dependencies` was generated by
  Flutter 3.44.9 on 2026-08-12 and incorrectly includes the dev dependency
  `flutter_native_splash 2.4.7` as a native Android plugin; the generated
  registrant is ignored/untracked and was recreated during this build. A first
  read-only inspection of that package's external Pub cache was denied by the
  workspace sandbox. Retry read-only with permission to confirm whether its
  current pubspec declares a removed/stale Android plugin class before choosing
  a fix.
- External cache inspection confirms `flutter_native_splash 2.4.7` still
  declares `FlutterNativeSplashPlugin` and its Java source exists. The mismatch
  is build metadata: the stale plugin manifest came from Flutter 3.44.9 while
  the active SDK is Flutter 3.41.4 and the build used `--no-pub`, so registration
  and Gradle inclusion diverged. Before regeneration, `pubspec.lock` has SHA-256
  `bfdba566...35d7853`; Git's index object and working-tree object both equal
  `84fa4dff8d4bad7cc9dbc744a2566d32b4065db8`, and `git diff` is empty. Its
  apparent modified status is stat metadata, not content. Run
  `flutter pub get --offline` to regenerate ignored plugin metadata with the
  active SDK, then verify the lock hash remains identical before rebuilding.
- Offline `flutter pub get` completed successfully using only available package
  caches. `pubspec.lock` SHA-256 remained exactly
  `bfdba566...35d7853`, and `git diff -- pubspec.lock` remains empty, so no user
  dependency content changed. A follow-up `rg` command intended to print the
  generated JSON version used quoting that PowerShell reduced into an invalid
  character class; this metadata display check failed, while the hash checks
  succeeded. Use JSON parsing rather than another regex, then retry the build.
- JSON parsing and `flutter --version` corrected the earlier SDK inference: the
  active SDK is Flutter 3.44.9 even though its containing directory is named
  `3.41.4`; the plugin metadata is current, not stale. The actual mismatch is
  that Flutter generates Java registration for the native
  `flutter_native_splash` dev dependency while Android Gradle excludes that dev
  dependency from compilation. Because project configuration explicitly sets
  `flutter_native_splash.android: false`, no Android runtime registration is
  required. For this local delivery build only, remove that single block from
  the ignored/generated registrant and invoke Gradle directly so Flutter does
  not regenerate it. Do not commit this generated workaround and do not alter
  `pubspec.yaml` or `pubspec.lock`; address the upstream tool/plugin mismatch
  separately from frame-generation source.
- Direct Gradle release build succeeded in 2m11s (852 tasks, 42 executed). The
  safe plugin `downloadDependencies` task ran successfully. Build warnings about
  NDK version recommendations, Kotlin plugin compatibility, legacy JNI
  packaging, and Gradle 9 deprecations were non-fatal. The generated splash
  registration workaround remains ignored/uncommitted.
- Produced APK metadata: application id `com.predidit.rekazumi`, version
  `2.2.7` / code 20207, file size 72,685,292 bytes, SHA-256
  `44c6c0f00dde0d40b3b2e022abf0b8dc7e55f0c5eb329a0549b12e7ed411285c`.
  The universal APK contains arm64, armeabi-v7a, and x86_64 `libmpv.so`; only
  arm64 uses the ReKazumi safe runtime. Planned delivery validation: extract
  the APK's arm64 `libmpv.so`, require its hash to match the independently
  verified safe JAR hash, inspect the application label with Android build
  tools, and only then copy the APK to a versioned `device-build` directory.
- Final local APK validation passed. Delivery file
  `device-build/rekazumi-safe-4905eb9/ReKazumi-safe-4905eb9-universal.apk`
  retains SHA-256
  `44c6c0f00dde0d40b3b2e022abf0b8dc7e55f0c5eb329a0549b12e7ed411285c`.
  Its extracted arm64 `libmpv.so` exactly matches the safe JAR digest
  `7deb3537...ab095a` and contains the fail-closed diagnostic. Android `aapt`
  confirms package `com.predidit.rekazumi`, application label `ReKazumi`,
  version 2.2.7 (20207), and ABIs arm64-v8a/armeabi-v7a/x86_64. The APK was not
  installed.
- GitHub validation run `31689768352` and non-publishing native run
  `31689768377` both succeeded at `4905eb9`. Timing caveat: the validation APK
  finished at 10:17:37Z, before the safe release asset replaced the old JAR at
  10:20:18Z, so that earlier CI APK must not be distributed even though the UI
  safety gate prevents activation. Only the independently checked local APK is
  currently approved. Push the new JAR hash pin and require the next validation
  run to rebuild after the safe asset publication.
- Created commit `841832d` (`build: pin fail-closed libmpv runtime`) with only
  the verified SHA-256 pin and accumulated journal. Generated caches, APKs,
  ignored registrant workaround, and `pubspec.lock` were excluded. Push this
  commit through proxy and treat its new validation APK as authoritative only
  after CI succeeds against the already-published safe asset.
- Push of `841832d` succeeded and started final validation.

### Replacement architecture research (2026-08-13)

- Strict GitHub repository searches for exact phrases `frame generation
  android vulkan`, `frame interpolation android vulkan`, and
  `optical flow android vulkan` returned no repositories. Broader searches
  found `FrankBarretta/LSFG-Android` as the only demonstrated Android/Vulkan
  frame-generation application; `The412Banner/LLS` is a near-identical mirror,
  not an independent implementation. General frame-interpolation results were
  desktop/research projects or ncnn model inference.
- Fixed reference revisions: LSFG-Android
  `da867e918d65289ceb38f75e354b197dc08ffd29`, standalone GPL application
  `b84754199823615d32d65fe33ea59481dca88dcf`, MIT Android lsfg-vk branch
  `3e89e5439a98f55d5acb003d20039426ab24e69c`, and HopperRender
  `0d586cd4a78f2905f65b82fb6ac87e2829477479`.
- LSFG-Android proves AHardwareBuffer sharing, explicit Vulkan ownership,
  bounded queues, vsync pacing, device-lost bypass, and real/total FPS
  instrumentation on Adreno 7xx+. Its capture/overlay path is unnecessary for
  ReKazumi because the player owns the decoded frames and final surface.
- License check used actual LICENSE files, not only repository badges. The
  standalone Android application and ReKazumi are GPL-3.0 compatible; the
  Android AHB branch is MIT. The monorepo app subtree has additional
  non-commercial restrictions and must not be copied. All LSFG variants still
  require shaders extracted from a user-owned `Lossless.dll`; those assets
  cannot be bundled or downloaded by ReKazumi.
- HopperRender provides a model-free hierarchical block-search plus
  bidirectional warp/blend design, but is desktop OpenCL and not an Android
  performance proof. A tree-list `gh api` command for that repository failed
  because its jq expression was parsed incorrectly (`function not defined:
  blob/0`); README and repository metadata reads succeeded, so no conclusion
  depends on the failed tree listing.
- Added `docs/frame-generation-architecture.md`. It chooses the proven
  LSFG-style Android/Vulkan transport, synchronization, pacing, metrics, and
  fail-closed structure while explicitly leaving the algorithm decision gated:
  user-supplied LSFG shaders versus a new fully open Vulkan optical-flow
  implementation. No proprietary shader, model, or external repository code
  was added to ReKazumi.
- Final hash-pin validation run `31691548048` succeeded at commit
  `841832d554ade10aa9a17928e4d05fdf32c1efe9`: formatting, full Flutter tests,
  full analysis, arm64 APK build, native-library package check, and artifact
  upload all passed. Artifact `rekazumi-afme-android-arm64` has id 9177853188
  and size 48,682,947 bytes. Download it into a new directory and independently
  verify its APK/package metadata and embedded arm64 `libmpv.so` hash before
  approving it; the historical artifact name is not evidence that AFME is
  active.
- First `gh run download` attempt for the 48.7 MB final artifact exceeded the
  180-second local command timeout and was terminated without output. Inspect
  the new destination read-only before retrying; do not assume a partial file
  is valid and do not overwrite a complete APK without checking its size/hash.
- The timed-out `gh` process remained alive with negligible CPU and no visible
  destination file. The first non-escalated exact-PID `Stop-Process` reported
  `STOP_FAILED`; by the subsequent approved inspection the process had exited
  and the directory was still empty. No complete or partial APK was accepted.
- Strengthened CI instead of relying on an unreliable artifact download:
  renamed the validation workflow/artifact to `safe` terminology, extracts the
  packaged arm64 `libmpv.so`, requires exact SHA-256
  `7deb3537...ab095a`, requires the fail-closed diagnostic, and rejects the old
  extension-detected diagnostic. This makes CI itself prove the APK embeds the
  independently verified safe binary before uploading it.
- Created commit `ab4eaba` (`docs: define safe Vulkan frame generation path`)
  containing the architecture document, renamed/strengthened validation
  workflow, and journal. Amend this operation record into that same unpushed
  commit, then push once; generated directories and `pubspec.lock` remain
  excluded.
- The amend produced final commit `6f12da5` and push succeeded. Validation run
  `31692783109` completed successfully at
  `6f12da5a3a657727cc6a575b6e715a0e9dc90347`: formatting, full tests, full
  analysis, Android arm64 APK build, strengthened native-library verification,
  and upload all passed. The exact embedded arm64 `libmpv.so` SHA-256 and
  fail-closed marker therefore passed in CI before artifact upload. Final
  artifact is `rekazumi-safe-android-arm64`, id 9178345124, size 48,682,935
  bytes. Historical workflow display text shown by GitHub may remain cached
  from the default branch, but the executed branch step contains the safe
  binary checks.
- Safe rollback outcome is complete. Approved local deliverable remains
  `device-build/rekazumi-safe-4905eb9/ReKazumi-safe-4905eb9-universal.apk`
  (SHA-256 `44c6c0f0...411285c`); approved CI artifact is the hash-checked
  `rekazumi-safe-android-arm64` from run 31692783109. Neither APK was installed
  during rollback. Future work starts from
  `docs/frame-generation-architecture.md`; no QCOM GLES extension may be
  re-enabled.
- The final journal commit had pre-amend id `bbaff73` (`docs: record safe
  runtime verification`). Its operation record was amended into the same
  unpushed commit; use Git history for the resulting id instead of embedding a
  self-changing hash here. AGENT-only changes do not match the Android
  validation workflow paths, so this documentation push must not start another
  APK build.

### Safe backend foundation (2026-08-14)

- User requested continuation. The next implementation is deliberately limited
  to algorithm-independent infrastructure: a backend/session state machine,
  counters, structured diagnostics, and a sticky per-session fault fuse. The
  default backend remains unavailable/no-op, and this work must not install,
  start, or test playback on the phone.
- Planned state contract: `disabled -> probing -> ready -> active`; unavailable
  and faulted states cannot activate; fault remains sticky until explicit
  session reset. Diagnostics include backend/state/reason, source/generated/
  generated-present counts, deadline drops, and duplicate/scene-cut bypasses.
  Integrate the snapshot into the existing log page and keep the rejected mpv
  option behind the availability guard. Add pure Dart transition/counter tests
  before any native Vulkan implementation.
- Implemented the pure Dart session state machine and connected its structured
  `ReKazumi FG:` snapshot to the player log. Persisted unavailable 3x settings
  enter `backend=vulkan state=unavailable`, are reset to Off, and never reach
  mpv activation. The existing off path resets counters; activation exceptions
  set the sticky fault state. Targeted tests passed 7/7 and focused static
  analysis reported no issues.
- A first combined patch for the dedicated status row failed atomically because
  its expected context used the terminal's mojibake rendering instead of the
  UTF-8 Chinese text actually stored in `video_details_sheet.dart`. No file in
  that combined patch changed. Re-read stable icon-based context and retry with
  the real source text.
- Next safe UI step: derive the latest structured frame-generation line from
  the already-observable log list and show it as a dedicated status row. This
  avoids changing MobX generated files while making backend/state/counters
  visible on the status page.
- Added the dedicated status row and latest-line extraction. The expanded
  targeted suite passed 8/8, but the new debug-report test printed a caught
  logger warning because Flutter's ServicesBinding was not initialized before
  the logger attempted file output. This did not fail the test or affect app
  code. Initialize `TestWidgetsFlutterBinding` in the test and rerun so the
  verification output is clean.
- Initializing ServicesBinding removed the first warning but exposed the next
  expected unit-test limitation: no native path-provider plugin exists in this
  pure Dart test, so the logger again printed a caught file-output warning.
  The test should validate the observable log extraction with the snapshot's
  pure log line directly; production `reportFrameGeneration` remains the thin
  append-plus-log wrapper. Remove the unnecessary binding and rerun.
- After removing the logger call from the pure unit test, the first combined
  format/test command produced no output and hit the shell tool's 120-second
  timeout. A subsequent process check found no remaining Dart or Flutter
  process. Treat this as an inconclusive tooling timeout, not a test failure;
  split formatting and testing into separate commands before evaluating code.
- The Flutter SDK batch wrappers also timed out even for `dart --version`, while
  the SDK's embedded `dart.exe --version` returned immediately. Direct format
  then exposed the real sandbox issue: Dart analytics initialization was denied
  access to `C:\Users\Skrindo\AppData\Roaming\.dart-tool`. Run the normal
  project verification with the required host permission instead of changing
  system paths or treating the wrapper timeout as an application defect.
- With the required host permission, formatting reported no changes, the two
  targeted suites passed cleanly (8/8) with no logger/plugin warnings, and
  focused analysis of the session, debug, playback, status-sheet, and test files
  reported no issues. `git diff --check` also passed. `pubspec.lock` still has
  no content diff and remains excluded with the pre-existing generated output.
- Full `flutter test` passed 140/140. Its caught ServicesBinding warnings came
  from the existing malformed-history-log recovery tests, not from the new
  frame-generation tests. Full analysis with warnings fatal completed
  successfully; it reported only the repository's 18 pre-existing info-level
  findings and no warning/error. No APK was built or installed and no device
  command was issued during this foundation verification.
- Created commit `a73f9e2` (`feat: add fail-closed frame generation state`) with
  only the six implementation/test files plus this journal. Amend this operation
  record into the same unpushed commit; continue excluding the unchanged-content
  `pubspec.lock` and generated `device-build/`, `work/`, and package build output.

### Read-only Vulkan capability probe (2026-08-14)

- The foundation commit was amended to final id `2a04421`, pushed through the
  local `mixed:10808` proxy, and GitHub Actions run `31761849365` passed in
  9m19s. Formatting, 140 tests, full analysis, Android arm64 APK build, exact
  safe `libmpv.so` hash/fail-closed marker checks, package id verification, and
  artifact upload all succeeded. The only annotations were GitHub's upstream
  Node 20/setup-java action deprecation notices. No artifact was installed.
- Read-only native-entry inspection found that the app already has a Kotlin
  `MethodChannel` host but no app CMake/native module. One inspection command
  incorrectly requested nonexistent `android/app/build.gradle.kts`; it failed
  only for that read, then the actual Groovy `android/app/build.gradle` was
  opened. No file changed because of the mistake. Two official-document web
  lookups returned no usable content, so no implementation claim relies on
  those empty results.
- Chose a deliberately shallow first probe: Android reports its packaged Vulkan
  feature version and hardware level through `PackageManager`; Java does not
  claim AHardwareBuffer/external-memory/timeline-semaphore support. The response
  hard-codes `nativeBackendLinked=false`, so even Vulkan 1.3 remains unavailable
  until a future NDK extension probe and transport backend actually exist.
- Added the Android method channel, a test-injectable Dart capability service,
  fail-closed malformed/missing-channel handling, and playback initialization
  diagnostics. The result reason includes Android SDK and Vulkan version while
  state remains unavailable. Expanded the validation workflow paths and format
  list to cover all new frame-generation state, capability, log/status, and test
  files. Targeted capability/session/interpolation tests passed 11/11.
- Strengthened the capability contract with a test proving that even a future
  `nativeBackendLinked=true` response remains unavailable until native extension
  validation exists; the final targeted suite passed 12/12. Focused analysis
  reported no issues. Full tests passed 143/143 and full analysis again had only
  the existing 18 info-level findings. The pre-existing history-test logger
  warnings remain unrelated.
- Local Android arm64 release build succeeded and produced
  `build/app/outputs/flutter-apk/app-release.apk` (47.2 MB), SHA-256
  `507ef58e9bc3d235efc4179a056ae1ccd0abbcbfd21e654d3df6d365fde04109`;
  output metadata confirms `com.predidit.rekazumi`. A post-format incremental
  `app:compileReleaseKotlin` also succeeded. Gradle repeated the repository's
  existing warning that pinned NDK 27.2 is below the `jni` plugin's recommended
  NDK 28.2, plus upstream Kotlin/Gradle deprecation notices. Do not change the
  toolchain as part of this isolated probe. The APK was not installed or run.
- Created commit `3640f31` (`feat: probe Android Vulkan capabilities safely`)
  with only the capability channel/service/tests, playback integration, CI
  coverage, and journal. Amend this operation record into the same unpushed
  commit, then push through the approved local proxy and require CI success.

### Headless native Vulkan extension probe (2026-08-14)

- The second-stage commit was amended to final id `37d828e`, pushed through the
  local proxy, and CI run `31763006261` passed in 9m47s. Expanded formatting,
  143 tests at that revision, full analysis, arm64 APK build, safe `libmpv`
  verification, package check, and artifact upload all succeeded. The device was
  not used.
- Confirmed local CMake 3.22.1, NDK 27.2, Vulkan Android external-memory header,
  and timeline semaphore feature definitions before adding native code. The new
  `librekazumi_framegen.so` is a capability probe only: it creates a headless
  Vulkan instance, enumerates physical devices/extensions, queries the timeline
  semaphore feature, destroys the instance, and returns JSON. It never creates a
  logical device, queue, image, AHardwareBuffer, surface, swapchain, or frame.
- Native prerequisites require device Vulkan 1.1,
  `VK_ANDROID_external_memory_android_hardware_buffer`, and a usable timeline
  semaphore (core 1.2 or extension plus enabled feature). Even when all are
  present, Kotlin reports `transportBackendImplemented=false`, and Dart remains
  fail-closed with `transport_backend_not_implemented_*`.
- Moved the native call to a dedicated single-thread executor so driver probing
  cannot block Android's UI thread. Dart imposes a 500 ms timeout and caches one
  result per player controller; timeout, library load errors, JNI/JSON errors,
  missing AHB, missing timeline semaphore, and incomplete probes all remain
  unavailable. Targeted tests passed 14/14, including timeout/cache and the
  "all prerequisites but no transport" gate. Focused analysis passed.
- Standalone CMake release compilation succeeded for all configured ABIs. Two
  local arm64 APK builds succeeded; the final incremental build contains the
  Vulkan 1.1 physical-device gate. Full tests passed 146/146 and full analysis
  retained only the existing 18 info-level findings. Existing NDK/Kotlin/Gradle
  version warnings were recorded previously and remain non-fatal.
- APK inspection found arm64 `libmpv.so`, `libmediakitandroidhelper.so`, and
  `librekazumi_framegen.so`. The first unprivileged `llvm-strings.exe` attempt
  was denied by the sandbox after extraction; rerunning the read-only inspection
  with required permission succeeded. The probe marker and JNI export were both
  present. Final local hashes: APK
  `56e26970a8a6a955abfe6239b9c9e92baf1ef3a6e288ed14b80e6f42b113ed99`,
  framegen probe `.so`
  `e888fa5350f7925d9b6dd3869053dffc2e02d283f021c7182a3e829be92f19ec`,
  and safe `libmpv.so` remains exactly
  `7deb3537ac6de412185a1dc95900a4b2ebf74737937652bde7cd780c4cab095a`.
  The APK was not installed or executed.
- Created commit `3e3de58` (`feat: add headless Vulkan capability probe`) with
  only the native probe/CMake integration, asynchronous Kotlin bridge, Dart
  timeout and fail-closed gates, tests, CI packaging marker check, and journal.
  Amend this operation record into the same unpushed commit, then push through
  the local proxy and require the complete Android CI gate to pass.

### Transport reference audit (2026-08-14)

- While native-probe CI runs, downloaded two reference repositories through
  `mixed:10808` into untracked `work/references/` and checked out detached exact
  commits: `lsfg-vk-android` at
  `3e89e5439a98f55d5acb003d20039426ab24e69c` and
  `LSFG-Android-Application` at
  `b84754199823615d32d65fe33ea59481dca88dcf`. They are read-only research
  inputs and must never be staged into ReKazumi.
- Initial sandbox-side `git rev-parse` was blocked by Git's dubious-ownership
  protection because the approved network clone ran as the host user. Did not
  modify global `safe.directory`; repeated each read with a command-local exact
  safe-directory value and verified both hashes.
- License audit corrected an earlier overconfident assumption. The pinned
  Android application snapshot's root `LICENSE` contains GPL-3.0, while its
  README claims the application is under a custom no-commercial/no-app-store
  license. Treat this contradiction as restrictive: use the application only
  to understand observable architecture and copy none of its source. Updated
  `docs/frame-generation-architecture.md` accordingly. The separately pinned
  `lsfg-vk-android` and its framegen directory state MIT, but the actual LSFG
  shader payload still requires a user-owned proprietary `Lossless.dll` and is
  not a redistributable default algorithm.
- Native-probe commit was amended to final id `1d14a0b`, pushed through the
  proxy, and CI run `31764268658` passed in 10m29s. It passed formatting, 146
  tests, analysis, CMake/arm64 APK build, exact safe `libmpv` checks, packaged
  `librekazumi_framegen.so` marker verification, package id, and upload.
- Added HopperRender/mpv-frame-interpolator as a third untracked read-only
  reference at exact commit
  `0d586cd4a78f2905f65b82fb6ac87e2829477479`. The first license inspection
  guessed a nonexistent plain `LICENSE` filename and returned exit 1; the repo
  actually carries `LICENSE.GPL` and `LICENSE.LGPL`, and Meson declares
  GPL2+/LGPL2.1+, compatible with ReKazumi GPL. Hash was confirmed using the
  same command-local safe-directory handling. No reference source was copied.
- HopperRender confirms a no-model path: hierarchical block matching,
  bidirectional warp, occlusion/artifact correction, and blend. Its desktop
  OpenCL/CPU integration is not suitable directly. Updated the architecture
  decision to an APK-bundled Vulkan compute implementation inside mpv
  `gpu-next`/libplacebo's existing device and queue; no runtime GitHub model and
  no proprietary DLL. LSFG remains reference/optional research only.
- Current safe `libmpv.so` contains `gpu-next`, libplacebo, Android Vulkan, and
  Vulkan hardware-decode symbols, so a same-device path is available. One
  Windows `rg` inspection used shell-style wildcards in path arguments and
  returned an invalid-path error after producing the useful first search; the
  follow-up used explicit paths. The `work/mpv` tree still contains the prior
  rejected QCOM experiment as four dirty source files. Preserve it unchanged
  until that patch is cleanly isolated; do not build or ship those dirty files
  as the new backend.
- Created commit `41947a5` (`docs: select open Vulkan frame generation path`)
  containing only the license/reference audit, resolved algorithm decision,
  and journal. Amend this operation record into the same unpushed docs commit;
  then push through the proxy. These paths do not trigger Android CI, whose
  source revision `1d14a0b` has already passed the complete gate.
