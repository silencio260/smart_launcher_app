import 'package:flutter/material.dart';

import 'package:smart_launcher_app/features/onboarding/presentation/widgets/mini_app_intro_scaffold.dart';

/// One-time intro shown the first time the File Locker (vault) is opened, before
/// its lock / setup screen.
class FileLockerOnboarding extends StatelessWidget {
  const FileLockerOnboarding({
    super.key,
    required this.onContinue,
    this.onBack,
  });

  final VoidCallback onContinue;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return MiniAppCarouselScaffold(
      featureId: 'file_locker',
      accent: const Color(0xFF44D7C4),
      title: 'File Locker',
      slides: const [
        MiniAppIntroSlide(
          icon: Icons.upload_file_outlined,
          title: 'Move files into a vault',
          body: 'Import photos, videos, and documents you want kept private.',
          assetPath: 'assets/onboarding/file_locker_import_files.webp',
        ),
        MiniAppIntroSlide(
          icon: Icons.folder_special_outlined,
          title: 'Organize private folders',
          body: 'Keep locked folders grouped and hidden from normal browsing.',
          assetPath: 'assets/onboarding/file_locker_private_folders.webp',
        ),
        MiniAppIntroSlide(
          icon: Icons.enhanced_encryption_outlined,
          title: 'Unlock securely',
          body: 'Use a passcode and fingerprint before private files appear.',
          assetPath: 'assets/onboarding/file_locker_secure_unlock.webp',
        ),
      ],
      ctaLabel: 'Set up File Locker',
      onContinue: onContinue,
      onBack: onBack,
    );
  }
}
