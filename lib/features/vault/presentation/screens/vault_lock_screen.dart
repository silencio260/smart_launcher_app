import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:smart_launcher_app/core/storage/mini_app_repositories.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/clock/presentation/clock_theme.dart';
import 'package:smart_launcher_app/core/widgets/mini_app_chrome.dart';
import 'package:smart_launcher_app/features/vault/presentation/screens/vault_pattern_lock.dart';
import 'package:smart_launcher_app/features/vault/presentation/screens/vault_pin_pad.dart';

/// First-run setup and subsequent unlock for the vault. Monochrome, modelled on
/// the App Lock reference (custom PIN pad + pattern + fingerprint shortcut).
///
/// Calls [onUnlocked] once the user is in; [onCancel] when they back out.
class VaultLockScreen extends StatefulWidget {
  final VaultSecurityRepository security;
  final VoidCallback onUnlocked;
  final VoidCallback onCancel;

  /// Forces the create/confirm flow even when a credential already exists
  /// (used by Settings → Change passcode). Otherwise setup only runs on first
  /// open.
  final bool forceSetup;

  /// Pre-selects PIN or Pattern in the setup flow.
  final String? initialType;

  const VaultLockScreen({
    super.key,
    required this.security,
    required this.onUnlocked,
    required this.onCancel,
    this.forceSetup = false,
    this.initialType,
  });

  @override
  State<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends State<VaultLockScreen> {
  late final bool _setup = widget.forceSetup || !widget.security.isConfigured;
  late String _type = widget.initialType ??
      (widget.security.isConfigured
          ? widget.security.type
          : VaultSecurityRepository.typePin);

  // Setup state.
  int _step = 0; // 0 = create, 1 = confirm
  String? _first; // code captured in step 0

  // Live PIN entry.
  String _pin = '';

  String? _error;

  VaultSecurityRepository get _sec => widget.security;

  // ---- PIN handlers -------------------------------------------------------

  void _onDigit(String d) {
    if (_pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == 4) {
      // Defer so the 4th dot paints before we advance/verify.
      WidgetsBinding.instance.addPostFrameCallback((_) => _submitPin());
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submitPin() {
    final code = _pin;
    setState(() => _pin = '');
    if (_setup) {
      _handleSetupCode(code);
    } else {
      _verify(code);
    }
  }

  // ---- Pattern handler ----------------------------------------------------

  void _onPattern(List<int> nodes) {
    if (nodes.length < 4) {
      _fail('Connect at least 4 dots');
      return;
    }
    final code = nodes.join('-');
    if (_setup) {
      _handleSetupCode(code);
    } else {
      _verify(code);
    }
  }

  // ---- Shared flow --------------------------------------------------------

  void _handleSetupCode(String code) {
    if (_step == 0) {
      setState(() {
        _first = code;
        _step = 1;
        _error = null;
      });
      return;
    }
    if (code != _first) {
      setState(() {
        _step = 0;
        _first = null;
        _error = _type == VaultSecurityRepository.typePin
            ? "PINs didn't match. Try again."
            : "Patterns didn't match. Try again.";
      });
      HapticFeedback.heavyImpact();
      return;
    }
    _saveAndFinish(code);
  }

  Future<void> _saveAndFinish(String code) async {
    await _sec.setCredential(_type, code);
    if (!mounted) return;
    // Only prompt for biometric on first-time setup; a passcode change keeps
    // the existing preference.
    if (!widget.forceSetup) {
      final enable = await _askBiometric();
      if (!mounted) return;
      await _sec.setBiometricEnabled(enable);
    }
    await _sec.markUnlocked();
    widget.onUnlocked();
  }

  Future<bool> _askBiometric() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Theme(
        data: clockThemeOf(context),
        child: AlertDialog(
          backgroundColor: miniAppSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Enable fingerprint?',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: const Text(
            'Use your device fingerprint or lock to open the vault faster.',
            style: TextStyle(color: miniAppMuted, height: 1.3),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text('Not now', style: TextStyle(color: miniAppMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Enable', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  void _verify(String code) {
    if (_sec.verify(code)) {
      _sec.markUnlocked();
      widget.onUnlocked();
      return;
    }
    _fail(_type == VaultSecurityRepository.typePin
        ? 'Wrong PIN'
        : 'Wrong pattern');
  }

  void _fail(String message) {
    HapticFeedback.heavyImpact();
    setState(() {
      _pin = '';
      _error = message;
    });
  }

  Future<void> _useBiometric() async {
    final ok = await LauncherService.authenticateDevice(
      title: 'Unlock Vault',
      description: 'Use your fingerprint or device lock',
    );
    if (!mounted || !ok) return;
    await _sec.markUnlocked();
    widget.onUnlocked();
  }

  // ---- UI -----------------------------------------------------------------

  String get _title {
    if (_setup) {
      final isPin = _type == VaultSecurityRepository.typePin;
      if (_step == 0) return isPin ? 'Set up a PIN' : 'Draw a pattern';
      return isPin ? 'Confirm your PIN' : 'Draw the pattern again';
    }
    return _type == VaultSecurityRepository.typePin
        ? 'Enter PIN'
        : 'Draw your pattern';
  }

  @override
  Widget build(BuildContext context) {
    final isPin = _type == VaultSecurityRepository.typePin;
    final showBiometric = !_setup && _sec.biometricEnabled;
    return Theme(
      data: clockThemeOf(context),
      child: Scaffold(
        backgroundColor: miniAppBackground,
        appBar: AppBar(
          backgroundColor: miniAppBackground,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onCancel,
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: miniAppSurface2,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.lock_outline,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: 18),
              if (_setup && _step == 1)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: _StepDots(),
                ),
              Text(
                _title,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 20,
                child: Text(
                  _error ??
                      (_setup && _step == 0 && !isPin
                          ? 'Connect at least 4 dots'
                          : ''),
                  style: TextStyle(
                    color: _error != null ? Colors.redAccent : miniAppMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_setup && _step == 0) ...[
                const SizedBox(height: 8),
                _typeChooser(),
              ],
              Expanded(
                child: Center(
                  child: isPin
                      ? VaultPinPad(
                          entered: _pin.length,
                          onDigit: _onDigit,
                          onBackspace: _onBackspace,
                          onBiometric: showBiometric ? _useBiometric : null,
                        )
                      : VaultPatternLock(onComplete: _onPattern),
                ),
              ),
              if (showBiometric && !isPin)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton.icon(
                    onPressed: _useBiometric,
                    icon: const Icon(Icons.fingerprint, color: Colors.white),
                    label: const Text('Use fingerprint',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeChooser() {
    Widget seg(String label, String type) {
      final active = _type == type;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _type = type;
            _step = 0;
            _first = null;
            _pin = '';
            _error = null;
          }),
          child: Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: miniAppSurface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          seg('PIN', VaultSecurityRepository.typePin),
          seg('Pattern', VaultSecurityRepository.typePattern),
        ],
      ),
    );
  }
}

/// The little "1 — 2" progress chips shown on the confirm step, like the
/// reference setup flow.
class _StepDots extends StatelessWidget {
  const _StepDots();

  @override
  Widget build(BuildContext context) {
    Widget chip(String n, bool done) => Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? Colors.white : miniAppSurface2,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            n,
            style: TextStyle(
              color: done ? Colors.black : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        chip('1', true),
        Container(width: 26, height: 2, color: miniAppMuted),
        chip('2', true),
      ],
    );
  }
}
