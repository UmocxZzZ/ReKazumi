# ReKazumi Android video runtime

This local Flutter plugin replaces only the Android `media_kit` native-library
package. It keeps the upstream v1.2.6 libraries for non-arm64 targets and uses
the reproducible `afme-runtime-v1` ReKazumi build for arm64.

Every downloaded JAR is pinned by SHA-256. The arm64 build patches mpv's
OpenGL ES renderer with fixed 3x Adreno motion estimation and full-resolution
bidirectional GLES synthesis. It contains no RIFE/ncnn library or model and
does not call the unsafe QCOM full-frame extrapolation extension.
