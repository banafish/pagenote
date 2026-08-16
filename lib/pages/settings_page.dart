import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/journal_provider.dart';
import '../providers/settings_provider.dart';

/// 设置页：外观、数据与关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final journal = context.watch<JournalProvider>();
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;

    final content = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _pageTitle(context),
        const SizedBox(height: 14),
        _sectionTitle(context, '外观'),
        const SizedBox(height: 10),
        _SettingsCard(
          children: [
            _SettingsLabel('主题模式'),
            const SizedBox(height: 10),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined, size: 19),
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined, size: 19),
                  label: Text('跟随系统'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined, size: 19),
                  label: Text('深色'),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (modes) => settings.setThemeMode(modes.first),
            ),
            const Divider(height: 32),
            _SettingsLabel('强调色'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (var i = 0; i < seedColorOptions.length; i++)
                  _SeedSwatch(
                    option: seedColorOptions[i],
                    selected: i == settings.seedIndexCache,
                    onTap: () => settings.setSeedIndex(i),
                  ),
              ],
            ),
            const Divider(height: 32),
            _SettingsLabel('正文字号'),
            Row(
              children: [
                const Text('小', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: settings.fontScale,
                    min: 0.85,
                    max: 1.3,
                    divisions: 9,
                    label: '${(settings.fontScale * 100).round()}%',
                    onChanged: (v) => settings.setFontScale(v),
                  ),
                ),
                const Text('大', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 12),
                Text(
                  '${(settings.fontScale * 100).round()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 26),
        _sectionTitle(context, '数据'),
        const SizedBox(height: 10),
        _SettingsCard(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.auto_stories_rounded,
                    size: 20, color: scheme.onPrimaryContainer),
              ),
              title: const Text('手账篇数',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: Text(
                '${journal.totalCount} 篇',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13.5,
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.sell_rounded,
                    size: 20, color: scheme.onSecondaryContainer),
              ),
              title: const Text('标签个数',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: Text(
                '${journal.allTags.length} 个',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _sectionTitle(context, '关于'),
        const SizedBox(height: 10),
        _SettingsCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.primary,
                          scheme.tertiary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child:
                        const Icon(Icons.auto_stories, color: Colors.white, size: 27),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '拾页',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'PageNote',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'v1.0.0 · 拾起生活中的每一页',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );

    return width < 900
        ? content
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: content,
            ),
          );
  }

  Widget _pageTitle(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: top + 8, left: 4),
      child: Text(
        '设置',
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 5,
          height: 18,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SeedColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: option.name,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: option.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 21)
              : null,
        ),
      ),
    );
  }
}
