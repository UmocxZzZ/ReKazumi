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

### Single-device gpu-next prototype (2026-08-14)

- Documentation commit was amended to final id `9134d68` and pushed. The next
  implementation remains off-device: no APK installation, app launch, playback,
  display-rate change, or adb command is authorized while building the first
  Vulkan prototype.
- Cloned pinned libplacebo read-only into untracked
  `work/references/libplacebo` at exact commit
  `d4624cbfb37fdef337a7da5794b66202671a89cd`. The proxy transfer completed in
  about 173 seconds. Like the other approved network clones, its host ownership
  triggers Git's sandbox-side dubious-ownership check; use only an exact
  command-local `safe.directory` for revision/status reads and never weaken the
  global Git safety configuration.
- An attempt to clone the existing local `work/mpv` into a clean prototype tree
  failed before creating the destination because Git also rejected that source
  repository's inner `.git` ownership. This did not modify the dirty QCOM
  experiment. Recovery downloaded a new isolated upstream mpv checkout through
  `mixed:10808` into untracked `work/mpv-open-framegen`, detached at the pinned
  base `32a164cc017acab50389f2194f720ccfd0b01a28`. Its clean status and revision
  were confirmed with an exact command-local safe-directory value.
- Read-only safe-runtime string inspection confirmed `gpu-next`, libplacebo,
  Vulkan, and Android Vulkan hardware-decode support. The search utility returned
  exit code 1 despite printing the requested matches because one alternative had
  no match; this is a command-result interpretation mistake, not evidence that
  the useful symbols are missing.
- Mapped the fixed-3x insertion point in clean `vo_gpu_next`: mpv already queues
  original source frames into `pl_queue`, obtains a `pl_frame_mix`, and renders
  once through libplacebo. The rejected dirty tree's scheduler is useful only as
  timing evidence; its QCOM code must not be copied. The clean implementation
  will request the next original, select exact source-pair phases 1/3 and 2/3,
  generate offscreen textures on gpu-next's existing `pl_gpu`/queue, and retain
  exactly one final swapchain presentation per phase.
- The first targeted libplacebo API search included a nonexistent top-level
  `tests` directory, so `rg` returned exit code 1 after producing useful hits.
  The actual tests live under `src/tests`; repeated inspection against public
  headers and concrete examples succeeded. Pinned APIs support this design:
  `pl_dispatch_begin`, `pl_shader_custom`, sampled/storage descriptors,
  `pl_dispatch_compute`, and `pl_tex_recreate`. No private Vulkan device or
  second queue is required.
- Planned prototype boundary: first add a model-free, full-resolution
  bidirectional warp/blend compute pass with a bounded coarse block-search
  motion field, but keep activation impossible in the shipped app until native
  build, marker/hash, pacing, failure, and visual tests pass. Any allocation,
  shader compilation, or dispatch failure must bypass to the original frame;
  generated frames may never become temporal inputs.
- Implemented the first isolated mpv prototype in `work/mpv-open-framegen`.
  Source-timed VO scheduling repeats each eligible source interval exactly three
  times at original/1/3/2/3 PTS, drops missed optional phases instead of
  bursting, and requests the next original without enabling display-sync or
  changing the media clock. The gpu-next path reuses libplacebo's current/next
  mapped originals, never a generated texture.
- The offscreen algorithm uses source-resolution FP16 RGB inputs, one 16x16
  coarse bidirectional block-motion field with a bounded +/-12-pixel search,
  and two full-resolution compute warps with forward/backward consistency
  weights. The generated RGB frame then returns to gpu-next's normal final
  render, keeping Anime4K/upscale after synthesis. This is the first compile
  prototype, not yet the final hierarchical search, duplicate/cut classifier,
  performance result, or device-approved backend.
- Reused the existing `pl_gpu` and libplacebo dispatch so resource barriers and
  queue submission stay in the same backend. No Vulkan instance/device/queue,
  AHardwareBuffer bridge, CPU readback, JNI frame transfer, model file, or
  runtime download was added. Allocation, source conversion, shader creation,
  and dispatch failures set a sticky VO failure and force future scheduling
  back to multiplier 1.
- The first automated `apply_patch` attempt to replace the tracked historical
  patch failed atomically because the generated patch text did not place
  `*** End Patch` on its own final line. No tracked file changed in that attempt.
  Corrected the patch framing and created
  `0002-add-rekazumi-vulkan-frame-generation.patch`, removing the old QCOM-named
  patch from the build path.
- Converted the native workflow into an upload-only Vulkan prototype build:
  it now has read-only repository permission, has no release-publication input
  or step, and writes a distinct prototype JAR name. It therefore cannot
  overwrite the known-safe `afme-runtime-v1` asset. The app plugin remains
  pinned to the safe fail-closed JAR and Dart still marks 3x unavailable.
- Created a second isolated clean mpv checkout at the exact pinned base under
  untracked `work/mpv-vulkan-patch-check`. The local clone succeeded only with
  exact command-local safe-directory values for the source worktree and its
  `.git`; global Git safety was unchanged. `git apply --check`, actual apply,
  and `git diff --check` all passed, producing only the intended three mpv
  source changes. Next gate is an arm64 native compile in GitHub Actions; no APK
  packaging, installation, phone launch, or playback is part of that gate.
- Staging validation reported trailing-whitespace warnings only on embedded
  unified-diff blank context lines (`" "`) inside the new `.patch` file; the
  patched C sources themselves pass `git diff --check`. An attempted
  zero-context (`--unified=0`) regeneration removed those cosmetic container
  warnings but proved too fragile: reverse/apply checks failed at several hunks.
  The combined PowerShell validation continued after those failures and ended
  with exit code 0 because its final command succeeded, so the visible per-step
  errors—not the aggregate exit code—were used. Restored the conventional
  three-line-context patch and discarded the zero-context variant.
- Created a fresh third isolated checkout
  `work/mpv-vulkan-patch-check-2` rather than trusting the ambiguous prior
  validation tree. The restored contextual patch again passed apply-check,
  actual application, patched-source whitespace validation, and intended
  three-file diff statistics. Patch-container blank-context warnings are
  accepted as standard unified-diff syntax; they are not source whitespace.
