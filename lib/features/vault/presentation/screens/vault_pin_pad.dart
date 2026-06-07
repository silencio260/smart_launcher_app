import 'package:flutter/material.dart';

import '../mini_app_chrome.dart';

/// Monochrome PIN entry: a row of dots showing progress over a 3x4 numeric
/// keypad. Dumb/stateless — the parent owns the entered string and decides what
/// happens when it fills. Styled after the App Lock reference but in black &
/// white to match the alarm theme.
class VaultPinPad extends StatelessWidget {
  /// How many digits have been entered (fills that many dots).
  final int entered;

  /// Total PIN length (number of dots).
  final int length;

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  /// When non-null, a fingerprint key appears bottom-left.
  final VoidCallback? onBiometric;

  const VaultPinPad({
    super.key,
    required this.entered,
    required this.onDigit,
    required this.onBackspace,
    this.length = 4,
    this.onBiometric,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dots(),
        const SizedBox(height: 44),
        _row(['1', '2', '3']),
        const SizedBox(height: 18),
        _row(['4', '5', '6']),
        const SizedBox(height: 18),
        _row(['7', '8', '9']),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _slot(
              onBiometric == null
                  ? const SizedBox(width: 76, height: 76)
                  : _IconKey(
                      icon: Icons.fingerprint,
                      onTap: onBiometric!,
                    ),
            ),
            _slot(_DigitKey(digit: '0', onTap: () => onDigit('0'))),
            _slot(
              _IconKey(
                icon: Icons.backspace_outlined,
                onTap: onBackspace,
                filled: false,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 11),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < entered ? Colors.white : Colors.transparent,
              border: Border.all(
                color: i < entered ? Colors.white : miniAppMuted,
                width: 1.6,
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(List<String> digits) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final d in digits)
            _slot(_DigitKey(digit: d, onTap: () => onDigit(d))),
        ],
      );

  Widget _slot(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: child);
}

class _DigitKey extends StatelessWidget {
  final String digit;
  final VoidCallback onTap;

  const _DigitKey({required this.digit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: miniAppSurface2,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 76,
          height: 76,
          child: Center(
            child: Text(
              digit,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconKey extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  const _IconKey({required this.icon, required this.onTap, this.filled = true});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? miniAppSurface2 : Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 76,
          height: 76,
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}
