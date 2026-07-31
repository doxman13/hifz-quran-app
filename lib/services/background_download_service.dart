import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'translation_downloader.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const String notificationChannelId = 'translation_download_channel';
const String notificationChannelName = 'Translation Downloads';

Future<void> initializeDownloadService() async {
  try {
    final service = FlutterBackgroundService();

    // Initialize notifications for foreground service and completion notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Create the Android Notification Channel explicitly to prevent startForeground crashes
    final androidNotificationPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidNotificationPlugin != null) {
      await androidNotificationPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          notificationChannelId,
          notificationChannelName,
          description: 'Notifications for translation download status',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
        ),
      );
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, // Start only when a download is requested
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Translation Download',
        initialNotificationContent: 'Preparing download...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  } catch (e) {
    debugPrint('Error initializing background download service: $e');
  }
}

Future<bool> requestNotificationPermission() async {
  try {
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }
    
    final iosPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
  } catch (e) {
    debugPrint('Error requesting notification permission: $e');
  }
  return false;
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('start_download').listen((event) async {
    final id = event?['id'] as int?;
    final name = event?['name'] as String?;
    final author = event?['author'] as String?;
    final language = event?['language'] as String?;

    if (id == null || name == null || author == null || language == null) {
      service.invoke('download_failed', {'id': id, 'error': 'Invalid parameters'});
      service.stopSelf();
      return;
    }

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Downloading translation',
        content: '$name: 0%',
      );
    }

    final success = await TranslationDownloader.downloadTranslation(
      id,
      name,
      author,
      language,
      onProgress: (progress) {
        final percent = (progress * 100).toStringAsFixed(0);
        
        // Update notification
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'Downloading translation',
            content: '$name: $percent%',
          );
        }

        // Send progress back to app UI
        service.invoke('update_progress', {
          'id': id,
          'progress': progress,
        });
      },
    );

    if (success) {
      // Show local notification for completion
      await _showCompletionNotification(id, 'Download complete', name);
      service.invoke('download_success', {'id': id});
    } else {
      await _showCompletionNotification(id, 'Download failed', 'Failed to download $name');
      service.invoke('download_failed', {'id': id});
    }

    // Stop background service once task is complete
    service.stopSelf();
  });
}

Future<void> _showCompletionNotification(int id, String title, String body) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    notificationChannelId,
    notificationChannelName,
    channelDescription: 'Notifications for translation download status',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
  );
  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );
  await flutterLocalNotificationsPlugin.show(
    id,
    title,
    body,
    platformChannelSpecifics,
  );
}