- Created local commit `f509f7c` (`feat: prototype Vulkan frame generation in
  gpu-next`) with only the upload-only workflow, native build script/README,
  replacement mpv patch, and this journal. The unchanged-content
  `pubspec.lock` and all generated/reference directories remain excluded.
  Amend this operation record into the same unpushed commit, then push through
  `mixed:10808`. The push may start only the isolated native compile workflow;
  that workflow has no release write permission and must not be treated as a
  device-ready runtime even if compilation succeeds.
- The amended prototype commit is `3a6a0c4`; push through `mixed:10808`
  succeeded. The first two `gh run list` queries accidentally omitted the fork
  selector and returned upstream `Predidit/Kazumi` history. This was a read-only
  repository-targeting mistake. Corrected every following query to explicit
  `-R UmocxZzZ/ReKazumi` and found native run `31766051267` at the expected
  commit.
- Native run `31766051267` completed successfully in 11m15s. Patch application,
  pinned mpv/libplacebo Android arm64 compilation, helper packaging, prototype
  JAR creation, and artifact upload all passed. This proves C API/ABI and link
  compatibility; it does not compile the dynamically generated GLSL at runtime
  and does not prove visual correctness, performance, or display safety.
- Several 60-second local `gh run watch` windows timed out while the remote job
  continued normally. A live-log API attempt first incorrectly supplied the
  unsupported `gh api -R` flag; the corrected explicit endpoint returned
  `BlobNotFound`/404 because GitHub does not expose the job-log blob until the
  job is complete. Neither monitoring mistake changed remote or local state.
- Artifact metadata is valid: id `9206548985`, name
  `rekazumi-vulkan-framegen-prototype-arm64`, size 9,090,238 bytes. The first
  local `gh run download` timed out after 184 seconds, left no destination, and
  left one low-CPU `gh` process. Stopped that exact PID; the following PID check
  returned exit 1 because the process was successfully absent. No partial file
  was accepted.
- A second download with explicit `HTTP_PROXY`/`HTTPS_PROXY` at
  `127.0.0.1:10808` failed explicitly on the Actions Azure blob URL with a TLS
  handshake timeout. A third authenticated `curl` retry through the same proxy
  exhausted its 300-second limit and left only a zero-byte untracked
  `artifact.zip`; it is invalid and must never be unpacked or used. Do not spend
  more development time retrying the external blob channel.
- Recovery plan: move the required JAR structure, SHA-256, required Vulkan
  prototype marker, option marker, fail-closed marker, and rejected-QCOM-string
  checks into the native CI job before artifact upload. This makes binary
  validation authoritative without a local download. It still must not publish
  the prototype or update the app runtime pin.
- Added the pre-upload binary gate and created local commit `a12cc56` (`ci:
  verify Vulkan framegen prototype binary`). Amend this operation record into
  the same unpushed commit, then push it through the proxy and require the new
  native run to pass the marker/hash gate. The resulting hashes may be trusted
  from CI logs even if the local Azure artifact download remains unavailable.
- The amended CI-gate commit is `79d9ab5`; push succeeded and native run
  `31767282557` passed in 12m47s. The new pre-upload gate verified JAR layout,
  non-empty arm64 `libmpv.so`, option/active/fail-closed markers, and absence of
  `GL_QCOM_`, `glExtrapolateTex2DQCOM`, and `glTexEstimateMotionQCOM` before
  uploading. JAR SHA-256 is
  `07507dd445a979298e36c42dbb06763de39bd5ece760decd8e6224b6817368bf`;
  contained `libmpv.so` SHA-256 is
  `d2e291d0442dcc49322d40f0036fc74d18a0b70d2bf2e1d386b08a7a3d0891f4`.
  Artifact id is `9206989522`, 9,090,238 bytes. Only upstream Node/action
  deprecation annotations were reported. No local download is needed.
- Located the pinned NDK 27.2 `glslc` and created equivalent explicit-binding
  compute shaders under untracked `work/shader-validation`. The initial motion
  and warp shaders compiled successfully for Vulkan 1.1 SPIR-V, proving their
  GLSL syntax independently of the C compile. These validation files and SPIR-V
  outputs are generated research artifacts and must not be staged.
- Extended the isolated prototype with a second coarse-grid FP16 score texture.
  Motion analysis writes normalized best forward/backward match costs; warp
  holds the first original for near-duplicate blocks and high-cost/cut blocks,
  avoiding line breathing and cross-cut fusion without reducing source/output
  resolution. This is a local conservative per-block gate, not yet a global
  scene classifier.
- Added libplacebo dispatch timing callbacks and structured native counters for
  pairs, generated phases, bypasses, motion milliseconds, and warp milliseconds.
  Moved `pl_dispatch_reset_frame` to once per generated presentation so the
  dispatcher advances/collects timing correctly for phase 1 and phase 2.
- Updated the equivalent validation shaders for the score texture and bypass
  logic. NDK 27.2 `glslc --target-env=vulkan1.1 -O` passed again; SPIR-V hashes
  are motion `0ade46cc6017201c55c04bcf96ebe605b0d8be781db362e39c7a7d4de0325dc0`
  and warp `f7b467bd19205d1d127a95e13e28be71d0cd81fc04b1f41252089eac0051d5b1`.
- Regenerated the contextual mpv patch and applied it from scratch in a fourth
  isolated pinned checkout `work/mpv-vulkan-patch-check-4`. Apply-check, actual
  apply, and patched-source whitespace validation passed; the intended diff is
  still limited to `vo.c`, `vo.h`, and `vo_gpu_next.c`. Next gate is another
  upload-only arm64 compile and binary-marker check. The phone remains unused.
- Created local commit `7ecb821` (`feat: add framegen bypass scores and timing`)
  containing only the updated mpv patch and journal. Amend this record into the
  same unpushed commit, push through the proxy, and require the complete native
  compile plus binary gate before accepting the score/timing implementation.
- The amended score/timing commit is `76b94ae`; push succeeded and run
  `31768008231` passed the full native build and binary gate in 12m22s. JAR
  SHA-256 is
  `1bb8020ffeadaa09b35d505a71acbe08ba2705969b0d403c22e174506177972f`;
  contained arm64 `libmpv.so` SHA-256 is
  `e2a95235f060afe8c09ee4213439aed9698ad75037bf9aba5974b573f651def3`.
  Required markers were present and all rejected QCOM strings remained absent.
  Only the known upstream action deprecation annotations appeared.
