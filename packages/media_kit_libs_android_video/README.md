# ReKazumi Android video runtime

This local Flutter plugin replaces only the Android `media_kit` native-library
package. It keeps the upstream v1.2.6 libraries for non-arm64 targets and uses
the reproducible `afme-runtime-v1` ReKazumi build for arm64.

Every downloaded JAR is pinned by SHA-256. The current arm64 build is a
fail-closed safety runtime: it does not resolve or invoke either QCOM GLES
frame-generation extension and keeps playback at the source frame rate. It
contains no RIFE/ncnn library or model. The 3x setting is unavailable until a
separately validated backend replaces the rejected driver-extension path.
