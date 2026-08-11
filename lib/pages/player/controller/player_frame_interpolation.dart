enum FrameInterpolationMode {
  off(
    storageValue: 0,
    label: '关闭',
    description: '保持原始视频帧率',
  ),
  anime3x(
    storageValue: 1,
    label: '动漫 3×（RIFE）',
    description: '仅生成 1/3、2/3 两张中间帧；不追帧到屏幕刷新率',
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

  static FrameInterpolationMode fromStorageValue(int value) {
    return FrameInterpolationMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => FrameInterpolationMode.off,
    );
  }
}