- Reviewed HopperRender's algorithm description again without copying its
  OpenCL source. The relevant behavior is a coarse global offset followed by
  progressively smaller local windows. The current zero-centered per-block
  search would miss camera pans or object motion beyond its local radius, so it
  is not sufficient as the intended quality path.
- Implemented a two-level open Vulkan search in the isolated source. A 33x33
  candidate texture evaluates forward/backward global offsets from -64 to +64
  pixels in parallel at four-pixel steps using a sparse 8x6 frame grid. A tiny
  reduction pass selects the best bidirectional global offsets. Each 16x16
  block then refines independently within +/-16 pixels at two-pixel steps
  around those offsets. This keeps large motion coverage without serializing
  roughly 200,000 texture reads onto one GPU invocation.
- A temporary first version performed the entire global +/-64 search in one
  compute invocation. Its GLSL compiled, but architecture review identified
  poor GPU occupancy and long dependency chains before it was staged or built.
  Replaced it with the parallel cost texture plus 1x1 reduction design; the
  serial version was never committed, packaged, or run.
- NDK 27.2 `glslc` compiled all four equivalent Vulkan 1.1 shaders. SPIR-V
  sizes/hashes: global cost 2,736 bytes
  `a667f1aa03199058a3709e9cc1ae72637abb3b659607acb59900acc5d4f39936`;
  global reduce 1,844 bytes
  `fb711da07c6b2a8a6f3265660e5eb7d9168e8c2e9128d913e2033a2852b3dff1`;
  local motion after the final +/-16 refinement change 3,960 bytes
  `c710386b48ff01bb393c44b046b97d539a164f9496306f4b27a6dfd32bd39613`;
  warp 3,336 bytes
  `f7b467bd19205d1d127a95e13e28be71d0cd81fc04b1f41252089eac0051d5b1`.
- Regenerated the contextual patch after the final local-radius change and
  applied it from scratch in `work/mpv-vulkan-patch-check-6`. Apply-check,
  actual application, and patched-source whitespace validation all passed at
  the exact pinned mpv base. Strengthened CI to require the global-cost,
  global-reduce, and `global-ms=` markers before upload. The app runtime pin and
  device remain untouched.
- Created local commit `83bacc4` (`feat: add hierarchical Vulkan motion search`)
  with only the updated mpv patch, strengthened upload-only marker gate, and
  journal. Amend this record into that unpushed commit, push through the proxy,
  and require the fourth native compile/binary gate before accepting it.
- The amended hierarchical-search commit is `9fb405f`; push through
  `mixed:10808` succeeded and started upload-only native run `31768771519`.
  A read-only status check while it was running showed setup, dependency, SDK,
  NDK, and source preparation complete, with the arm64 native compile still in
  progress and no failed step. Do not interpret an in-progress result as a
  successful build; the binary-marker gate and final conclusion are still
  required.
- Planned next native change while that independent run continues: isolate
  frame-generation source conversion from gpu-next's main renderer state by
  creating a dedicated libplacebo renderer on the existing `pl_gpu`. This must
  not create a second Vulkan instance, device, or queue. Activation remains
  fail-closed if either the compute dispatcher or helper renderer is missing.
  Regenerate the contextual patch from the exact pinned mpv base, apply it in a
  fresh clean checkout, and require another upload-only arm64 compile before
  accepting it. No app runtime pin, APK, installation, adb, or phone state may
  be changed by this operation.
- Regenerated the tracked contextual mpv patch from the isolated pinned source
  after adding the helper renderer. The first attempt to create clean validation
  checkout `work/mpv-vulkan-patch-check-7` failed before creating it: the clone
  command marked only the source worktree as command-local safe, but Git also
  evaluates its inner `.git` path and rejected that path for host/sandbox owner
  mismatch. Subsequent chained validation commands consequently reported that
  the destination did not exist. No global Git setting or tracked source was
  changed. Retry must mark both exact source paths command-locally safe; do not
  weaken global ownership checks.
- Retried with command-local safety entries for both exact source paths.
  `work/mpv-vulkan-patch-check-7` was created at pinned mpv commit
  `32a164cc017acab50389f2194f720ccfd0b01a28`; patch apply-check, actual apply,
  and patched-source `git diff --check` passed. The diff remains limited to
  `video/out/vo.c`, `video/out/vo.h`, and `video/out/vo_gpu_next.c` with 619
  insertions and 11 deletions. Added a CI binary gate for the helper-renderer
  failure marker so a build cannot upload an older/non-isolated native binary.
  A second read-only check of run `31768771519` still showed only the native
  compile in progress, with all preceding steps successful and no failed gate.
- Hierarchical-search run `31768771519` completed successfully in 11m46s.
  Arm64 native compilation, strengthened global-motion marker verification,
  rejected-QCOM absence check, and artifact upload all passed. JAR SHA-256 is
  `2262e609dfad76d25348e49d7a9f8d271c45486dceb21728279351af0075857e`;
  contained `libmpv.so` SHA-256 is
  `25e720f49528ff6f4a2d666a46135bef3eff58bbde74f7b8b5e18a11c703fc8e`.
  Artifact id `9207534287` is 9,090,259 bytes and unexpired. Only the known
  upstream Node/action deprecation annotations appeared. This accepts the
  hierarchical implementation as compile/binary-valid, not device-ready.
- Planned Git operation: stage only the helper-renderer workflow gate, updated
  contextual mpv patch, and this journal; create a dedicated renderer-isolation
  commit, leaving `pubspec.lock` and every generated/reference directory out.
  Push may trigger only the upload-only native workflow. Require its compile and
  helper-marker checks to pass before accepting the isolation change; do not
  publish or pin the resulting prototype artifact into the app.
- The first exact-file staging command was denied when the sandbox could not
  create `.git/index.lock`. No file was staged and the subsequent cached checks
  therefore showed only ordinary unstaged status. This is a local repository
  metadata permission failure, not a source validation failure. Retry the same
  three-path staging operation with repository-write approval; do not broaden
  the staged path set.
