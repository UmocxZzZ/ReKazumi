# ReKazumi Android libmpv

ReKazumi uses a pinned `Predidit/libmpv-android-video-build` base and patches
mpv's OpenGL renderer to use Qualcomm Adreno Frame Motion Engine (AFME).

The implementation keeps two original frames as GPU textures. With the
previous frame first and the current frame second, positive scale factors
`+1/3` and `+2/3` generate the two forward presentations. Each generated phase
is submitted on its own presentation frame and cached as part of a fixed
three-phase sequence. A 120 Hz display only holds these phases; it does not
increase the generation factor.

AFME runs after mpv's source-frame shaders in the same OpenGL ES context. This
keeps Anime4K and frame generation GPU-resident and removes the former CPU
video-filter, ncnn, Vulkan upload/readback, and model distribution path.
The mpv and Anime4K render surfaces remain FP16. Immediately before AFME, two
full-resolution GPU passes convert the temporal inputs to dedicated RGB8
textures (RGBA8 only if RGB8 is unavailable), matching Qualcomm's reference
implementation. AFME outputs use the same fixed-point format. This boundary is
required because positive extrapolation from RGBA16F repeatedly hung the
Adreno 830 display stack even with one job per presentation frame.

The Android player selects `vo=gpu`, the `android` EGL context, and keeps
`video-sync=audio`. The patched VO retains original-frame history and submits
the original/1/3/2/3 phases against the source frame's realtime PTS. It never
changes mpv's media clock. If a generated phase misses its deadline it is
dropped instead of being presented in a catch-up burst.

Qualcomm's reference path submits one AFME job in a display frame and samples
its output without a blocking finish. ReKazumi follows the same cadence and
keeps source/output textures alive for ordered GLES consumption. Batching two
positive jobs behind `glFinish()` is also unsafe and must not be reintroduced.

The GitHub workflow installs
`patches/mpv/0002-add-adreno-afme-frame-generation.patch` into the pinned build
and publishes the arm64 JAR used by ReKazumi.
