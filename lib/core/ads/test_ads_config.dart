import 'package:flutter/foundation.dart';
import 'package:genrevibes_ads/genrevibes_ads.dart';
import 'package:genrevibes_ads_admob/genrevibes_ads_admob.dart';
import 'package:smart_launcher_app/core/config/app_env.dart';

class TestAdsConfig {
  TestAdsConfig._();

  static GenRevibesAdMobConfiguration? fromAppEnv() => fromValues(
    developmentMode: AppEnv.developmentMode,
    bannerAdId: AppEnv.bannerAdId,
    interstitialAdId: AppEnv.interstitialAdId,
    appOpenAdId: AppEnv.appOpenAdId,
    rewardedAdId: AppEnv.rewardedAdId,
    nativeAdId: AppEnv.nativeAdId,
  );

  static bool shouldShowDebugEntry({
    bool isDebugBuild = kDebugMode,
    bool developmentMode = AppEnv.developmentMode,
  }) => isDebugBuild && developmentMode;

  @visibleForTesting
  static GenRevibesAdMobConfiguration? fromValues({
    required bool developmentMode,
    required String bannerAdId,
    required String interstitialAdId,
    required String appOpenAdId,
    required String rewardedAdId,
    required String nativeAdId,
  }) {
    if (!developmentMode) return null;

    final hasAnyAdUnit = [
      bannerAdId,
      interstitialAdId,
      appOpenAdId,
      rewardedAdId,
      nativeAdId,
    ].any((value) => value.trim().isNotEmpty);
    if (!hasAnyAdUnit) return null;

    final units = <AdFormat, String>{
      AdFormat.banner: bannerAdId,
      AdFormat.interstitial: interstitialAdId,
      AdFormat.appOpen: appOpenAdId,
      AdFormat.rewarded: rewardedAdId,
      AdFormat.native: nativeAdId,
    };
    return GenRevibesAdMobConfiguration(
      adUnits: [
        for (final entry in units.entries)
          if (entry.value.trim().isNotEmpty)
            AdMobAdUnit(
              placement: AdPlacement(
                id: 'dev_${entry.key.name}',
                format: entry.key,
              ),
              adUnitId: entry.value.trim(),
            ),
      ],
    ).withTestAdUnits();
  }
}
