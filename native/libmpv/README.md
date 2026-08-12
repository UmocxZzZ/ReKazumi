# ReKazumi Android libmpv

ReKazumi uses a pinned `Predidit/libmpv-android-video-build` base and patches
mpv's OpenGL renderer to use Qualcomm Adreno Frame Motion Engine (AFME).

The implementation keeps two original frames as GPU textures and calls
`glExtrapolateTex2DQCOM` twice per source pair. Qualcomm's scale factor is
relative to the second input, so `-2/3` generates `t=1/3` and `-1/3` generates
`t=2/3`. The results are cached as a fixed three-phase sequence. A 120 Hz
display only holds these phases; it does not increase the generation factor.

AFME runs after mpv's source-frame shaders in the same OpenGL ES context. This
keeps Anime4K and frame generation GPU-resident and removes the former CPU
video-filter, ncnn, Vulkan upload/readback, and model distribution path.

The Android player selects `vo=gpu`, the `android` EGL context, and keeps
`video-sync=audio`. The patched VO requests the next original frame, prepares
the two AFME outputs, and submits the original/1/3/2/3 phases against the
source frame's realtime PTS. It never changes mpv's media clock. If a generated
phase misses its deadline it is dropped instead of being presented in a
catch-up burst.

Each AFME extension call is completed before the next call or texture reuse.
This deliberately serializes the Adreno work to protect the Flutter GLES
context from the driver-side asynchronous resource hazard observed on device.

The GitHub workflow installs
`patches/mpv/0002-add-adreno-afme-frame-generation.patch` into the pinned build
and publishes the arm64 JAR used by ReKazumi.
