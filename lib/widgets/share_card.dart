import 'dart:io';

import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/journal_entry.dart';
import '../utils/date_utils.dart';

/// 分享长图卡面（REQ-11）：固定浅色纸质风格，深色模式下导出同样用浅色模板。
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.entry, this.showSignature = true});

  final JournalEntry entry;

  /// 底部 app 署名（可在设置中关闭）。
  final bool showSignature;

  // 纸质暖色调（与深浅色主题无关，导出恒为浅色）。
  static const paper = Color(0xFFF9F3E8);
  static const ink = Color(0xFF4A3F35);
  static const subInk = Color(0xFF8A7B6C);
  static const accent = Color(0xFFE8734A);
  static const chipBg = Color(0xFFF0E5D4);

  @override
  Widget build(BuildContext context) {
    final images = entry.images.take(3).toList();

    return Container(
      width: 400,
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 20),
      color: paper,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：日期 + 天气 + 心情。
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateUtils2.fullDate(entry.date),
                      style: const TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (entry.mood != null || entry.weather != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (entry.mood != null)
                            '${entry.mood!.emoji} ${entry.mood!.label}',
                          if (entry.weather != null)
                            '${entry.weather!.emoji} ${entry.weather!.label}',
                        ].join('  '),
                        style: const TextStyle(color: subInk, fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(entry.mood?.emoji ?? '📔',
                    style: const TextStyle(fontSize: 17)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _Divider(),
          const SizedBox(height: 16),

          // 标题与正文。
          if (entry.title.trim().isNotEmpty) ...[
            Text(
              entry.title.trim(),
              style: const TextStyle(
                color: ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            entry.plainContent,
            style: const TextStyle(
              color: ink,
              fontSize: 14.5,
              height: 1.85,
            ),
          ),

          // 图片（最多 3 张，REQ-11.2）。
          if (images.isNotEmpty) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 150,
                child: Row(
                  children: [
                    for (var i = 0; i < images.length; i++)
                      Expanded(
                        child: Padding(
                          padding:
                              EdgeInsets.only(right: i == images.length - 1 ? 0 : 6),
                          child: _ShareImage(path: images[i]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],

          // 活动与标签。
          if (entry.activities.isNotEmpty || entry.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in entry.activities)
                  _Chip('${emojiOfActivity(a)} $a'),
                for (final t in entry.tags) _Chip('#$t'),
              ],
            ),
          ],

          const SizedBox(height: 18),
          const _Divider(),
          const SizedBox(height: 12),

          // 底部署名（REQ-11.3：可在设置中关闭）。
          Row(
            children: [
              const Spacer(),
              if (showSignature)
                const Row(
                  children: [
                    Text('📖', style: TextStyle(fontSize: 13)),
                    SizedBox(width: 4),
                    Text(
                      '拾页 PageNote',
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: const Color(0xFFE4D8C4),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ShareCard.chipBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF6B5A48),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ShareImage extends StatelessWidget {
  const _ShareImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        color: const Color(0xFFEFE4D2),
        child: const Center(
          child: Text('🖼️', style: TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}