- Retried with repository-write approval and staged exactly the three planned
  paths. Cached whitespace checking outside the conventional patch container
  passed, and staged statistics confirmed no unrelated file. Created local
  commit `66014f2` (`feat: isolate Vulkan framegen renderer`). Amend this result
  into that still-unpushed commit, then push through `mixed:10808` and monitor
  the resulting upload-only native workflow to completion.
- The amended renderer-isolation commit is `c37e138`; push through the local
  proxy succeeded. Upload-only native run `31769536108` started at the exact
  head `c37e138d36dec367bcb50c0889d3456b9b63388d`; the unrelated PR workflow was
  skipped as expected. The app runtime pin and phone remain untouched.
- Architecture review while CI runs found that the hierarchical local-refine
  shader still serializes all 289 candidates and five taps inside each block
  invocation. Although this preserves full resolution and search radius, it
  underuses GPU parallelism and could recreate the slow-playback failure at a
  different layer. Planned isolated optimization: calculate a 17x17 candidate
  atlas in parallel, then reduce that atlas once per 16x16 block. At 1080p the
  extra RGBA16F scratch texture is roughly 9 MB. Keep the same +/-16/two-pixel
  radius, five taps, full-resolution warp, duplicate/cut scores, source timing,
  and 3x quality; do not reduce resolution or alter the shipped runtime.
- Implemented the parallel local candidate atlas only in the isolated pinned
  mpv source. Each atlas invocation evaluates one block/candidate pair with the
  unchanged five taps; a separate per-block reduction selects the best forward
  and backward vectors and preserves the same scores. Source-diff whitespace
  validation passes. Added equivalent explicit-binding validation shaders in
  untracked `work/shader-validation`; NDK 27.2 `glslc` compiled both for Vulkan
  1.1. Local-cost SPIR-V is 3,120 bytes with SHA-256
  `d150366b4364e2680eba5d1522d73ea9b003c2c2300ef1094e27d74373ddb008`;
  local-reduce SPIR-V is 2,624 bytes with SHA-256
  `9a5178688d01fe054c54728d5646d21adaa9e5172fd8a22c7ac15310386e9938`.
  These generated validation files remain untracked and must not be staged.
- The first regeneration of the enlarged contextual patch silently exceeded
  the orchestration output budget; the captured diff was truncated even though
  the helper script found a valid beginning and wrote 888 lines. Fresh checkout
  `work/mpv-vulkan-patch-check-8` then correctly rejected it as corrupt at line
  741. This validation failure prevents staging or CI use. Regenerate from the
  same pinned source with an explicitly larger output budget and recreate a new
  clean validation checkout; never repair hunk counts by hand.
- A second one-shot regeneration with a larger outer budget still contained an
  inner tool truncation marker at patch line 468, collapsing two descriptor
  lines into one; apply-check again rejected the hunk at line 741. Two attempted
  `apply_patch` replacements of that corrupted line failed safely because the
  marker's mojibake text did not match byte-for-byte. They changed nothing.
  Read-only line counting found the affected hunk declared 542 new lines but
  contained 541, and direct source-vs-patch comparison located the inserted
  truncation marker. This was a transfer/capture defect, not a Git diff defect.
- Corrected the process without shell file writes or manual hunk edits: queried
  the source diff in three bounded 350-line chunks, asserted exact chunk sizes
  `350/350/189`, rejected any truncation marker, then reassembled all 889 lines
  through `apply_patch`. The existing clean `work/mpv-vulkan-patch-check-8`
  then passed apply-check, actual application, and patched-source whitespace
  validation. The intended diff is still exactly the three mpv files, now 677
  insertions and 11 deletions. Renderer-isolation run `31769536108` remains in
  the native compile step with every preceding step successful.
- A 59-second local `gh run watch` observation window expired while the remote
  renderer-isolation job continued normally. A following explicit status query
  confirmed the job was still compiling, not failed. Run `31769536108` then
  completed successfully in 12m23s: arm64 compile, helper-renderer marker,
  prior global/timing/fail-closed markers, rejected-QCOM absence, and upload all
  passed. JAR SHA-256 is
  `85fb800821ab312cf713612f1f1b151783701e6a8580e31f8b4d51e4ddca1c33`;
  contained `libmpv.so` SHA-256 is
  `730bbc96d63a5d179daf7a2b1e80252114cef8b80e80016a9fa26780fe60352f`.
  Artifact id `9207808743` is 9,093,293 bytes and unexpired. The app pin remains
  unchanged, so this result cannot run on the phone.
- Tightened the parallel-search scratch formats before its native build. Added
  a fail-closed RG16F allocator and use it for global costs, the local candidate
  atlas, and per-block scores; motion/source/output textures remain RGBA16F.
  Thus the 1080p local atlas is roughly 9.4 MB rather than 18.9 MB, with no
  quality or search-radius change. Recompiled the equivalent Vulkan 1.1
  shaders: global cost is 2,744 bytes SHA-256
  `a933cc910ad27688c8f974f3184300a56824fdec86ee99357e4a4491f3b238ff`,
  local cost is 3,128 bytes
  `a9c8edece852cf4491cb7693361a6ac20c8db665d87ce497bfebbd89a936a176`,
  and local reduce is 2,684 bytes
  `bf150e4166686110654d8bdec932abe0ad376801864fae24ae2d95e05667c7a2`.
- Regenerated the final 907-line contextual patch through the bounded-chunk
  method. Fresh pinned checkout `work/mpv-vulkan-patch-check-9` passed
  apply-check, actual application, and patched-source whitespace validation;
  the diff remains exactly the three intended mpv files with 695 insertions and
  11 deletions. Planned Git operation: stage only the two strengthened CI
  markers, updated mpv patch, and this journal; create/push a separate local
  candidate-parallelization commit, then require its upload-only native compile
  and both new block-motion binary markers to pass. No APK/device operation.
- Staged exactly the three planned paths; cached checks outside the conventional
  patch container passed and unrelated paths remained excluded. Created local
  commit `233bc9d` (`perf: parallelize Vulkan block motion search`). Amend this
  result into the still-unpushed commit, push through `mixed:10808`, and monitor
  the resulting native compile/binary gate to completion.
