# ReKazumi Android 3× 帧生成架构

## 当前状态

`GL_QCOM_frame_extrapolation` 与 `GL_QCOM_motion_estimation` 已永久退出产品
路径。前者在 Adreno 830 上导致显示栈卡死，后者导致播放冻结与花屏。当前
arm64 运行库保持普通源帧率播放，设置层也不会启用 3× 调度。

产品目标不变：保持源时间轴，将相邻两张原始帧直接生成 `t=1/3`、`t=2/3`，
Anime4K 与帧生成全程驻留 GPU，120 Hz 只负责呈现。

## 可复核的现成实现

- [LSFG-Android](https://github.com/FrankBarretta/LSFG-Android/tree/da867e918d65289ceb38f75e354b197dc08ffd29)
  已在 Adreno 7xx 及更新设备实现 Android 帧生成。可借鉴 AHardwareBuffer
  共享、Vulkan 队列所有权转移、有界队列、vsync pacing、device-lost 自动
  bypass 与真实/总 FPS 诊断。其完整应用子目录有非商业限制，不能直接复制。
- [LSFG-Android-Application](https://github.com/FrankBarretta/LSFG-Android-Application/tree/b84754199823615d32d65fe33ea59481dca88dcf)
  是 GPL-3.0 独立应用，与 ReKazumi 的 GPL-3.0 兼容。它证明了
  `ImageReader -> AHardwareBuffer -> Vulkan -> ANativeWindow` 的实机路径。
- [lsfg-vk-android](https://github.com/FrankBarretta/lsfg-vk-android/tree/3e89e5439a98f55d5acb003d20039426ab24e69c)
  的 Android AHardwareBuffer 扩展为 MIT，可作为资源共享接口参考。但 LSFG
  算法 shader 必须由用户合法持有的 `Lossless.dll` 提取，ReKazumi 不能内置、
  下载或重新分发它。因此它不是无条件可发布的默认后端。
- [HopperRender](https://github.com/HopperLogger/mpv-frame-interpolator/tree/0d586cd4a78f2905f65b82fb6ac87e2829477479)
  展示了无模型的分层块匹配、双向 warp、遮挡修正与 blend，但实现依赖桌面
  OpenCL，尚未证明能在 Android/Adreno 上达到实时速度。只能借鉴算法结构。

结论：现成且已证明能在 Android 实时运行的方案目前只有 LSFG 路线，但它依赖
用户提供专有 shader。传输、同步和呈现架构可以立即采用；最终算法后端必须在
“用户提供 Lossless.dll 的 LSFG”与“重新实现完全开源 Vulkan 光流”之间明确选择。

## ReKazumi 专用流水线

ReKazumi 自己拥有解码与播放器渲染器，不需要 LSFG-Android 的
MediaProjection、系统悬浮窗、Accessibility 或 Shizuku。目标流水线为：

```text
MediaCodec original frames (source PTS)
        -> optional Anime4K Restore at source rate
        -> two persistent original-frame GPU images
        -> Vulkan frame-generation backend (t=1/3, t=2/3)
        -> Anime4K upscale on original/generated images
        -> one final swapchain present per scheduled slot
```

硬约束：

1. 后端只接收两个原始帧，生成帧永不递归成为输入。
2. 音频/源 PTS 是主时钟；不做 23.976 -> 24，不改变播放速度。
3. 每个源区间只允许原始、1/3、2/3 三相；120 Hz 不改变倍率。
4. GPU 工作晚于截止时间时丢弃生成相，不追赶、不 burst present。
5. 每个显示时隙只提交一次最终画面；不在同一 vsync 多次 post。
6. duplicate 与 scene cut 直接 hold/bypass，不能送入帧生成。

## 资源与同步

- 持久资源上限：2 张原始输入、2 张生成输出、交换链自身图像；禁止逐帧创建纹理。
- 队列深度最多 2 个源帧对。新帧到达时丢弃过期生成任务，不阻塞解码或音频。
- 优先让 mpv `gpu-next`、Anime4K、帧生成和呈现共享一个 Vulkan device/queue，
  使用 timeline semaphore 与明确的 image layout/queue ownership barrier。
- 只有无法共享 device 时才使用 AHardwareBuffer 跨 device；该模式必须保留双方
  buffer 引用直到消费完成，并把 `waitIdle()` 当作首版正确性手段而非最终性能方案。
- 禁止 CPU readback、Bitmap 中转、每帧 JNI 大对象与 GLES/Vulkan 隐式同步。

## 故障隔离

- 启动时探测 Vulkan 版本、AHB external memory、所需格式与同步能力；不满足即
  显示“后端不可用”，保持源帧播放。
- 任意 Vulkan error、device lost、超时、非法时间戳或输出校验失败，立即对本次
  播放 session 熔断，释放生成队列并回到原始帧。
- 后端熔断不能销毁播放器、改变屏幕刷新率、重建系统显示或影响音频。
- 首次实机测试必须先离屏生成并读取小尺寸校验结果；只有离屏结果与 GPU 时间
  合格后，才允许接入 ANativeWindow 呈现。

## 必须可见的诊断

日志页持续显示：

- backend 名称与 availability/bypass/fault 状态；
- source FPS、generated FPS、present FPS；
- 生成请求、成功、deadline drop、duplicate bypass、scene-cut bypass 数量；
- GPU 分析/生成/Anime4K/present 时间与当前队列深度；
- 当前帧对 PTS、生成相位和最后一次 Vulkan 错误。

“设置选中”不是启用证据；只有 generated-present 计数增长且输出帧时间符合
`1/3`、`2/3`，才能判定插帧实际工作。

## 实施顺序

1. 保持当前 fail-closed 版本作为可恢复基线。
2. 在独立 native module 建立 backend interface、能力探测、统计与 session fuse，
   先以 no-op backend 验证生命周期。
3. 将 mpv `gpu-next` 的原始帧输出到持久 Vulkan offscreen image，完成单 device
   的 timeline semaphore 与 bounded queue，不做任何插值。
4. 接入一个后端原型，仅做离屏 `t=1/3`、`t=2/3` 结果和 GPU timing 验证。
5. 加 duplicate/cut bypass、deadline drop，再接入单次 swapchain present。
6. 最后接 Anime4K：Restore 可在源帧率前置，Upscale 在三相画面后置。
7. 通过离屏、短时呈现、长时稳定性三道门后，设置页才能把 3× 标记为可用。

## 尚需产品决定

正式帧生成算法只能二选一：

- **LSFG adapter**：最快获得已证明的 Android 效果，但用户必须自行提供合法
  `Lossless.dll`，ReKazumi 不得分发其 shader。
- **完全开源 Vulkan 光流**：无外部模型或 DLL，分发最干净，但需要自行实现和
  调优，HopperRender 只能作为算法参考，实时质量尚未验证。

在这个决定前，不应再次把任何实验算法接到手机的最终显示路径。
