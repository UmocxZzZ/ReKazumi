enum FrameInterpolationMode {
  off(
    storageValue: 0,
    label: '关闭',
    description: '保持原始视频帧率',
  ),
  anime3x(
    storageValue: 1,
    label: '动漫 3×（暂不可用）',
    description: 'QCOM 驱动路径已因实机卡死与花屏停用，等待安全后端',
  );

  const FrameInterpolationMode({
    required this.storageValue,
    required this.label,
    required this.description,
  });

  final int storageValue;
  final String label;
  final String description;

  bool get enabled => this != FrameInterpolationMode.off;

  bool get available => switch (this) {
        FrameInterpolationMode.off => true,
        FrameInterpolationMode.anime3x => false,
      };

  static FrameInterpolationMode fromStorageValue(int value) {
    return FrameInterpolationMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => FrameInterpolationMode.off,
    );
  }
}