- The amended parallel-search commit is `45348d0`; push through the proxy
  succeeded and started upload-only run `31770325073` at exact head
  `45348d02fc3cbffb87726822bfdaccf6e97612d5`. The PR workflow was skipped as
  expected. Eight bounded 59-second local watch windows expired while the
  remote native compilation continued; explicit status checks consistently
  showed the same compile step active with all predecessors successful. These
  were observation timeouts, not eight CI failures, and no retry run was
  created.
- Run `31770325073` completed successfully in 11m33s. Arm64 compilation, both
  new `ReKazumi block motion cost/reduce` markers, helper/global/timing/failure
  markers, rejected-QCOM absence, and artifact upload all passed. JAR SHA-256
  is `f0825d6f77c399ad8d0f7778567be653ba4fdd9dd849ccb44e83a4d55b015847`;
  contained `libmpv.so` SHA-256 is
  `aa1960e563be4da24959991bbcede5048456c4f85a12f39e92da7694fab925e6`.
  Artifact id `9208081251` is 9,092,358 bytes and unexpired. This accepts the
  parallelized/RG16F source as compile- and marker-valid only; it remains
  unpinned, uninstalled, and unavailable in Dart.
- Updated `docs/frame-generation-architecture.md` with the exact current
  off-device prototype: source-timed phases, same-device helper renderer,
  parallel global/local search, RG16F scratch budget, consistency/bypass logic,
  timing, fail-closed behavior, and the distinction between native CI and
  device safety. This documentation change does not enable any runtime path.
  Planned Git operation: commit only this documentation plus the accumulated
  journal, leaving all unrelated/generated paths untouched, then push it.
- Staged only `AGENT.md` and the architecture document; whitespace and staged
  scope checks passed. Created commit `159849b` (`docs: record Vulkan prototype
  validation`) and pushed it through `mixed:10808`. The branch is now at a safe
  off-device checkpoint: the parallel Vulkan prototype is source/CI-valid but
  remains absent from the app runtime. Next authorized engineering phase is an
  Android Vulkan offscreen output, phase, and GPU-time harness. Do not install,
  launch, present, change refresh rate, or enable Dart 3x before that harness
  passes and a separate short-presentation candidate is explicitly prepared.

### Android Vulkan offscreen validation (2026-08-14)

- Began the next authorized phase with an offscreen-only boundary: no Surface,
  ANativeWindow, swapchain, display-rate change, playback, automatic launch,
  runtime pin, or Dart 3x availability. The harness must run only through a new
  explicit method-channel call and return structured diagnostics; the existing
  capability probe and playback path must not invoke it automatically.
- A grouped read-only inspection guessed workflow filenames
  `.github/workflows/pr_workflow.yml` and `build-android.yml`; both paths do not
  exist, so that grouped tool call returned nonzero and suppressed its other
  parallel outputs. This changed nothing. Listing the directory found the
  actual Android gate at `validate-rife-android.yml`, then inspection succeeded.
- Planned first offscreen gate: create a private Vulkan instance/device/compute
  queue with no presentation extensions, verify RG16F/RGBA16F sampled/storage
  capabilities, execute a deterministic embedded compute shader for `t=1/3`
  and `t=2/3` on synthetic FP16 colors, copy only the tiny validation result to
  a host buffer, and record GPU timestamps. Use a bounded fence wait and destroy
  every object on return. This validates driver shader execution, phase math,
  formats, synchronization, and timing without touching the display stack. It
  does not enable the production transport or claim full algorithm quality.
- Implemented the first isolated harness in source: a reproducible Vulkan 1.1
  compute shader, embedded SPIR-V, explicit `validateOffscreen` method-channel
  call, bounded 8-second Dart/5-second native waits, RG16F/RGBA16F capability
  checks, synthetic FP16 1/3 and 2/3 output readback, GPU timestamps, and
  fail-closed structured results. It creates no Surface, swapchain, or present
  call and leaves `transportBackendImplemented=false`. Added parser tests and a
  CI step that recompiles the shader, compares it byte-for-byte with the
  embedded words, checks native markers, and rejects presentation symbols.
- The first `dart format` invocation through Flutter's `dart.bat` wrapper
  exceeded a 30-second local timeout without output. No Dart process remained;
  source inspection showed only the intended additions, but formatting cannot
  be credited as successful. Retry must call the pinned SDK `dart.exe`
  directly, then use its explicit exit result before testing.
- Direct `dart.exe format` initially failed because the restricted sandbox
  denied creation of Dart's user-level analytics directory under AppData. It
  changed no source. Repeating the same two-file format operation with approved
  user-config access succeeded and reported both files already formatted.
  Focused `flutter test --no-pub
  test/frame_generation_capability_service_test.dart` then passed all nine
  tests, including successful no-surface parsing, native mismatch fail-close,
  timeout, and single-invocation caching.
- Planned compile gate: build an arm64 release APK only to compile/link the new
  Vulkan JNI library and package it for inspection. Do not copy it into a
  candidate directory, publish it, install it, launch it, or change the safe
  libmpv pin. Require C++ `-Werror`, Kotlin/Dart compilation, shader identity,
  package markers, and absence of Surface/swapchain/present symbols first.
- The local arm64 release build completed in 153.8 seconds and produced the
  ordinary build-output APK only; it was not copied, published, or installed.
  Existing NDK-version advisory output remained (notably `jni` requests 28.2),
  but C++ `-Werror`, Kotlin, Dart, linking, and packaging succeeded. APK size is
  50,273,686 bytes, SHA-256
  `bfb1d88059de4a3c9e338781e74a0fc7f0c9941b1449aa1969425e5f3bb89489`.
  Package id/name remain `com.predidit.rekazumi` / `ReKazumi`.
- The packaged arm64 offscreen library is 920,112 bytes, SHA-256
  `ba2db03a6f09b147a1c8cfd03ad25b892e9d52a3dc59088d9dc562ddb24fdd84`.
  It contains the validation marker, exact shader hash, fail-closed transport
  field, and explicit JNI entry; binary inspection found no `ANativeWindow`,
  `vkCreateSwapchainKHR`, or `vkQueuePresentKHR`. Packaged arm64 `libmpv.so`
  still hashes to the safe pinned
  `7deb3537ac6de412185a1dc95900a4b2ebf74737937652bde7cd780c4cab095a`.
  Recompiled shader and 303 embedded words both independently hash to
  `f85d4f123b2f29b864439c1488c6fdc2361be6456746119c7230c9ad0a510b49`.
