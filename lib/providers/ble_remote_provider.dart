import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BleConnectionState { disconnected, scanning, connecting, connected }

class BleRemoteProvider extends ChangeNotifier {
  static const String _bleDevicePrefKey = 'ble_remote_device_id';

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectedDevice;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  final List<StreamSubscription<List<int>>> _notificationSubscriptions = [];

  int _clickCount = 0;
  int? _lastMode;
  final Map<int, int> _lastCounts = {};
  List<int>? _lastNotificationValue;
  DateTime? _lastNotificationTime;
  DateTime? _lastClickTime;

  BleConnectionState get connectionState => _connectionState;
  List<ScanResult> get scanResults => _scanResults;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  int get clickCount => _clickCount;

  BleRemoteProvider() {
    _autoConnect();
  }

  Future<void> _autoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(_bleDevicePrefKey);
    if (deviceId != null) {
      final device = BluetoothDevice.fromId(deviceId);
      await connectToDevice(device);
    }
  }

  Future<void> startScan() async {
    if (_connectionState == BleConnectionState.scanning) return;

    // Ensure Bluetooth is turned on at the system level
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      try {
        // Prompt user to enable Bluetooth
        await FlutterBluePlus.turnOn();
      } catch (e) {
        // This can happen if the user denies the request to turn on Bluetooth
        debugPrint('Error turning on Bluetooth: $e');
        return;
      }
    }

    _connectionState = BleConnectionState.scanning;
    _scanResults = [];
    notifyListeners();

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
      );

      FlutterBluePlus.scanResults.listen((results) {
        _scanResults = results;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Error starting BLE scan: $e');
    } finally {
      await Future.delayed(const Duration(seconds: 8));
      if (_connectionState == BleConnectionState.scanning) {
        stopScan();
      }
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    if (_connectionState == BleConnectionState.scanning) {
      _connectionState = BleConnectionState.disconnected;
      notifyListeners();
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_connectedDevice != null) {
      await disconnect();
    }

    _connectionState = BleConnectionState.connecting;
    notifyListeners();

    try {
      await device.connect(autoConnect: false);
      _connectionSubscription = device.connectionState.listen((state) async {
        if (state == BluetoothConnectionState.connected) {
          _connectedDevice = device;
          _connectionState = BleConnectionState.connected;
          await _discoverServicesAndListen(device);
          await _saveDevice(device.remoteId.toString());
        } else if (state == BluetoothConnectionState.disconnected) {
          await disconnect();
        }
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      _connectionState = BleConnectionState.disconnected;
      notifyListeners();
    }
  }

  Future<void> _discoverServicesAndListen(BluetoothDevice device) async {
    try {
      for (var sub in _notificationSubscriptions) {
        await sub.cancel();
      }
      _notificationSubscriptions.clear();

      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        for (var c in s.characteristics) {
          if (c.properties.notify || c.properties.indicate) {
            try {
              await c.setNotifyValue(true);
              final subscription = c.lastValueStream.listen((value) {
                _handleNotification(value);
              });
              _notificationSubscriptions.add(subscription);
              debugPrint('Subscribed to characteristic: ${c.uuid}');
            } catch (e) {
              debugPrint('Error subscribing to ${c.uuid}: $e');
            }
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error discovering services or listening to characteristics: $e');
    }
  }

  bool _canCountClick() {
    if (_lastClickTime == null) return true;
    return DateTime.now().difference(_lastClickTime!).inMilliseconds >= 150;
  }

  void _handleNotification(List<int> value) {
    final now = DateTime.now();
    if (_lastNotificationTime != null &&
        now.difference(_lastNotificationTime!).inMilliseconds < 100 &&
        _listEquals(_lastNotificationValue, value)) {
      debugPrint('Ignoring duplicate BLE notification: $value');
      return;
    }
    _lastNotificationTime = now;
    _lastNotificationValue = List<int>.from(value);

    debugPrint('Received BLE notification: $value');

    if (value.isEmpty) return;

    if (value.first == 0x06) {
      if (value.length <= 4) {
        if (value.length > 1) {
          final mode = value[1];
          if (mode != _lastMode) {
            _lastMode = mode;
            _lastCounts[mode] = 0;
            debugPrint('BEIQI-S7 mode sync: $mode');
          }
        }
        return;
      }

      final mode = value[1];
      final count = value[4];

      if (mode != _lastMode) {
        _lastMode = mode;
        _lastCounts[mode] = count;
        debugPrint('BEIQI-S7 mode changed to $mode, baseline count set to $count.');
        return;
      }

      if (count == 0x00) {
        _lastCounts[mode] = 0;
        debugPrint('BEIQI-S7 counter reset to 0 for mode $mode.');
        return;
      }

      if (count > (_lastCounts[mode] ?? 0)) {
        if (!_canCountClick()) {
          debugPrint('BEIQI-S7 click ignored (cooldown). Mode: $mode, Count: $count.');
          return;
        }
        _lastCounts[mode] = count;
        _clickCount++;
        _lastClickTime = now;
        notifyListeners();
        debugPrint('BEIQI-S7 click counted. Mode: $mode, Count: $count.');
      }
      return;
    }

    if (!_canCountClick()) {
      debugPrint('Fallback click ignored (cooldown).');
      return;
    }
    _triggerClick();
    _lastClickTime = now;
  }

  bool _listEquals(List<int>? a, List<int> b) {
    if (a == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _triggerClick() {
    _clickCount++;
    notifyListeners();
  }

  Future<void> disconnect() async {
    for (var sub in _notificationSubscriptions) {
      await sub.cancel();
    }
    _notificationSubscriptions.clear();

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (e) {
        debugPrint('Error during disconnect: $e');
      }
    }

    _connectedDevice = null;
    _connectionState = BleConnectionState.disconnected;
    _lastMode = null;
    _lastCounts.clear();
    _lastNotificationValue = null;
    _lastNotificationTime = null;
    _lastClickTime = null;
    await _clearSavedDevice();
    notifyListeners();
  }

  Future<void> _saveDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bleDevicePrefKey, deviceId);
  }

  Future<void> _clearSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bleDevicePrefKey);
  }

  @override
  void dispose() {
    stopScan();
    for (var sub in _notificationSubscriptions) {
      sub.cancel();
    }
    _connectionSubscription?.cancel();
    if (_connectedDevice != null) {
      _connectedDevice!.disconnect();
    }
    super.dispose();
  }
}