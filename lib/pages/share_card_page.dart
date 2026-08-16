import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/journal_entry.dart';
import '../providers/settings_provider.dart';
import '../utils/date_utils.dart';
import '../widgets/share_card.dart';

/// 分享图预览页（REQ-11）：RepaintBoundary 渲染长图，
/// Android 保存相册 / 拉起分享；Windows 保存为文件。
class ShareCardPage extends StatefulWidget {
  const ShareCardPage({super.key, required this.entry});

  final JournalEntry entry;

  @override
  State<ShareCardPage> createState() => _ShareCardPageState();
}

class _ShareCardPageState extends State<ShareCardPage> {
  final _boundaryKey = GlobalKey();
  bool _busy = false;

  Future<ui.Image?> _render() async {
    final boundary =
        _boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;
    // 图片加载完成后再截图，避免截到空白占位。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return boundary.toImage(pixelRatio: 2.5);
  }

  Future<Uint8List?> _renderPng() async {
    final image = await _render();
    if (image == null) return null;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _renderPng();
      if (bytes == null) return;
      final name =
          '拾页-${widget.entry.date}-${DateUtils2.monthDay(widget.entry.date)}.png';

      if (Platform.isAndroid || Platform.isIOS) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          _toast('未获得相册权限');
          return;
        }
        await Gal.putImageBytes(
          bytes,
          name: name.replaceAll('.png', ''),
          album: '拾页',
        );
        _toast('已保存到相册 📁');
      } else {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: '图片', extensions: ['png']),
          ],
        );
        if (location == null) return;
        await File(location.path).writeAsBytes(bytes, flush: true);
        _toast('已保存到 ${p.basename(location.path)} 📁');
      }
    } on GalException {
      _toast('保存失败，请检查相册权限');
    } catch (_) {
      _toast('保存失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _renderPng();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(
          dir.path,
          'pagenote-share-${DateTime.now().millisecondsSinceEpoch}.png',
        ),
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: '来自拾页的手账分享'),
      );
    } catch (_) {
      _toast('分享失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showSignature = context
        .watch<SettingsProvider>()
        .shareSignatureEnabled;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
      appBar: AppBar(title: const Text('分享手账')),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: ShareCard(
                      entry: widget.entry,
                      showSignature: showSignature,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_rounded, size: 19),
                  label: Text(
                    Platform.isAndroid || Platform.isIOS ? '保存到相册' : '保存为图片',
                  ),
                ),
                const SizedBox(height: 10),
                if (Platform.isAndroid || Platform.isIOS)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.share_rounded, size: 19),
                    label: const Text('分享'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
