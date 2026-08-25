import 'dart:io';

import 'package:flutter/painting.dart';

/// 原生端：路径即真实文件，直接交给 [FileImage]。
ImageProvider<Object> storedImageProvider(String path) => FileImage(
      File(path),
    );
