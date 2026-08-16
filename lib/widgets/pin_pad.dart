import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PIN 输入组件：圆点指示 + 数字键盘（REQ-08）。
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.length,
    required this.digits,
    required this.onDigit,
    required this.onBackspace,
    this.errorText,
    this.hint,
  });

  final int length;
  final String digits;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final String? errorText;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          errorText ?? hint ?? '',
          style: TextStyle(
            fontSize: 13.5,
            color: errorText == null
                ? scheme.onSurfaceVariant
                : const Color(0xFFE57373),
            fontWeight: errorText == null ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < length; i++)
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < digits.length
                      ? scheme.primary
                      : Colors.transparent,
                  border: Border.all(
                    color: i < digits.length
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: 2,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          [null, '0', 'back'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final key in row)
                  SizedBox(
                    width: 74,
                    height: 62,
                    child: key == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _Key(
                              label: key,
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                if (key == 'back') {
                                  onBackspace();
                                } else if (digits.length < length) {
                                  onDigit(key);
                                }
                              },
                            ),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBack = label == 'back';
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 58,
          height: 58,
          child: Center(
            child: isBack
                ? Icon(
                    Icons.backspace_outlined,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
