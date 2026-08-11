import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/pages/player/controller/player_frame_interpolation.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/services/storage/storage.dart';

class SuperResolutionSettings extends StatefulWidget {
  const SuperResolutionSettings({super.key});

  @override
  State<SuperResolutionSettings> createState() =>
      _SuperResolutionSettingsState();
}

class _SuperResolutionSettingsState extends State<SuperResolutionSettings> {
  late bool disableWarning;
  late SuperResolutionMode superResolutionMode;
  late FrameInterpolationMode frameInterpolationMode;

  @override
  void initState() {
    super.initState();
    disableWarning = GStorage.getSetting<bool>(
      SettingsKeys.disableSuperResolutionWarning,
    );
    superResolutionMode = SuperResolutionMode.fromStorageValue(
      GStorage.getSetting<int>(SettingsKeys.defaultSuperResolutionMode),
    );
    frameInterpolationMode = FrameInterpolationMode.fromStorageValue(
      GStorage.getSetting<int>(SettingsKeys.defaultFrameInterpolationMode),
    );
  }

  Future<void> _changeFrameInterpolation(
    FrameInterpolationMode mode,
  ) async {
    if (mode == frameInterpolationMode) return;
    if (!mode.enabled) {
      await GStorage.putSetting<int>(
        SettingsKeys.defaultFrameInterpolationMode,
        mode.storageValue,
      );
      if (mounted) setState(() => frameInterpolationMode = mode);
      return;
    }

    if (!Platform.isAndroid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adreno AFME 帧生成仅支持兼容的 Android 设备')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('启用动漫 3× 插帧？'),
            content: const Text(
              '该模式使用 Snapdragon GPU 内置的 Adreno Frame Motion Engine，'
              '不下载模型，也不会执行 RIFE 神经网络。\n\n'
              '23.976 fps 会保持原始时间轴并生成 71.928 fps 的三相画面；'
              '120 Hz 屏幕只负责重复呈现，不会生成更多中间帧。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('启用'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    await GStorage.putSetting<int>(
      SettingsKeys.defaultFrameInterpolationMode,
      mode.storageValue,
    );
    if (mounted) setState(() => frameInterpolationMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(
        title: Text('动漫画质增强'),
      ),
      body: SettingsList(
        sections: [
          SettingsRadioSection<SuperResolutionMode>(
            title: const Text(
              'Anime4K 超分辨率需要使用 gpu 或 gpu-next 视频渲染器',
            ),
            groupValue: superResolutionMode,
            onChanged: (SuperResolutionMode? value) {
              if (value == null) return;
              GStorage.putSetting<int>(
                SettingsKeys.defaultSuperResolutionMode,
                value.storageValue,
              );
              setState(() {
                superResolutionMode = value;
              });
            },
            tiles: [
              for (final mode in SuperResolutionMode.values)
                SettingsTile<SuperResolutionMode>.radioTile(
                  title: Text(mode.label),
                  description: Text(mode.description),
                  radioValue: mode,
                ),
            ],
          ),
          SettingsRadioSection<FrameInterpolationMode>(
            title: const Text('固定 3× 硬件帧生成'),
            groupValue: frameInterpolationMode,
            onChanged: (value) {
              if (value != null) _changeFrameInterpolation(value);
            },
            tiles: [
              for (final mode in FrameInterpolationMode.values)
                SettingsTile<FrameInterpolationMode>.radioTile(
                  title: Text(mode.label),
                  description: Text(mode.description),
                  radioValue: mode,
                ),
            ],
          ),
          SettingsSection(
            title: Text('默认行为'),
            tiles: [
              SettingsTile.switchTile(
                leading: Icons.notifications_off_rounded,
                title: Text('关闭提示'),
                description: Text('关闭每次启用超分辨率时的提示'),
                initialValue: disableWarning,
                onToggle: (value) async {
                  disableWarning = value ?? !disableWarning;
                  await GStorage.putSetting<bool>(
                    SettingsKeys.disableSuperResolutionWarning,
                    disableWarning,
                  );
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
