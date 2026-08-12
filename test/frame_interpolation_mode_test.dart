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

  test('fixed 3x presentation clock follows source FPS, not display Hz', () {
    expect(fixed3xPresentationFps(24000 / 1001), closeTo(72000 / 1001, 1e-9));
    expect(fixed3xPresentationFps(24), 72);
    expect(fixed3xPresentationFps(double.nan), isNull);
    expect(fixed3xPresentationFps(60), isNull);
  });
}