- Timeout-path review corrected the initial cleanup assumption. Destroying
  Vulkan resources after a submitted command exceeds its fence deadline can be
  invalid because work may still be executing; calling `vkDeviceWaitIdle`
  would reintroduce an unbounded hang. The one-shot harness now quarantines and
  intentionally leaves its private no-surface instance/device for OS cleanup on
  a true fence timeout, reports `resourcesQuarantined=true`, and fails the gate.
  Normal and all pre-submit failure paths still destroy every created object.
- A first NDK `clang-format --dry-run --Werror` check could not execute inside
  the restricted sandbox (`Permission denied`) and changed no files. The same
  read-only check with approved tool execution then showed that both the new
  offscreen files and the long-existing `rekazumi_framegen.cpp` do not match
  the NDK tool's default formatting style. Reformatting the existing probe
  would create a large unrelated rewrite. Decision: mechanically format only
  the newly introduced `rekazumi_offscreen.cpp` and `.h`, keep the existing
  probe's established style, and validate the new files independently.
- A follow-up read-only formatter lookup incorrectly assumed `ANDROID_HOME` or
  `ANDROID_SDK_ROOT` was populated in the current shell and therefore probed
  `C:\\ndk\\...`, which does not exist. It changed nothing. Reading the existing
  `android/local.properties` resolved the configured SDK correctly at
  `C:\\Users\\Skrindo\\AppData\\Local\\Android\\sdk`.
- NDK `clang-format -i` was applied only to the two newly introduced offscreen
  C++ files; their subsequent independent `--dry-run --Werror` check passed.
  Review then found that the Dart pass predicate trusted the native boolean
  fields without requiring the exact validation marker and full embedded
  shader SHA-256. Tightened the gate to require both identities, added a
  mismatch regression test, and made CI require the timeout-quarantine marker
  in the packaged native binary as well.
- After those changes, direct Dart formatting reported no changes and the
  focused capability/offscreen suite passed all 10 tests. The incremental
  arm64 release rebuild then succeeded in 83.7 seconds (Gradle 78.0 seconds).
  The existing NDK advisory remains: the app selects 27.2, most plugins request
  27.0, and `jni` requests 28.2. This is an advisory after a successful build,
  not a new compile failure, and no APK was copied, published, or installed.
- The first post-build binary-inspection command retrieved the build files but
  the restricted sandbox denied execution of NDK `llvm-strings.exe`; its table
  formatting also hid the useful hash columns. No files changed. Repeat the
  same read-only inspection with approved SDK-tool execution and explicit
  line-oriented output before accepting the package.
- Approved post-build inspection found APK SHA-256
  `2e9ac66620f3ff78a7f1708571de6f41486c856ce2f0932f4b5abe17c1c2f388`
  (50,273,810 bytes), native harness SHA-256
  `6b386a0a19eb8a4d29c8017b762d3ac02989f479c90e64ff5cc40da45e532313`
  (920,208 bytes), and unchanged safe `libmpv.so` SHA-256
  `7deb3537ac6de412185a1dc95900a4b2ebf74737937652bde7cd780c4cab095a`.
  Package identity remains `com.predidit.rekazumi` / `ReKazumi`; validation and
  shader markers are present and presentation symbols are absent.
- That inspection also caught a CI-test design error before push: although the
  structured JSON key `resourcesQuarantined` exists and the Dart test covers
  it, the compiler did not retain that short key as one contiguous entry in
  the binary string table, so a `strings | grep` binary check would fail. This
  is not a missing quarantine implementation. Replaced the brittle binary key
  check with an explicit versioned `ReKazumi offscreen timeout quarantine v1`
  policy marker returned by the native report and required by CI. Rebuild and
  re-inspect the marker before accepting the candidate.
- Reformatting and the second incremental build succeeded in 22.5 seconds
  (Gradle 16.7 seconds). The explicit timeout-policy, validation, and shader
  markers are all present; presentation symbols remain absent. APK SHA-256 is
  `80bdc176b92198c36589ec0a53623e8ad1c254090de7a77f09533afc789e2cd9`
  (50,273,942 bytes), native harness SHA-256 is
  `ef544682a818704e0dee248793faa5f92ff7110ad49d4a31daae23fdb219676c`
  (920,320 bytes), and the safe `libmpv.so` hash is still unchanged. This
  build remains inspection-only and was not installed or published.
- Full Flutter tests then passed 150/150. Static analysis exited successfully
  with no warning/error and the same 18 pre-existing info-level findings.
  Recompiling the shader with NDK 27.2 produced exact SHA-256
  `f85d4f123b2f29b864439c1488c6fdc2361be6456746119c7230c9ad0a510b49`;
  independently decoding all 303 embedded words in memory produced the same
  hash.
- Final source review found the implementation did not yet meet its recorded
  one-shot property: each Dart service cached its call, but constructing a new
  service could execute the native harness again. Moved caching into the native
  function via thread-safe function-local static initialization, making it one
  Vulkan execution per app process even across service instances. Also reject
  zero GPU timestamp deltas in native and Dart, with a regression test, so the
  timing portion cannot be reported as validated without an actual measurement.
- After native one-shot/timestamp hardening, NDK formatting passed, direct Dart
  formatting changed nothing, the focused suite passed 11/11, and the final
  arm64 release build succeeded in 82.5 seconds (Gradle 71.2 seconds). Final
  inspection-only APK SHA-256 is
  `6bb9561bf10242e99b50773aa1a98f94dd2f64de5f0dda23362126d920c44aa0`
  (50,274,766 bytes); native harness SHA-256 is
  `b423fc820cfdb149769d011d9d5127686c4fddc5a072a7c44ff788bf864040ae`
  (920,808 bytes); safe `libmpv.so` remains
  `7deb3537ac6de412185a1dc95900a4b2ebf74737937652bde7cd780c4cab095a`.
  Validation, shader, timeout-policy, and zero-timestamp rejection markers are
  present; `ANativeWindow`, swapchain creation, and queue presentation symbols
  are absent. `git diff --check` passed. No APK/device operation occurred.
