/// External support destinations used by the Settings "Support" section
/// (Help & Feedback, Privacy Policy).
///
/// TODO(genrevibes-starter-kit): these are placeholders. The real values
/// (support inbox, hosted privacy policy) will be supplied by the shared
/// genrevibes_starter_kit package — replace these constants when that wiring
/// lands. Until then the menu items still resolve, they just point at the
/// placeholders below.
class SupportLinks {
  const SupportLinks._();

  /// Address the "I still need to give feedback" item composes a mail to.
  // TODO(genrevibes-starter-kit): set the real support inbox.
  static const String feedbackEmail = 'support@genrevibes.com';

  /// Subject pre-filled on the feedback email.
  static const String feedbackSubject = 'Smart Launcher feedback';

  /// Hosted privacy policy opened by the "Privacy Policy" item.
  // TODO(genrevibes-starter-kit): set the real privacy policy URL.
  static const String privacyPolicyUrl = 'https://genrevibes.com/privacy';
}
