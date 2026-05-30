import '../models/app_info.dart';

/// Coarse app categories used to seed the default home layout (pages 2/3 and
/// the page-4 category folders). This is a best-effort classifier: a curated
/// map of well-known packages first, then prefix/keyword heuristics. Anything
/// we can't place lands in [AppCategory.other] and is left in the drawer only.
enum AppCategory {
  social,
  communication,
  google,
  utility,
  games,
  finance,
  shopping,
  photography,
  music,
  video,
  travel,
  health,
  productivity,
  news,
  tools,
  system,
  other,
}

extension AppCategoryLabel on AppCategory {
  /// Human-readable title used for the page-4 folders.
  String get label => switch (this) {
        AppCategory.social => 'Social',
        AppCategory.communication => 'Communication',
        AppCategory.google => 'Google',
        AppCategory.utility => 'Utilities',
        AppCategory.games => 'Games',
        AppCategory.finance => 'Finance',
        AppCategory.shopping => 'Shopping',
        AppCategory.photography => 'Photography',
        AppCategory.music => 'Music',
        AppCategory.video => 'Video',
        AppCategory.travel => 'Travel',
        AppCategory.health => 'Health',
        AppCategory.productivity => 'Productivity',
        AppCategory.news => 'News',
        AppCategory.tools => 'Tools',
        AppCategory.system => 'System',
        AppCategory.other => 'Other',
      };
}

/// Exact package-name → category overrides for popular apps. Checked before any
/// heuristic so well-known apps always land in the expected bucket.
const Map<String, AppCategory> _curated = {
  // Social
  'com.instagram.android': AppCategory.social,
  'com.facebook.katana': AppCategory.social,
  'com.facebook.lite': AppCategory.social,
  'com.zhiliaoapp.musically': AppCategory.social, // TikTok
  'com.ss.android.ugc.trill': AppCategory.social, // TikTok (intl)
  'com.snapchat.android': AppCategory.social,
  'com.twitter.android': AppCategory.social,
  'com.reddit.frontpage': AppCategory.social,
  'com.pinterest': AppCategory.social,
  'com.linkedin.android': AppCategory.social,
  'com.tumblr': AppCategory.social,
  'com.bsky.app': AppCategory.social, // Bluesky
  'com.mastodon.android': AppCategory.social,
  'com.vkontakte.android': AppCategory.social,
  'com.sina.weibo': AppCategory.social,

  // Communication / messaging
  'com.whatsapp': AppCategory.communication,
  'com.whatsapp.w4b': AppCategory.communication,
  'org.telegram.messenger': AppCategory.communication,
  'org.thoughtcrime.securesms': AppCategory.communication, // Signal
  'com.facebook.orca': AppCategory.communication, // Messenger
  'com.discord': AppCategory.communication,
  'jp.naver.line.android': AppCategory.communication,
  'com.viber.voip': AppCategory.communication,
  'com.skype.raider': AppCategory.communication,
  'us.zoom.videomeetings': AppCategory.communication,
  'com.microsoft.teams': AppCategory.communication,
  'com.slack': AppCategory.communication,
  'com.google.android.apps.messaging': AppCategory.communication,
  'com.android.messaging': AppCategory.communication,
  'com.google.android.dialer': AppCategory.communication,
  'com.android.dialer': AppCategory.communication,
  'com.android.contacts': AppCategory.communication,
  'com.google.android.contacts': AppCategory.communication,

  // Google suite
  'com.android.chrome': AppCategory.google,
  'com.android.vending': AppCategory.google, // Play Store
  'com.google.android.gms': AppCategory.google,

  // Finance
  'com.paypal.android.p2pmobile': AppCategory.finance,
  'com.google.android.apps.walletnfcrel': AppCategory.finance, // Google Wallet
  'com.coinbase.android': AppCategory.finance,
  'com.venmo': AppCategory.finance,
  'com.squareup.cash': AppCategory.finance, // Cash App
  'com.revolut.revolut': AppCategory.finance,

  // Shopping
  'com.amazon.mShop.android.shopping': AppCategory.shopping,
  'com.ebay.mobile': AppCategory.shopping,
  'com.einnovation.temu': AppCategory.shopping,
  'com.contextlogic.wish': AppCategory.shopping,
  'com.alibaba.aliexpresshd': AppCategory.shopping,
  'com.etsy.android': AppCategory.shopping,

  // Music
  'com.spotify.music': AppCategory.music,
  'com.soundcloud.android': AppCategory.music,
  'com.amazon.mp3': AppCategory.music,
  'deezer.android.app': AppCategory.music,
  'com.pandora.android': AppCategory.music,

  // Video / streaming
  'com.netflix.mediaclient': AppCategory.video,
  'com.disney.disneyplus': AppCategory.video,
  'com.hulu.plus': AppCategory.video,
  'com.amazon.avod.thirdpartyclient': AppCategory.video,
  'tv.twitch.android.app': AppCategory.video,

  // Travel
  'com.ubercab': AppCategory.travel,
  'com.lyft.android': AppCategory.travel,
  'com.airbnb.android': AppCategory.travel,
  'com.booking': AppCategory.travel,
  'com.tripadvisor.tripadvisor': AppCategory.travel,

  // Health
  'com.fitbit.FitbitMobile': AppCategory.health,
  'com.myfitnesspal.android': AppCategory.health,
  'com.strava': AppCategory.health,
  'com.google.android.apps.fitness': AppCategory.health,
  'com.headspace.android': AppCategory.health,

  // News
  'flipboard.app': AppCategory.news,
  'com.google.android.apps.magazines': AppCategory.news,
  'bbc.mobile.news.ww': AppCategory.news,
  'com.cnn.mobile.android.phone': AppCategory.news,

  // Utility
  'com.android.calculator2': AppCategory.utility,
  'com.google.android.calculator': AppCategory.utility,
  'com.android.deskclock': AppCategory.utility,
  'com.google.android.deskclock': AppCategory.utility,
  'com.android.documentsui': AppCategory.utility,
  'com.google.android.apps.nbu.files': AppCategory.utility, // Files by Google
  'com.android.calendar': AppCategory.utility,
  'com.google.android.calendar': AppCategory.utility,
};

