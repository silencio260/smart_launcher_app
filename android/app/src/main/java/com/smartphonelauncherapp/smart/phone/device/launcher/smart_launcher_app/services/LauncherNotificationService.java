package com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app.services;

import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

public class LauncherNotificationService extends NotificationListenerService {

    public static final ConcurrentHashMap<String, Integer> badgeCounts = new ConcurrentHashMap<>();
    public static final ConcurrentHashMap<String, Set<String>> activeNotifications = new ConcurrentHashMap<>();
    public static volatile Runnable onBadgeChanged = null;

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        String pkg = sbn.getPackageName();
        activeNotifications.computeIfAbsent(pkg, k -> ConcurrentHashMap.newKeySet()).add(sbn.getKey());
        Set<String> keys = activeNotifications.get(pkg);
        badgeCounts.put(pkg, keys != null ? keys.size() : 0);
        if (onBadgeChanged != null) onBadgeChanged.run();
    }

    @Override
    public void onNotificationRemoved(StatusBarNotification sbn) {
        String pkg = sbn.getPackageName();
        Set<String> keys = activeNotifications.get(pkg);
        if (keys != null) keys.remove(sbn.getKey());
        badgeCounts.put(pkg, keys != null ? keys.size() : 0);
        if (onBadgeChanged != null) onBadgeChanged.run();
    }

    @Override
    public void onListenerConnected() {
        activeNotifications.clear();
        badgeCounts.clear();
        try {
            StatusBarNotification[] active = getActiveNotifications();
            if (active != null) {
                for (StatusBarNotification sbn : active) {
                    onNotificationPosted(sbn);
                }
            }
        } catch (Exception ignored) {}
    }
}
