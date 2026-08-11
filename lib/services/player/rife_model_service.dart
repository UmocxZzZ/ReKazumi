import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class RifeModelService {
  RifeModelService._();

  static final RifeModelService instance = RifeModelService._();

  static const String _assetBase = 'assets/models/rife-v4.25-lite';
  static const Map<String, String> _modelHashes = {
    'flownet.param':
        'f750ec6723f05a800c8fb07ac0bf3537e741b6ff7fe61b3894e407bd10373a63',
    'flownet.bin':
        '350a15e464bea5ad378e06c0fb43996e90a0d35653d5a6ef6bc980d832538fb7',
  };

  Future<String>? _preparing;

  bool get isSupported =>
      Platform.isAndroid && Abi.current() == Abi.androidArm64;

  Future<String> ensureModel() {
    final active = _preparing;
    if (active != null) return active;

    final future = _ensureModel();
    _preparing = future;
    return future.whenComplete(() {
      if (identical(_preparing, future)) _preparing = null;
    });
  }

  Future<String> _ensureModel() async {
    if (!isSupported) {
      throw UnsupportedError('RIFE 3x 当前仅支持 Android arm64 设备');
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final modelDirectory = Directory(
      path.join(supportDirectory.path, 'models', 'rife-v4.25-lite'),
    );
    await modelDirectory.create(recursive: true);

    for (final entry in _modelHashes.entries) {
      final destination = File(path.join(modelDirectory.path, entry.key));
      if (await _hasExpectedHash(destination, entry.value)) continue;

      final partial = File('${destination.path}.part');
      if (await partial.exists()) await partial.delete();

      await _copyBundledModel(entry.key, partial, entry.value);
      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
    }

    return modelDirectory.path;
  }

  Future<void> _copyBundledModel(
    String name,
    File destination,
    String expectedHash,
  ) async {
    final ByteData data;
    try {
      data = await rootBundle.load('$_assetBase/$name');
    } on FlutterError catch (error) {
      throw StateError('内置 RIFE 模型缺失：$name ($error)');
    }

    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await destination.writeAsBytes(bytes, flush: true);
    if (!await _hasExpectedHash(destination, expectedHash)) {
      await destination.delete();
      throw StateError('内置 RIFE 模型完整性校验失败：$name');
    }
  }

  Future<bool> _hasExpectedHash(File file, String expected) async {
    if (!await file.exists()) return false;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == expected;
  }
}
