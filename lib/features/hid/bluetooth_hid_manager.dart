import 'package:flutter/services.dart';

class BluetoothHidManager {
  static const MethodChannel _channel = MethodChannel('com.example.andpad/hid');

  static const int stateDisconnected = 0;
  static const int stateConnecting = 1;
  static const int stateConnected = 2;
  static const int stateDisconnecting = 3;

  Function(bool)? onBluetoothStateChanged;
  Function(bool)? onAppStatusChanged;
  Function(int state, String name, String address)? onConnectionStateChanged;
  Function(String action, String detail)? onHidDebugEvent;

  BluetoothHidManager() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onBluetoothStateChanged':
        onBluetoothStateChanged?.call(call.arguments as bool);
        break;
      case 'onAppStatusChanged':
        onAppStatusChanged?.call(call.arguments as bool);
        break;
      case 'onConnectionStateChanged':
        final Map<dynamic, dynamic> args =
            call.arguments as Map<dynamic, dynamic>;
        onConnectionStateChanged?.call(
          args['state'] as int,
          args['deviceName'] as String,
          args['deviceAddress'] as String,
        );
        break;
      case 'onHidDebugEvent':
        final Map<dynamic, dynamic> args =
            call.arguments as Map<dynamic, dynamic>;
        onHidDebugEvent?.call(
          args['action'].toString(),
          args['detail'].toString(),
        );
        break;
    }
  }

  Future<bool> isBluetoothSupported() {
    return _invokeBool('isBluetoothSupported');
  }

  Future<bool> isHidSupported() {
    return _invokeBool('isHidSupported');
  }

  Future<bool> isBluetoothEnabled() {
    return _invokeBool('isBluetoothEnabled');
  }

  Future<bool> checkPermissions() {
    return _invokeBool('checkPermissions');
  }

  Future<bool> requestPermissions() {
    return _invokeBool('requestPermissions');
  }

  Future<bool> makeDiscoverable() {
    return _invokeBool('makeDiscoverable');
  }

  Future<bool> openBluetoothSettings() {
    return _invokeBool('openBluetoothSettings');
  }

  Future<List<Map<String, String>>> getPairedDevices() async {
    try {
      final List<dynamic>? devices = await _channel.invokeMethod<List<dynamic>>(
        'getPairedDevices',
      );
      if (devices == null) return [];
      return devices.map((d) {
        final map = d as Map<dynamic, dynamic>;
        return {
          'name': map['name'].toString(),
          'address': map['address'].toString(),
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> connectDevice(String address) async {
    try {
      return await _channel.invokeMethod<bool>('connectDevice', {
            'address': address,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> disconnectDevice() {
    return _invokeBool('disconnectDevice');
  }

  Future<bool> sendMouseEvent({
    int buttons = 0,
    int dx = 0,
    int dy = 0,
    int wheel = 0,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('sendMouseEvent', {
            'buttons': buttons,
            'dx': dx,
            'dy': dy,
            'wheel': wheel,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendKeyboardEvent({
    int modifiers = 0,
    List<int> keyCodes = const [],
  }) async {
    try {
      return await _channel.invokeMethod<bool>('sendKeyboardEvent', {
            'modifiers': modifiers,
            'keyCodes': keyCodes,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<int> getConnectionState() async {
    try {
      return await _channel.invokeMethod<int>('getConnectionState') ??
          stateDisconnected;
    } catch (_) {
      return stateDisconnected;
    }
  }

  Future<bool> registerApp() {
    return _invokeBool('registerApp');
  }

  Future<bool> resetHidProfile() {
    return _invokeBool('resetHidProfile');
  }

  Future<bool> unregisterApp() {
    return _invokeBool('unregisterApp');
  }

  Future<bool> _invokeBool(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } catch (_) {
      return false;
    }
  }
}
