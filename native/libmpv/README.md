# ReKazumi Android libmpv

ReKazumi uses a pinned `Predidit/libmpv-android-video-build` base and adds the
`rife-ncnn` mpv video filter. The filter is intentionally fixed to 3x output:
for every pair of original frames it emits the first original frame followed
by frames at `t=1/3` and `t=2/3`. Generated frames are never used as model
inputs.

The filter loads `libkazumi_rife.so` at runtime. This keeps ncnn and the RIFE
model implementation out of `libmpv.so`, while allowing mpv to own frame
ordering and PTS assignment. The Android application builds that shared library
from `android/app/src/main/cpp`.

Duplicate and scene-cut pairs bypass inference and emit held source frames.
The default thresholds are configurable through filter options, but the 3x
factor is not configurable by design.

The GitHub workflow copies `vf_rife_ncnn.c` into the pinned mpv source tree,
applies `patches/mpv/0001-add-rife-ncnn-filter.patch`, and publishes the arm64
JAR consumed by the app build.
