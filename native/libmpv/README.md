# ReKazumi Android libmpv

ReKazumi uses a pinned `Predidit/libmpv-android-video-build` base. The current
arm64 runtime is a safety rollback: both proprietary Qualcomm GLES
frame-generation extensions are disabled after device-level failures on the
OPlus 13T / Adreno 830 reference device.

The former Qualcomm experiments remain historical only. The new off-device
prototype targets mpv `gpu-next` and uses libplacebo's existing Vulkan device,
queue, resource tracking, and shader dispatch. It does not create another
`VkDevice`, perform CPU readback, invoke ncnn, or retrieve a model at runtime.

The prototype converts the current and next original frames to persistent
source-resolution FP16 RGB textures, computes a coarse bidirectional block
motion field, and synthesizes `t=1/3` and `t=2/3` with inverse warping plus
forward/backward consistency weights. Generated textures are never temporal
inputs. Anime4K remains in the final gpu-next render path after synthesis.

The VO scheduler uses source PTS and keeps `video-sync=audio`. It presents only
original/1/3/2/3 phases; 120 Hz does not increase the generation factor. Late
optional phases are dropped instead of being submitted in a catch-up burst.
Allocation, shader creation, or dispatch failure disables generation for that
VO session and falls back to the original frame.

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
`patches/mpv/0002-add-rekazumi-vulkan-frame-generation.patch` into the pinned
build and uploads an arm64 prototype artifact. It cannot publish or replace the
known-safe app runtime. ReKazumi's Dart capability gate remains fail-closed, so
this artifact is not selectable, packaged, installed, or run on the phone.
