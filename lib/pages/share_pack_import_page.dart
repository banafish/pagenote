import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_fonts.dart';
import '../models/decoration.dart';
import '../models/journal_entry.dart';
import '../models/mood.dart';
import '../models/sticker_assets.dart';
import '../models/template.dart';
import '../providers/custom_sticker_provider.dart';
import '../providers/template_provider.dart';
import '../services/share_pack_service.dart';
import '../utils/date_utils.dart';
import '../widgets/canvas/canvas_view.dart';

/// 缩略图用的预览条目：与模板管理页同一套渲染,组件元素从它读展示数据。
final _previewEntry = JournalEntry(
  id: 'pack-preview',
  date: DateUtils2.dateKey(DateTime.now()),
  title: '',
  content: '',
  mood: Mood.calm,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

const _pagePadding = 16.0;
const _cellSpacing = 12.0;

/// 模板缩略图格子（与模板管理页一致的目标宽度与比例）。
const _templateExtent = 190.0;
const _templateRatio = 0.62;

/// 贴纸格子：小图 + 名字一行。
const _stickerExtent = 84.0;
const _stickerRatio = 0.78;

/// 分享包导入结果（REQ-21.9）：由调用方据此跳转到模板管理页 / 素材面板并高亮。
class SharePackImportResult {
  const SharePackImportResult({
    required this.templateIds,
    required this.stickerIds,
  });

  /// 本机新写入的模板 id —— installTemplates 重新分配过,不是包内的原 id。
  final List<String> templateIds;

  /// 本机新写入的自定义贴纸 id（内容 sha1）。
  final List<String> stickerIds;

  bool get isEmpty => templateIds.isEmpty && stickerIds.isEmpty;
}

/// 分享包导入预览页（REQ-21.5～21.10）。
///
/// 入参是分享包原始字节,解析放在本页内完成 —— 损坏 / 版本过高 / 超限
/// 统一收敛为可读中文提示与「取消」出口（REQ-21.10）。包内模板与贴纸
/// 逐项可勾选、默认全选,用户点「导入」才真正落库（REQ-21.5）。
///
/// 导入成功后以 [SharePackImportResult] 出栈,调用方拿到新写入的 id
/// 去跳转并高亮（REQ-21.9）。用户取消或导入失败时出栈值为 null。
class SharePackImportPage extends StatefulWidget {
  const SharePackImportPage({super.key, required this.bytes, this.sourceName});

  /// 分享包 zip 字节（系统分享、文件选择、Android intent 三个入口共用）。
  final Uint8List bytes;

  /// 来源文件名,仅用于顶部副标题,可空。
  final String? sourceName;

  @override
  State<SharePackImportPage> createState() => _SharePackImportPageState();
}

class _SharePackImportPageState extends State<SharePackImportPage> {
  SharePackData? _pack;
  String? _error;
  bool _importing = false;

  /// 勾选状态按下标记录,避免包内出现重名或重复 id 时互相干扰。
  Set<int> _templates = {};
  Set<int> _stickers = {};

  /// 同名冲突时覆盖（REQ-21.8）；默认关,即保留两者自动加后缀。
  bool _overwriteSameName = false;

  @override
  void initState() {
    super.initState();
    // 放到首帧之后,先让加载态出现,再做解压与解析。
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 解析分享包（REQ-21.10）：只认服务层抛出的可读中文错误,其余一律兜底。
  void _load() {
    try {
      final pack = SharePackService.instance.parsePack(widget.bytes);
      if (!mounted) return;
      setState(() {
        _pack = pack;
        _templates = {for (var i = 0; i < pack.templates.length; i++) i};
        // 包内没带上位图的贴纸装不进来,默认不勾选。
        _stickers = {
          for (var i = 0; i < pack.stickers.length; i++)
            if (pack.stickerBytes.containsKey(pack.stickers[i].fileName)) i,
        };
      });
    } on SharePackFormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '读取分享包失败，请确认文件完整后重试');
    }
  }

  // ---------------- 勾选 ----------------

  List<JournalTemplate> get _pickedTemplates {
    final pack = _pack;
    if (pack == null) return const [];
    return [
      for (var i = 0; i < pack.templates.length; i++)
        if (_templates.contains(i)) pack.templates[i],
    ];
  }

  List<CustomSticker> get _pickedStickers {
    final pack = _pack;
    if (pack == null) return const [];
    return [
      for (var i = 0; i < pack.stickers.length; i++)
        if (_stickers.contains(i)) pack.stickers[i],
    ];
  }

  void _toggle(Set<int> selection, int index) {
    setState(() {
      if (!selection.remove(index)) selection.add(index);
    });
  }

  void _toggleAll(Set<int> selection, Iterable<int> all) {
    setState(() {
      final target = all.toSet();
      if (selection.length == target.length) {
        selection.clear();
      } else {
        selection
          ..clear()
          ..addAll(target);
      }
    });
  }

  /// 勾选内容的引用完整性（REQ-21.7）：不阻止导入,只如实告知。
  /// 包内自带的贴纸此刻还没落库,全局索引查不到,不能算作缺失。
  MissingAssetReport get _missing {
    final report = checkMissingAssets(
      _pickedTemplates,
      hasPaper: (id) => paperById(id) != null,
      hasFont: (family) => fontByFamily(family) != null,
    );
    final provided = {for (final s in _pickedStickers) s.stickerKey};
    final keys = report.stickerKeys.where((k) => !provided.contains(k)).toSet();
    if (keys.length == report.stickerKeys.length) return report;
    return MissingAssetReport(
      stickerKeys: keys,
      paperIds: report.paperIds,
      fontFamilies: report.fontFamilies,
    );
  }

  // ---------------- 导入 ----------------

  Future<void> _import() async {
    final pack = _pack;
    if (pack == null || _importing) return;
    final templates = _pickedTemplates;
    final stickers = _pickedStickers;
    if (templates.isEmpty && stickers.isEmpty) return;

    setState(() => _importing = true);
    final messenger = ScaffoldMessenger.of(context);
    final stickerProvider = context.read<CustomStickerProvider>();
    final templateProvider = context.read<TemplateProvider>();
    final stickerIds = <String>[];
    // 尺寸超限或格式无法识别的素材会被跳过（NFR-06），如实告知用户，
    // 否则贴纸静默变少、模板里的引用却退化成缺失占位，无从追查。
    var skipped = 0;
    try {
      // 先落贴纸再装模板：贴纸落库会刷新 CustomStickerIndex,
      // 之后模板里的 `img:<sha1>` 才不会先闪一下占位框。
      for (final s in stickers) {
        final bytes = pack.stickerBytes[s.fileName];
        if (bytes == null) {
          skipped++;
          continue;
        }
        final saved = await stickerProvider.importFromBytes(
          bytes,
          name: s.name.trim().isEmpty ? '未命名素材' : s.name,
          category: s.category,
          ext: s.ext,
        );
        if (saved != null) {
          stickerIds.add(saved.id);
        } else {
          skipped++;
        }
      }
      // 新 id + originId + builtin = false 由 installTemplates 保证（REQ-21.8）。
      // photos/ 里的照片交给 attachments，模板画布内的路径按文件名重映射到本机，
      // 不传就会全部退化成占位框（FIX-01.2 / FIX-01.3）。
      final installed = await templateProvider.installTemplates(
        templates,
        attachments: pack.photoBytes,
        overwriteSameName: _overwriteSameName,
      );
      if (!mounted) return;
      if (skipped > 0) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('$skipped 张素材尺寸超限或无法识别，已跳过')),
          );
      }
      Navigator.pop(
        context,
        SharePackImportResult(
          templateIds: [for (final t in installed) t.id],
          stickerIds: stickerIds,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _importing = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('导入失败，请重试')));
    }
  }

  // ---------------- 布局 ----------------

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    final empty =
        pack != null && pack.templates.isEmpty && pack.stickers.isEmpty;
    return PopScope(
      // 落库过程中不让返回,避免写到一半退出。
      canPop: !_importing,
      child: Scaffold(
        appBar: AppBar(title: const Text('导入分享包')),
        body: _error != null
            ? _errorView(_error!)
            : pack == null
            ? _loadingView()
            : empty
            ? _emptyView()
            : _preview(pack),
        bottomNavigationBar: pack == null || empty ? null : _bottomBar(),
      ),
    );
  }

  Widget _loadingView() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2.4),
          const SizedBox(height: 16),
          Text(
            '正在读取分享包…',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 可读的中文错误 + 明确的退出口（REQ-21.10）。
  Widget _errorView(String message) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 36,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.sourceName != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.sourceName!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyView() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 36,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            const Text(
              '这个分享包是空的',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '包内没有模板也没有贴纸，没有可导入的内容。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(SharePackData pack) {
    final missing = _missing;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _header(pack)),
        if (!missing.isEmpty) SliverToBoxAdapter(child: _missingCard(missing)),
        if (pack.templates.isNotEmpty) ...[
          _sectionLabel(
            '模板',
            pack.templates.length,
            _templates.length,
            () => _toggleAll(_templates, [
              for (var i = 0; i < pack.templates.length; i++) i,
            ]),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: _templateExtent,
                mainAxisSpacing: _cellSpacing,
                crossAxisSpacing: _cellSpacing,
                childAspectRatio: _templateRatio,
              ),
              itemCount: pack.templates.length,
              itemBuilder: (context, i) => _templateCard(
                pack.templates[i],
                _templates.contains(i),
                () => _toggle(_templates, i),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
        ],
        if (pack.stickers.isNotEmpty) ...[
          _sectionLabel(
            '贴纸',
            pack.stickers.length,
            _stickers.length,
            () => _toggleAll(_stickers, [
              for (var i = 0; i < pack.stickers.length; i++)
                if (pack.stickerBytes.containsKey(pack.stickers[i].fileName)) i,
            ]),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: _stickerExtent,
                mainAxisSpacing: _cellSpacing,
                crossAxisSpacing: _cellSpacing,
                childAspectRatio: _stickerRatio,
              ),
              itemCount: pack.stickers.length,
              itemBuilder: (context, i) => _stickerCard(
                pack.stickers[i],
                pack.stickerBytes[pack.stickers[i].fileName],
                _stickers.contains(i),
                () => _toggle(_stickers, i),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  /// 包名 / 来源署名 / 数量与体积（REQ-21.6）。
  Widget _header(SharePackData pack) {
    final scheme = Theme.of(context).colorScheme;
    final author = pack.author.trim();
    final counts = [
      if (pack.templates.isNotEmpty) '${pack.templates.length} 个模板',
      if (pack.stickers.isNotEmpty) '${pack.stickers.length} 张贴纸',
      // 对方勾了「包含照片」才有，导入后会落到本机并接回模板（FIX-01.2）。
      if (pack.photoBytes.isNotEmpty) '${pack.photoBytes.length} 张照片',
      _sizeLabel(widget.bytes.lengthInBytes),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.fromLTRB(_pagePadding, 12, _pagePadding, 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 20,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pack.name.trim().isEmpty ? '未命名素材包' : pack.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  author.isEmpty ? '未署名' : '来自 $author',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  counts,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 引用完整性提示（REQ-21.7）：如实列出缺什么,但不拦导入。
  Widget _missingCard(MissingAssetReport report) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(_pagePadding, 0, _pagePadding, 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.report_gmailerrorred_rounded,
                size: 18,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${report.count} 个素材本机缺失，导入后显示为占位框',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in report.labels)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '缺失不影响导入，版式其余部分照常显示；补上对应素材后会自动恢复。',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(
    String text,
    int total,
    int picked,
    VoidCallback onToggleAll,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_pagePadding + 4, 0, 8, 6),
        child: Row(
          children: [
            Text(
              '$text（已选 $picked / $total）',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12.5),
              ),
              onPressed: onToggleAll,
              child: Text(picked >= total ? '取消全选' : '全选'),
            ),
          ],
        ),
      ),
    );
  }

  /// 模板卡片：缩略图与模板管理页同一套渲染,左上角是勾选态。
  Widget _templateCard(
    JournalTemplate template,
    bool picked,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: picked
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: picked ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _thumbnail(template)),
                  Positioned(left: 6, top: 6, child: _checkMark(picked)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
              child: Text(
                template.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(JournalTemplate template) {
    final scheme = Theme.of(context).colorScheme;
    final canvas = template.canvas;
    if (canvas == null) {
      return Container(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 24,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              '纯文本模板',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return RepaintBoundary(
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 240,
          child: AspectRatio(
            aspectRatio: 1 / canvas.effectiveHeight,
            child: CanvasView(canvas: canvas, entry: _previewEntry),
          ),
        ),
      ),
    );
  }

  /// 贴纸格子；包内漏带位图的条目不可勾选,直接说明装不进来。
  Widget _stickerCard(
    CustomSticker sticker,
    Uint8List? bytes,
    bool picked,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final usable = bytes != null;
    return Opacity(
      opacity: usable ? 1 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: picked
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.5),
            width: picked ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: usable ? onTap : null,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: usable
                          ? Padding(
                              padding: const EdgeInsets.all(8),
                              child: Image.memory(bytes, fit: BoxFit.contain),
                            )
                          : Icon(
                              Icons.image_not_supported_outlined,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                    ),
                    if (usable)
                      Positioned(left: 4, top: 4, child: _checkMark(picked)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Text(
                  usable
                      ? (sticker.name.trim().isEmpty ? '未命名' : sticker.name)
                      : '缺文件',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkMark(bool picked) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: picked ? scheme.primary : scheme.surface.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(
          color: picked ? scheme.primary : scheme.outlineVariant,
          width: 1.4,
        ),
      ),
      child: picked
          ? Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary)
          : null,
    );
  }

  /// 底部操作条：同名冲突开关（REQ-21.8）+ 取消 / 导入。
  Widget _bottomBar() {
    final scheme = Theme.of(context).colorScheme;
    final templates = _templates.length;
    final stickers = _stickers.length;
    final total = templates + stickers;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(_pagePadding, 8, _pagePadding, 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '同名时覆盖已有模板',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _overwriteSameName
                            ? '同名的我的模板会被包内版本替换'
                            : '默认保留两者，同名时自动加后缀',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _overwriteSameName,
                  onChanged: _importing || templates == 0
                      ? null
                      : (v) => setState(() => _overwriteSameName = v),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _importing ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _importing || total == 0 ? null : _import,
                    child: _importing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : Text(total == 0 ? '请至少选择一项' : '导入选中的 $total 项'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
