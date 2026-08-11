import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/pages/player/controller/player_frame_interpolation.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/services/player/rife_model_service.dart';
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
  bool preparingRife = false;

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
    if (preparingRife || mode == frameInterpolationMode) return;
    if (!mode.enabled) {
      await GStorage.putSetting<int>(
        SettingsKeys.defaultFrameInterpolationMode,
        mode.storageValue,
      );
      if (mounted) setState(() => frameInterpolationMode = mode);
      return;
    }

    if (!RifeModelService.instance.isSupported) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RIFE 3× 当前仅支持 Android arm64 设备')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('启用动漫 3× 插帧？'),
            content: const Text(
              '首次启用会下载约 11 MB 的 RIFE 4.25-lite 模型。'
              '该模式面向 Quest 3、Snapdragon 8 Gen 2 及更高性能设备。\n\n'
              '23.976 fps 会保持原始时间轴并输出 71.928 fps；'
              '不会同步到 72 或 120 fps。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('下载并启用'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => preparingRife = true);
    try {
      await RifeModelService.instance.ensureModel();
      await GStorage.putSetting<int>(
        SettingsKeys.defaultFrameInterpolationMode,
        mode.storageValue,
      );
      if (!mounted) return;
      setState(() => frameInterpolationMode = mode);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RIFE 模型准备完成，将从下次播放开始启用')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('RIFE 模型准备失败：$error')),
      );
    } finally {
      if (mounted) setState(() => preparingRife = false);
    }
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
            title: Text(
              preparingRife ? '正在下载并校验 RIFE 模型…' : '固定 3× 动漫插帧',
            ),
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
