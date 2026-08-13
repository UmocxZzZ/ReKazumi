import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_frame_interpolation.dart';
import 'package:kazumi/services/storage/settings_keys.dart';

void main() {
  test('fixed 3x interpolation is opt-in', () {
    expect(SettingsKeys.defaultFrameInterpolationMode.defaultValue, 0);
    expect(
      FrameInterpolationMode.fromStorageValue(0),
      FrameInterpolationMode.off,
    );
    expect(
      FrameInterpolationMode.fromStorageValue(1),
      FrameInterpolationMode.anime3x,
    );
  });

  test('unknown persisted values safely disable interpolation', () {
    expect(
      FrameInterpolationMode.fromStorageValue(999),
      FrameInterpolationMode.off,
    );
  });

  test('rejected QCOM backend is unavailable while Off remains usable', () {
    expect(FrameInterpolationMode.off.available, isTrue);
    expect(FrameInterpolationMode.anime3x.enabled, isTrue);
    expect(FrameInterpolationMode.anime3x.available, isFalse);
  });
}
