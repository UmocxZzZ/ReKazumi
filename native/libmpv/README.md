# ReKazumi Android libmpv

ReKazumi uses a pinned `Predidit/libmpv-android-video-build` base. The current
arm64 runtime is a safety rollback: both proprietary Qualcomm GLES
frame-generation extensions are disabled after device-level failures on the
OPlus 13T / Adreno 830 reference device.

The former `GL_QCOM_motion_estimation` experiment remains documented below for
postmortem value, but the runtime does not discover its entry point, cannot
schedule 3x phases without a validated backend, and falls back to ordinary
source-rate playback.

The implementation keeps the current and next original frames as GPU textures.
It estimates both current-to-next and next-to-current motion, then synthesizes
`t=1/3` and `t=2/3` with inverse warping and forward/backward consistency
weights. Each generated phase is cached as part of a fixed three-phase
sequence. A 120 Hz display only holds these phases; it does not increase the
generation factor.

Motion estimation runs after mpv's source-frame shaders in the same OpenGL ES
context. This keeps Anime4K and frame generation GPU-resident and removes the
former CPU video-filter, ncnn, Vulkan upload/readback, and model distribution
path. The mpv, Anime4K, and synthesized presentation surfaces remain at full
resolution in the existing FP16 path. Two GPU passes create block-aligned R8
luma analysis textures, as required by the extension, and hardware writes the
forward/backward vectors to RGBA16F textures for the synthesis shader.

The Android player selects `vo=gpu`, the `android` EGL context, and keeps
`video-sync=audio`. The patched VO retains original-frame history and submits
the original/1/3/2/3 phases against the source frame's realtime PTS. It never
changes mpv's media clock. If a generated phase misses its deadline it is
dropped instead of being presented in a catch-up burst.

Do not restore either `GL_QCOM_motion_estimation` or
`GL_QCOM_frame_extrapolation` on the reference
OPlus 13T/Adreno 830. Every tested positive extrapolation variant caused a
repeatable SurfaceFlinger hang and SystemUI restart: FP16 and RGB8, blocking and
nonblocking, and batched and one-job-per-presentation submissions. The negative
experiment avoided the system hang but placed previous-to-current intermediate
frames after the current frame, causing severe temporal oscillation. Neither
variant is a valid fallback. The subsequent motion-estimation build froze and
then visibly corrupted the image. A future backend must use an explicitly
synchronized, validated Android/Vulkan architecture and fail closed on any GPU
or presentation error.

The GitHub workflow installs
`patches/mpv/0002-add-adreno-afme-frame-generation.patch` into the pinned build
and publishes the arm64 JAR used by ReKazumi.