- Planned Git operation: stage only the workflow, journal, CMake/native shader
  and offscreen harness, JNI/Kotlin bridge, Dart fail-closed service, and its
  tests. Explicitly exclude user/unrelated `pubspec.lock` status plus generated
  `device-build/`, package build output, `work/`, and ordinary APK output. Check
  the cached scope and whitespace, commit this offscreen validation gate, push
  through `mixed:10808`, then require the Android workflow to pass before any
  separate device-invocation design is considered.
- Exact staging selected only the 11 intended paths and excluded every listed
  unrelated/generated path. The first cached whitespace check found one new
  blank line at EOF in the generated SPIR-V header. This is a packaging-text
  issue only; remove that final blank line, restage only the header/journal, and
  require the cached check to return success before committing.
- Removed the extra EOF blank line, then cached whitespace and exact 11-path
  comparison passed. Created local commit `0e1f57c` (`test: add Vulkan offscreen
  validation gate`), with unrelated `pubspec.lock` and generated directories
  still outside the commit. Amend this journal entry into that unpushed commit,
  push the resulting hash through `mixed:10808`, and require its Android CI.
- The amended implementation commit is `315efef8b42cdf19717d9b2b0ebba8efd8fbf7d1`;
  push through `mixed:10808` succeeded. Exact-head Android run `31774553107`
  started, while the unrelated PR workflow was skipped as expected. Five
  bounded 59-second `gh run watch` windows expired locally while the same
  remote cold Android build continued. These were observation timeouts, not
  CI failures or retries; status queries consistently showed the first eight
  steps successful and one uninterrupted arm64 build in progress.
- Run `31774553107` then completed successfully. Its cold arm64 build passed in
  7m16s; exact embedded-shader reproduction, packaged validation/timeout/shader
  markers, forbidden presentation-symbol check, tests, analysis, and APK upload
  all passed. Uploaded artifact `rekazumi-safe-android-arm64` has id
  `9209537676`, size 49,457,784 bytes, is unexpired, and expires 2026-11-12.
  This remote artifact is CI evidence only: it has not been downloaded,
  installed, launched, or promoted to a device candidate. Next phase is to
  design an explicit one-shot device invocation that exposes only structured
  offscreen diagnostics and cannot enter playback or presentation paths.

### Isolated device invocation design (2026-08-14)

- Pushed journal commit `1bbd37f` after recording the successful offscreen CI.
  Read-only inspection of the existing logs page and Android channel found that
  a manual log-page button could call the harness, but the current JNI method
  would still execute inside the main app process. A pathological driver hang
  before/around the bounded fence could therefore strand an app worker even
  though the harness has no Surface. Do not expose that direct route on device.
- Chosen isolation boundary: move the only offscreen JNI declaration to a
  non-exported Android service in dedicated `:framegen_validation` process.
  The main process binds explicitly, receives only Messenger bundles/raw JSON,
  enforces a 7-second wall timeout, and can kill the known same-package child
  PID on timeout. The child sends its PID before native work, executes only once,
  returns the result, then terminates itself so both normal and quarantined
  Vulkan state receives OS cleanup. Remote death must fail closed. First compile
  and CI-validate this transport; add a confirmation-gated log-page button only
  in a separate step after isolation is proven. No installation/device action.
- Implemented the isolation transport in source: a non-exported dedicated
  service/process, Messenger protocol, PID-first/result PID redundancy, main
  process bind/death handling, 7-second timeout and child kill, child self-exit
  after reply, and cancellation on activity destruction. The main activity no
  longer declares or invokes the offscreen JNI symbol; it only parses raw JSON
  returned by the child. Dart now requires `isolatedProcess=true` in addition
  to every prior gate, with a non-isolated regression test. The UI still has no
  trigger and playback remains disconnected. Next operation is formatting,
  focused tests, and an inspection-only arm64 compile/manifest-symbol audit.
- Direct formatting reported no Dart changes, focused tests passed 12/12, and
  the inspection-only arm64 build succeeded in 143.7 seconds (Gradle 133.4
  seconds). Merged Manifest inspection confirmed the validation service is
  `exported=false`, uses `:framegen_validation`, and stops with the app task.
  Dynamic symbols contain only the service offscreen JNI entry plus the main
  activity's read-only capability probe; the old main-activity offscreen JNI
  entry is absent. APK SHA-256 is
  `69739904a581f3c48d7885df188afa644d4d3cdfb73f963e0513fdc64b3ff11e`
  (50,277,078 bytes) and native library SHA-256 is
  `6bcee7fa266fb023cbe731f7465685235fd3a866cd567416d8de4793b78226e0`
  (920,824 bytes). No device action occurred.
- Timeout-kill review added a defense against future manifest regressions: the
  service now verifies its actual running process name is exactly the dedicated
  suffix before starting native work, while the client rejects missing or
  main-process-equal PIDs and will never kill its own PID. CI now parses the
  merged Manifest and checks JNI ownership explicitly. Recompile before
  accepting this hardening.
- The PID/process-name hardened incremental arm64 build passed in 70.6 seconds
  (Gradle 64.7 seconds). Full tests passed 152/152; analysis again returned no
  warnings/errors and only the same 18 existing info findings. Final local
  transport APK SHA-256 is
  `b4d6c32db8338272b4b38c66b9f385151b02d32c711c53adf101a0edd3c06c89`
  (50,277,330 bytes); native harness remains
  `6bcee7fa266fb023cbe731f7465685235fd3a866cd567416d8de4793b78226e0`
  (920,824 bytes), and safe `libmpv.so` remains the exact pinned
  `7deb3537ac6de412185a1dc95900a4b2ebf74737937652bde7cd780c4cab095a`.
  Repeated merged-Manifest/JNI inspection passed and `git diff --check` passed.
  No download, install, launch, display, or playback operation occurred.
- Planned Git operation: stage only the workflow, journal, app Manifest, JNI
  ownership change, three new isolation Kotlin files, MainActivity transport,
  Dart isolation gate, and tests. Exclude unrelated `pubspec.lock` plus every
  generated directory/output. Verify the exact cached scope and whitespace,
  commit/push the isolation transport, then require exact-head Android CI before
  adding any user-visible manual trigger.
