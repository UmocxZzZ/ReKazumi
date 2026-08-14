import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/platform/frame_generation_capability_service.dart';

final FrameGenerationOffscreenValidationService
    _sharedOffscreenValidationService =
    FrameGenerationOffscreenValidationService();

class OffscreenValidationAction extends StatefulWidget {
  const OffscreenValidationAction({
    super.key,
    this.service,
    this.diagnosticWriter,
    this.onDiagnosticPersisted,
  });

  final FrameGenerationOffscreenValidationService? service;
  final Future<bool> Function(String message)? diagnosticWriter;
  final Future<void> Function()? onDiagnosticPersisted;

  @override
  State<OffscreenValidationAction> createState() =>
      _OffscreenValidationActionState();
}

class _OffscreenValidationActionState extends State<OffscreenValidationAction> {
  late final FrameGenerationOffscreenValidationService _service;
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? _sharedOffscreenValidationService;
  }

  Future<void> _requestValidation() async {
    if (_isValidating) return;
    final wasCached = _service.hasCachedValidation;
    if (!wasCached) {
      final confirmed = await KazumiDialog.show<bool>(
        context: context,
        clickMaskDismiss: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('运行离屏 GPU 验证？'),
          content: const Text(
            '验证只会在独立进程中创建 8×8 Vulkan 测试图像，'
            '不会播放视频、不会输出到屏幕，也不会开启插帧。'
            '本次应用运行期间只执行一次。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('开始验证'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _isValidating = true);
    final validation = await _service.validate();
    final diagnostics = validation.toDiagnosticMap();
    if (!wasCached) {
      final persisted = await (widget.diagnosticWriter ?? appendDiagnosticLog)(
        'FrameGenOffscreenValidation ${jsonEncode(diagnostics)}',
      );
      if (persisted) {
        await widget.onDiagnosticPersisted?.call();
      }
    }
    if (!mounted) return;
    setState(() => _isValidating = false);

    final formattedDiagnostics = const JsonEncoder.withIndent('  ').convert(
      diagnostics,
    );
    await KazumiDialog.show<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(validation.passed ? '离屏验证通过' : '离屏验证未通过'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
          child: SingleChildScrollView(
            child: SelectableText(
              formattedDiagnostics,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: formattedDiagnostics),
              );
              if (dialogContext.mounted) {
                KazumiDialog.showToast(
                  context: dialogContext,
                  message: '验证结果已复制',
                );
              }
            },
            child: const Text('复制结果'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'offscreen_validation',
      onPressed: _isValidating ? null : _requestValidation,
      tooltip: _service.hasCachedValidation ? '查看离屏 GPU 验证结果' : '运行离屏 GPU 验证',
      child: _isValidating
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.shield_outlined),
    );
  }
}
