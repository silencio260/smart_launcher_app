import 'package:flutter/foundation.dart';
import 'package:genrevibes_starter_kit/starter_kit.dart';
import 'package:smart_launcher_app/core/config/app_env.dart';

class TestAdsConfig {
  TestAdsConfig._();

  static AdsConfig? fromAppEnv() => fromValues(
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
  }) =>
      isDebugBuild && developmentMode;

  @visibleForTesting
  static AdsConfig? fromValues({
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

    return AdsConfig(
      bannerAdUnitId: _emptyToNull(bannerAdId),
      interstitialAdUnitId: _emptyToNull(interstitialAdId),
      appOpenAdUnitId: _emptyToNull(appOpenAdId),
      rewardedAdUnitId: _emptyToNull(rewardedAdId),
      nativeAdUnitId: _emptyToNull(nativeAdId),
      minInterstitialInterval: 0,
      minRewardedInterval: 0,
      minNativeInterval: 0,
      minAppOpenInterval: 0,
      minBannerInterval: 0,
      shouldShowAppOpenAd: true,
      timeBeforeFirstInstaAd: 0,
      timeBeforeFirstRewardedAd: 0,
    );
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