- Exact cached whitespace/scope checks passed for the 10 intended files, with
  all unrelated/generated paths excluded. Created local commit `4cb5e3d`
  (`feat: isolate Vulkan validation process`). Amend this record into the still
  unpushed commit, push through `mixed:10808`, and require its exact-head CI.
- The amended isolation commit is
  `1582be8dd5eb8f7ee1ab0034402b370f76b32cf3`; proxy push succeeded and exact
  run `31775921062` completed successfully in 10m24s. Seven bounded 59-second
  local watch windows expired during its single uninterrupted cold arm64 build;
  these were observation timeouts, not failures/retries. All format, 152-test,
  analysis, shader identity, packaged native, merged isolated-service Manifest,
  service-only JNI ownership, forbidden presentation-symbol, and upload gates
  passed. Artifact `rekazumi-safe-android-arm64` id `9210053975` is 49,460,213
  bytes, unexpired until 2026-11-12, and was not downloaded or installed.
- Began the separately reviewable manual-trigger phase only after that success.
  Planned UI is Android-only on the existing logs page, performs no call before
  a non-dismissible explicit confirmation, uses the process-wide cached Dart
  service, persists one structured diagnostic record, and shows a copyable
  result dialog. It must require the exact timeout-policy marker and positive
  isolated PID as well as every prior gate. Add widget tests proving cancel
  invokes nothing and confirmation invokes exactly once. No playback linkage.
- First focused UI test run failed before invoking validation: mounting the
  entire logs page also mounted `SysAppBar`, whose global settings box is not
  initialized in this isolated widget-test environment; both UI tests then hit
  `pumpAndSettle` timeout. Service tests still passed. This is a test-boundary
  mistake, not a runtime validation failure. Refactor the confirmation/action/
  result UI into a standalone widget with an injected service, leaving the logs
  page responsible only for Android visibility and log refresh. Test that small
  widget inside a plain Scaffold so no global app storage is required.
- The first refactored test retry did not compile because the mechanical test
  rewrite omitted one closing `Scaffold` parenthesis in each of two pumpWidget
  trees. Dart formatter identified the exact lines; no runtime code executed.
  Restore both delimiters, format successfully, then rerun both focused files.
- After fixing syntax, the explicit-cancel test passed and proved zero service
  invocations. The confirmed test reached its one invocation but timed out
  waiting for the platform log-directory plugin, which is absent in the narrow
  widget-test host. Make the diagnostic writer injectable: production retains
  the awaited real file append, while tests use an immediate in-memory success.
  This removes a platform-fixture dependency without weakening confirmation or
  persistence behavior.
- With the injected test writer, the focused capability/UI suite passed 15/15.
  The inspection-only arm64 APK build then succeeded in 124.4 seconds (Gradle
  119.0 seconds). Full tests passed 155/155 and static analysis again had no
  warnings/errors, only the same 18 existing info findings. Final manual-gate
  APK SHA-256 is
  `4507a032b339678a47508101fe04f785e4286e2a23029aa3ed05522e1ec3841e`
  (50,284,890 bytes); native harness and safe `libmpv.so` hashes remain exactly
  `6bcee7fa266fb023cbe731f7465685235fd3a866cd567416d8de4793b78226e0`
  and `7deb3537ac6de412185a1dc95900a4b2ebf74737937652bde7cd780c4cab095a`.
  Package identity is `com.predidit.rekazumi` / `ReKazumi`; merged isolation
  attributes remain correct and `git diff --check` passed. No device action.
- Planned Git operation: stage only the journal, MainActivity policy-marker
  parse, logs page/action, awaited diagnostic append, Dart gate, and two test
  files. Exclude `pubspec.lock` and all generated outputs. Verify exact cached
  scope/whitespace, commit and push this manual diagnostic gate, then require
  exact-head Android CI. Do not download/install until that CI succeeds.
- Exact cached whitespace/scope checks passed for the eight intended manual-gate
  files; unrelated/generated paths stayed excluded. Created local commit
  `90dd3d5` (`feat: expose isolated Vulkan diagnostic`). Amend this entry into
  that still-unpushed commit, push through `mixed:10808`, and require its CI.
- The amended manual diagnostic commit is
  `eb40aeecc8d5402425a6abdaafe0556f6ff80118`; proxy push succeeded. Exact-head
  run `31777270613` completed successfully after seven bounded 59-second local
  observation timeouts during one uninterrupted cold Android build. Format,
  155 tests, analysis, arm64 APK, shader identity, packaged native safety,
  isolated Manifest/JNI ownership, forbidden presentation symbols, and upload
  all passed. Artifact `rekazumi-safe-android-arm64` id `9210546524` is
  49,467,880 bytes, unexpired until 2026-11-12. It remains remote and uninstalled
  at this point. Record/push this result before preparing any device candidate;
  never auto-run the shield action or enter playback.
- Committed/pushed CI journal checkpoint `252e297`. `adb devices -l` then showed
  no connected device, so no install was attempted. Began downloading the
  successful CI artifact into new non-overwriting target
  `device-build/offscreen-manual-eb40aee`; the outer command timed out after
  124 seconds while its `gh` child remained alive, with no target or partial
  candidate visible. A 30-second follow-up found the child still nearly idle
  and the target absent. A grouped read-only network/process inspection then
  failed because Windows denied CIM command-line access; a separate connection
  query found no TCP connection for the orphan. No candidate file was changed.
- Terminated only that stalled `gh` process (PID 18940), verified the intended
  candidate root resolves exactly under `C:\\ReKazumi\\device-build`, created the
  previously absent unique directory, and copied the already local/CI-validated
  exact-source inspection APK there. Candidate path is
  `C:\\ReKazumi\\device-build\\offscreen-manual-eb40aee\\ReKazumi-offscreen-manual-eb40aee.apk`,
  size 50,284,890 bytes, SHA-256
  `4507a032b339678a47508101fe04f785e4286e2a23029aa3ed05522e1ec3841e`.
  Device list remained empty afterward. This candidate is prepared but not
  installed or launched; when a device reconnects, install only this exact hash
  and leave the shield action entirely manual.
