# ReKazumi Android video runtime

This local Flutter plugin replaces only the Android `media_kit` native-library
package. It keeps the upstream v1.2.6 libraries for non-arm64 targets and uses
the reproducible `rife-runtime-v1` ReKazumi build for arm64.

Every downloaded jar is pinned by SHA-256. The arm64 build adds mpv's
`rife-ncnn` filter; `libkazumi_rife.so` itself is built by the app CMake project.