/// Substring → category heuristics, checked against the lowercased package name
/// (and, as a fallback, the app title). Order matters: earlier entries win.
const List<(String, AppCategory)> _keywordRules = [
  ('camera', AppCategory.photography),
  ('gallery', AppCategory.photography),
  ('photo', AppCategory.photography),
  ('dialer', AppCategory.communication),
  ('phone', AppCategory.communication),
  ('contacts', AppCategory.communication),
  ('messag', AppCategory.communication),
  ('.mms', AppCategory.communication),
  ('.sms', AppCategory.communication),
  ('calculator', AppCategory.utility),
  ('clock', AppCategory.utility),
  ('calendar', AppCategory.utility),
  ('weather', AppCategory.utility),
  ('files', AppCategory.utility),
  ('filemanager', AppCategory.utility),
  ('recorder', AppCategory.utility),
  ('scanner', AppCategory.utility),
  ('flashlight', AppCategory.utility),
  ('bank', AppCategory.finance),
  ('wallet', AppCategory.finance),
  ('finance', AppCategory.finance),
  ('budget', AppCategory.finance),
  ('shop', AppCategory.shopping),
  ('store', AppCategory.shopping),
  ('music', AppCategory.music),
  ('audio', AppCategory.music),
  ('podcast', AppCategory.music),
  ('video', AppCategory.video),
  ('player', AppCategory.video),
  ('game', AppCategory.games),
  ('news', AppCategory.news),
  ('fit', AppCategory.health),
  ('health', AppCategory.health),
  ('workout', AppCategory.health),
  ('travel', AppCategory.travel),
  ('maps', AppCategory.travel),
  ('settings', AppCategory.system),
  ('launcher', AppCategory.system),
];

/// Best-effort category for a single package. Never returns null — unknown apps
/// fall back to [AppCategory.other].
AppCategory categorize(String packageName, {String? title}) {
  final pkg = packageName.toLowerCase();

  final exact = _curated[packageName];
  if (exact != null) return exact;

  // Anything else under the Google umbrella is treated as the Google suite.
  if (pkg.startsWith('com.google.android') || pkg.startsWith('com.google.')) {
    return AppCategory.google;
  }

  for (final (keyword, category) in _keywordRules) {
    if (pkg.contains(keyword)) return category;
  }
  if (title != null) {
    final t = title.toLowerCase();
    for (final (keyword, category) in _keywordRules) {
      if (t.contains(keyword)) return category;
    }
  }

  // Android-platform packages we couldn't otherwise place.
  if (pkg.startsWith('com.android.') || pkg.startsWith('com.samsung.android')) {
    return AppCategory.system;
  }

  return AppCategory.other;
}

/// Buckets installed apps by [categorize], preserving input order within each
/// bucket. Categories with no apps are omitted from the returned map.
Map<AppCategory, List<AppInfo>> categorizeApps(List<AppInfo> apps) {
  final result = <AppCategory, List<AppInfo>>{};
  for (final app in apps) {
    final category = categorize(app.packageName, title: app.title);
    result.putIfAbsent(category, () => <AppInfo>[]).add(app);
  }
  return result;
}
