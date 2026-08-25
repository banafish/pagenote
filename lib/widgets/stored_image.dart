/// 存储层图片的统一渲染入口。
///
/// 传入的「路径」在原生端有两种形态——历史附件的绝对文件路径，
/// 以及存储层相对逻辑键（如 `stickers/<sha1>.png`）；Web 端一律是
/// IndexedDB 键。本文件不再按平台拆分实现：无论哪端都经 [storedFiles]
/// 异步取字节后解码，绝对路径与相对键的解析差异由存储层内部消化
/// （原生端 FileImage 无法同步解析相对键到文档目录，这正是三端
/// 统一走存储层的原因）。所有渲染点一律写
/// `Image(image: storedImageProvider(path))`，不得直接使用 Image.file。
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../storage/stored_files.dart';

/// 经存储层取字节的图片源。缓存键即路径本身，
/// 同一路径多处置用只解码一次。
class StoredImageProvider extends ImageProvider<StoredImageProvider> {
  StoredImageProvider(this.path);

  final String path;

  @override
  Future<StoredImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<StoredImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    StoredImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key.path, decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _load(String path, ImageDecoderCallback decode) async {
    final bytes = await storedFiles.read(path);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('存储层中找不到图片:$path');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is StoredImageProvider && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() =>
      '${objectRuntimeType(this, 'StoredImageProvider')}("$path")';
}

/// 渲染入口：所有调用点统一经这里构造图片提供器。
ImageProvider<Object> storedImageProvider(String path) =>
    StoredImageProvider(path);
