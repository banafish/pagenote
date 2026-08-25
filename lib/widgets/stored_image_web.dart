import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../storage/stored_files.dart';

/// Web 端图片源：数据库里存的「路径」是 IndexedDB 键，
/// 渲染时经存储层异步取字节再解码。缓存键即路径本身，
/// 同一路径多处置用只解码一次。
class BlobImageProvider extends ImageProvider<BlobImageProvider> {
  BlobImageProvider(this.path);

  final String path;

  @override
  Future<BlobImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<BlobImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    BlobImageProvider key,
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
      other is BlobImageProvider && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() =>
      '${objectRuntimeType(this, 'BlobImageProvider')}("$path")';
}

/// 与 IO 端同名同签名的入口，见 stored_image_io.dart。
ImageProvider<Object> storedImageProvider(String path) =>
    BlobImageProvider(path);
