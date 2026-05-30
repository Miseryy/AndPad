import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HapticFeedbackType { light, medium, heavy, selection }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Start in portrait until the saved orientation setting is loaded.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Make status bar transparent
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AndPad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFCC),
          secondary: Color(0xFFE94057),
          tertiary: Color(0xFF8A2387),
          background: Color(0xFF0F0E17),
          surface: Color(0xFF1F1D2B),
        ),
        useMaterial3: true,
      ),
      home: const TouchpadScreen(),
    );
  }
}

// Native Platform Channel Manager
class BluetoothHidManager {
  static const MethodChannel _channel = MethodChannel('com.example.andpad/hid');

  // Connection states
  static const int stateDisconnected = 0;
  static const int stateConnecting = 1;
  static const int stateConnected = 2;
  static const int stateDisconnecting = 3;

  // Callbacks
  Function(bool)? onBluetoothStateChanged;
  Function(bool)? onAppStatusChanged;
  Function(int state, String name, String address)? onConnectionStateChanged;

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
    }
  }

  Future<bool> isBluetoothSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isBluetoothSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isHidSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isHidSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isBluetoothEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isBluetoothEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkPermissions() async {
    try {
      return await _channel.invokeMethod<bool>('checkPermissions') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermissions') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> makeDiscoverable() async {
    try {
      return await _channel.invokeMethod<bool>('makeDiscoverable') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openBluetoothSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openBluetoothSettings') ??
          false;
    } catch (_) {
      return false;
    }
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

  Future<bool> disconnectDevice() async {
    try {
      return await _channel.invokeMethod<bool>('disconnectDevice') ?? false;
    } catch (_) {
      return false;
    }
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

  Future<int> getConnectionState() async {
    try {
      return await _channel.invokeMethod<int>('getConnectionState') ??
          stateDisconnected;
    } catch (_) {
      return stateDisconnected;
    }
  }

  Future<bool> registerApp() async {
    try {
      return await _channel.invokeMethod<bool>('registerApp') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resetHidProfile() async {
    try {
      return await _channel.invokeMethod<bool>('resetHidProfile') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unregisterApp() async {
    try {
      return await _channel.invokeMethod<bool>('unregisterApp') ?? false;
    } catch (_) {
      return false;
    }
  }
}

// Touchpad UI Screen
class TouchpadScreen extends StatefulWidget {
  const TouchpadScreen({super.key});

  @override
  State<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends State<TouchpadScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final BluetoothHidManager _hidManager;

  // State variables
  bool _isBluetoothSupported = true;
  bool _isHidSupported = true;
  bool _isBluetoothEnabled = false;
  bool _hasPermissions = false;
  int _connectionState = BluetoothHidManager.stateDisconnected;
  String _connectedDeviceName = "";
  String _connectedDeviceAddress = "";

  // Auto-Reconnection & State Tracking
  String _lastDeviceAddress = "";
  String _lastDeviceName = "";
  bool _isExplicitlyDisconnected = false;
  Timer? _reconnectTimer;
  bool _isAutoReconnecting = false;
  int _reconnectAttempts = 0;
  bool _isRecoveringTransport = false;
  static const int maxReconnectAttempts = 5;
  static const Duration hidResetDelay = Duration(milliseconds: 1200);

  // Touchpad Settings
  double _sensitivity = 1.2;
  double _scrollSensitivity = 0.8;
  bool _invertScroll = false;
  bool _hapticFeedbackEnabled = true;
  bool _landscapeModeEnabled = false;

  // Gesture Tracking
  Offset? _activeTouchPoint;
  final List<Offset> _touchTrail = [];
  Offset? _startTouchPoint;
  bool _hasMovedSignificantly = false;
  DateTime? _lastTapTime;
  bool _isDraggingLocked = false;
  int _currentButtons = 0; // 1 = Left, 2 = Right, 4 = Middle

  // Scroll Strip Gesture Tracking
  Offset? _activeScrollPoint;
  double _accumulatedScroll = 0;

  // Interpolation and smoothing accumulators
  double _accumulatedDx = 0.0;
  double _accumulatedDy = 0.0;

  // Slide Animation for settings drawer
  bool _isSettingsPanelOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hidManager = BluetoothHidManager();
    _setupBluetoothCallbacks();
    _loadSettings().then((_) {
      _checkSystemSupport();
    });
  }

  // Load settings from persistent SharedPreferences storage
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _sensitivity = prefs.getDouble('sensitivity') ?? 1.2;
        _scrollSensitivity = prefs.getDouble('scrollSensitivity') ?? 0.8;
        _invertScroll = prefs.getBool('invertScroll') ?? false;
        _hapticFeedbackEnabled = prefs.getBool('hapticFeedbackEnabled') ?? true;
        _landscapeModeEnabled = prefs.getBool('landscapeModeEnabled') ?? false;
        _lastDeviceAddress = prefs.getString('lastDeviceAddress') ?? "";
        _lastDeviceName = prefs.getString('lastDeviceName') ?? "";
      });
      _applyOrientationPreference(_landscapeModeEnabled);
    } catch (e) {
      debugPrint("Error loading settings: $e");
    }
  }

  Future<void> _applyOrientationPreference(bool landscapeEnabled) {
    return SystemChrome.setPreferredOrientations(
      landscapeEnabled
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
  }

  // Save setting to SharedPreferences
  Future<void> _saveSetting(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      }
    } catch (e) {
      debugPrint("Error saving setting $key: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recoverHidTransport(showStatus: false, resetTransport: false);
    }
  }

  void _setupBluetoothCallbacks() {
    _hidManager.onBluetoothStateChanged = (enabled) {
      setState(() {
        _isBluetoothEnabled = enabled;
      });
      _showToast(enabled ? "Bluetooth enabled" : "Bluetooth disabled");
    };

    _hidManager.onAppStatusChanged = (registered) {
      debugPrint("HID app registered: $registered");
    };

    _hidManager.onConnectionStateChanged = (state, name, address) {
      setState(() {
        _connectionState = state;
        if (state == BluetoothHidManager.stateConnected) {
          _connectedDeviceName = name;
          _connectedDeviceAddress = address;
          _lastDeviceAddress = address;
          _lastDeviceName = name;
          _saveSetting('lastDeviceAddress', address);
          _saveSetting('lastDeviceName', name);
          _isExplicitlyDisconnected = false;
          _stopAutoReconnect();
        } else if (state == BluetoothHidManager.stateDisconnected) {
          _connectedDeviceName = "";
          _connectedDeviceAddress = "";
        }
      });

      String stateStr = "";
      if (state == BluetoothHidManager.stateConnected) {
        stateStr = "Connected to $name";
        _triggerHaptic(HapticFeedbackType.heavy);
      } else if (state == BluetoothHidManager.stateDisconnected) {
        stateStr = "Disconnected";
        _triggerHaptic(HapticFeedbackType.medium);

        // Unexpected disconnect: trigger auto reconnection!
        if (!_isExplicitlyDisconnected && _lastDeviceAddress.isNotEmpty) {
          _startAutoReconnect();
        }
      } else if (state == BluetoothHidManager.stateConnecting) {
        stateStr = "Connecting to $name...";
      }

      _showToast(stateStr);
    };
  }

  // Trigger background auto reconnection attempts
  void _startAutoReconnect() {
    if (_isAutoReconnecting) return;
    if (_lastDeviceAddress.isEmpty) return;

    setState(() {
      _isAutoReconnecting = true;
      _reconnectAttempts = 0;
    });

    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_connectionState == BluetoothHidManager.stateConnected) {
        _stopAutoReconnect();
        return;
      }

      if (_reconnectAttempts >= maxReconnectAttempts) {
        _stopAutoReconnect();
        _showToast("Auto-reconnect failed. Please connect manually.");
        return;
      }

      _reconnectAttempts++;
      _showToast(
        "Reconnecting to $_lastDeviceName ($_reconnectAttempts/$maxReconnectAttempts)...",
      );

      final success = await _attemptReconnect(
        resetTransport: _reconnectAttempts >= 3,
      );
      if (success) {
        _stopAutoReconnect();
      }
    });
  }

  void _stopAutoReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_isAutoReconnecting) {
      setState(() {
        _isAutoReconnecting = false;
      });
    }
  }

  Future<bool> _attemptReconnect({bool resetTransport = false}) async {
    if (_lastDeviceAddress.isEmpty) return false;

    if (resetTransport) {
      await _hidManager.resetHidProfile();
      await Future.delayed(hidResetDelay);
    } else {
      await _hidManager.registerApp();
      await Future.delayed(const Duration(milliseconds: 250));
    }

    return _hidManager.connectDevice(_lastDeviceAddress);
  }

  Future<void> _recoverHidTransport({
    bool showStatus = true,
    bool resetTransport = false,
  }) async {
    if (_isRecoveringTransport) return;
    if (!_hasPermissions ||
        !_isBluetoothEnabled ||
        _lastDeviceAddress.isEmpty) {
      return;
    }

    _isRecoveringTransport = true;
    try {
      if (resetTransport) {
        await _hidManager.resetHidProfile();
        await Future.delayed(hidResetDelay);
      } else {
        await _hidManager.registerApp();
        await Future.delayed(const Duration(milliseconds: 250));
      }
      final state = await _hidManager.getConnectionState();

      if (!mounted) return;
      setState(() {
        _connectionState = state;
        if (state == BluetoothHidManager.stateConnected) {
          _connectedDeviceName = _connectedDeviceName.isNotEmpty
              ? _connectedDeviceName
              : _lastDeviceName;
          _connectedDeviceAddress = _connectedDeviceAddress.isNotEmpty
              ? _connectedDeviceAddress
              : _lastDeviceAddress;
        } else {
          _connectedDeviceName = _lastDeviceName;
          _connectedDeviceAddress = _lastDeviceAddress;
        }
      });

      if (state == BluetoothHidManager.stateConnected ||
          _isExplicitlyDisconnected) {
        return;
      }

      _stopAutoReconnect();
      setState(() {
        _connectionState = BluetoothHidManager.stateConnecting;
      });
      if (showStatus) {
        _showToast("Reconnecting to $_lastDeviceName...");
      }

      final ok = await _hidManager.connectDevice(_lastDeviceAddress);
      if (!mounted) return;

      if (!ok) {
        setState(() {
          _connectionState = BluetoothHidManager.stateDisconnected;
          _connectedDeviceName = "";
          _connectedDeviceAddress = "";
        });
        _startAutoReconnect();
      }
    } finally {
      _isRecoveringTransport = false;
    }
  }

  Future<void> _checkSystemSupport() async {
    final btSupported = await _hidManager.isBluetoothSupported();
    final hidSupported = await _hidManager.isHidSupported();
    final btEnabled = await _hidManager.isBluetoothEnabled();
    final permissionsGranted = await _hidManager.checkPermissions();

    setState(() {
      _isBluetoothSupported = btSupported;
      _isHidSupported = hidSupported;
      _isBluetoothEnabled = btEnabled;
      _hasPermissions = permissionsGranted;
    });

    if (permissionsGranted && btEnabled) {
      await _hidManager.registerApp();
      await _fetchCurrentConnectionState();

      // Auto-connect to the last device on app launch!
      if (_connectionState == BluetoothHidManager.stateDisconnected &&
          _lastDeviceAddress.isNotEmpty) {
        setState(() {
          _isExplicitlyDisconnected = false;
          _connectionState = BluetoothHidManager.stateConnecting;
          _connectedDeviceName = _lastDeviceName;
          _connectedDeviceAddress = _lastDeviceAddress;
        });
        _showToast("Auto-connecting to $_lastDeviceName...");
        final ok = await _hidManager.connectDevice(_lastDeviceAddress);
        if (!ok) {
          setState(() {
            _connectionState = BluetoothHidManager.stateDisconnected;
          });
          // Start retry cycle if first quick attempt fails
          _startAutoReconnect();
        }
      }
    }
  }

  Future<void> _fetchCurrentConnectionState() async {
    final state = await _hidManager.getConnectionState();
    setState(() {
      _connectionState = state;
      if (state == BluetoothHidManager.stateConnected) {
        _connectedDeviceName = _connectedDeviceName.isNotEmpty
            ? _connectedDeviceName
            : _lastDeviceName;
        _connectedDeviceAddress = _connectedDeviceAddress.isNotEmpty
            ? _connectedDeviceAddress
            : _lastDeviceAddress;
      }
    });
  }

  Future<void> _requestPermissions() async {
    final granted = await _hidManager.requestPermissions();
    setState(() {
      _hasPermissions = granted;
    });
    if (granted) {
      _showToast("Permissions granted");
      if (_isBluetoothEnabled) {
        await _hidManager.registerApp();
      }
    } else {
      _showToast("Permissions denied");
    }
  }

  // Toast Helper
  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: const Color(0xFF1F1D2B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      ),
    );
  }

  // Haptic Feedback Helper
  void _triggerHaptic(HapticFeedbackType type) {
    if (!_hapticFeedbackEnabled) return;
    switch (type) {
      case HapticFeedbackType.light:
        HapticFeedback.lightImpact();
        break;
      case HapticFeedbackType.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticFeedbackType.heavy:
        HapticFeedback.heavyImpact();
        break;
      case HapticFeedbackType.selection:
        HapticFeedback.selectionClick();
        break;
    }
  }

  // Mouse reporting
  void _sendMouseEvent({
    int buttons = 0,
    int dx = 0,
    int dy = 0,
    int wheel = 0,
  }) {
    if (_connectionState == BluetoothHidManager.stateConnected) {
      _hidManager
          .sendMouseEvent(buttons: buttons, dx: dx, dy: dy, wheel: wheel)
          .then((sent) {
            if (!sent && mounted && !_isExplicitlyDisconnected) {
              setState(() {
                _connectionState = BluetoothHidManager.stateDisconnected;
                _connectedDeviceName = "";
                _connectedDeviceAddress = "";
                _currentButtons = 0;
                _isDraggingLocked = false;
              });
              _recoverHidTransport();
            }
          });
    }
  }

  // Perform a clean left click (down, wait, up)
  Future<void> _performLeftClick() async {
    _triggerHaptic(HapticFeedbackType.medium);
    _sendMouseEvent(buttons: 1);
    await Future.delayed(const Duration(milliseconds: 40));
    _sendMouseEvent(buttons: 0);
  }

  // Perform a clean right click
  Future<void> _performRightClick() async {
    _triggerHaptic(HapticFeedbackType.medium);
    _sendMouseEvent(buttons: 2);
    await Future.delayed(const Duration(milliseconds: 40));
    _sendMouseEvent(buttons: 0);
  }

  // Raw Pointer down
  void _onPointerDown(PointerDownEvent event) {
    _startTouchPoint = event.localPosition;
    _hasMovedSignificantly = false;

    // Double tap click-and-drag logic
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 250)) {
      // Double tap! Lock left click down for dragging
      _isDraggingLocked = true;
      _currentButtons = 1;
      _sendMouseEvent(buttons: _currentButtons);
      _triggerHaptic(HapticFeedbackType.heavy);
      _showToast("Drag Lock Active");
    }
    _lastTapTime = now;

    setState(() {
      _activeTouchPoint = event.localPosition;
      _touchTrail.clear();
      _touchTrail.add(event.localPosition);
    });
  }

  // Raw Pointer move (Handles pointer calculation and neon trail)
  void _onPointerMove(PointerMoveEvent event) {
    if (_startTouchPoint != null) {
      final dist = (event.localPosition - _startTouchPoint!).distance;
      if (dist > 8.0) {
        _hasMovedSignificantly = true;
      }
    }

    setState(() {
      _activeTouchPoint = event.localPosition;
      _touchTrail.add(event.localPosition);
      if (_touchTrail.length > 15) {
        _touchTrail.removeAt(0);
      }
    });

    // Cursor movement delta calculation
    double rawDx = event.delta.dx * _sensitivity;
    double rawDy = event.delta.dy * _sensitivity;

    _accumulatedDx += rawDx;
    _accumulatedDy += rawDy;

    int sendX = _accumulatedDx.truncate();
    int sendY = _accumulatedDy.truncate();

    _accumulatedDx -= sendX;
    _accumulatedDy -= sendY;

    if (sendX != 0 || sendY != 0) {
      sendX = sendX.clamp(-127, 127);
      sendY = sendY.clamp(-127, 127);
      _sendMouseEvent(buttons: _currentButtons, dx: sendX, dy: sendY);
    }
  }

  // Raw Pointer up
  void _onPointerUp(PointerUpEvent event) {
    if (!_hasMovedSignificantly && !_isDraggingLocked) {
      // Tap detected! Perform click
      _performLeftClick();
    } else if (_isDraggingLocked) {
      // Release Drag Lock
      _isDraggingLocked = false;
      _currentButtons = 0;
      _sendMouseEvent(buttons: 0);
      _triggerHaptic(HapticFeedbackType.light);
    }

    setState(() {
      _activeTouchPoint = null;
      _touchTrail.clear();
    });
  }

  // Scroll Strip Handling
  void _onScrollDown(PointerDownEvent event) {
    _triggerHaptic(HapticFeedbackType.selection);
    setState(() {
      _activeScrollPoint = event.localPosition;
    });
  }

  void _onScrollMove(PointerMoveEvent event) {
    setState(() {
      _activeScrollPoint = event.localPosition;
    });

    double rawScroll = event.delta.dy * _scrollSensitivity;
    _accumulatedScroll += rawScroll;

    int sendScroll = _accumulatedScroll.truncate();
    _accumulatedScroll -= sendScroll;

    if (sendScroll != 0) {
      sendScroll = sendScroll.clamp(-127, 127);
      int finalScroll = _invertScroll
          ? sendScroll
          : -sendScroll; // Invert scroll wheel mapping
      _sendMouseEvent(
        buttons: _currentButtons,
        dx: 0,
        dy: 0,
        wheel: finalScroll,
      );
      _triggerHaptic(HapticFeedbackType.light);
    }
  }

  void _onScrollUp(PointerUpEvent event) {
    setState(() {
      _activeScrollPoint = null;
    });
  }

  // Device Manager bottom sheet
  void _showDeviceManager() async {
    _triggerHaptic(HapticFeedbackType.selection);

    if (!_hasPermissions) {
      _requestPermissions();
      return;
    }

    final pairedDevices = await _hidManager.getPairedDevices();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1F1D2B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 24,
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Bluetooth Devices",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white60),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Pair your PC first in Android system settings, then select it below to connect as a Touchpad.",
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  if (pairedDevices.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      alignment: Alignment.center,
                      child: const Column(
                        children: [
                          Icon(
                            Icons.bluetooth_searching,
                            size: 48,
                            color: Colors.white24,
                          ),
                          SizedBox(height: 12),
                          Text(
                            "No paired devices found",
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: pairedDevices.length,
                        separatorBuilder: (context, index) =>
                            const Divider(color: Colors.white10),
                        itemBuilder: (context, index) {
                          final device = pairedDevices[index];
                          final isCurrent =
                              _connectedDeviceAddress == device['address'];

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.computer_rounded,
                              color: isCurrent
                                  ? const Color(0xFF00FFCC)
                                  : Colors.white70,
                            ),
                            title: Text(
                              device['name'] ?? "Unknown",
                              style: TextStyle(
                                color: isCurrent
                                    ? const Color(0xFF00FFCC)
                                    : Colors.white,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              device['address'] ?? "",
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                            trailing: isCurrent
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF00FFCC,
                                      ).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF00FFCC,
                                        ).withOpacity(0.3),
                                      ),
                                    ),
                                    child: const Text(
                                      "Connected",
                                      style: TextStyle(
                                        color: Color(0xFF00FFCC),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: Colors.white38,
                                  ),
                            onTap: () async {
                              _triggerHaptic(HapticFeedbackType.selection);
                              Navigator.pop(context);

                              if (isCurrent) {
                                // Disconnect explicitly
                                setState(() {
                                  _isExplicitlyDisconnected = true;
                                  _lastDeviceAddress = "";
                                  _lastDeviceName = "";
                                });
                                _saveSetting('lastDeviceAddress', '');
                                _saveSetting('lastDeviceName', '');
                                _stopAutoReconnect();
                                await _hidManager.disconnectDevice();
                              } else {
                                // Connect explicitly
                                setState(() {
                                  _isExplicitlyDisconnected = false;
                                  _connectionState =
                                      BluetoothHidManager.stateConnecting;
                                  _connectedDeviceName = device['name'] ?? "PC";
                                  _connectedDeviceAddress =
                                      device['address'] ?? "";
                                });
                                _stopAutoReconnect();
                                final ok = await _hidManager.connectDevice(
                                  device['address']!,
                                );
                                if (!ok) {
                                  setState(() {
                                    _connectionState =
                                        BluetoothHidManager.stateDisconnected;
                                  });
                                  _showToast(
                                    "Connection failed. Make sure your PC is powered and Bluetooth is active.",
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            _triggerHaptic(HapticFeedbackType.selection);
                            await _hidManager.makeDiscoverable();
                          },
                          icon: const Icon(Icons.wifi_tethering, size: 18),
                          label: const Text("Make Discoverable"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white30),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _triggerHaptic(HapticFeedbackType.selection);
                            _hidManager.openBluetoothSettings();
                          },
                          icon: const Icon(Icons.settings_bluetooth, size: 18),
                          label: const Text("Bluetooth Settings"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE94057),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Header connection bar
  Widget _buildHeader() {
    Color statusColor;
    String statusText;
    bool isPulse = false;

    switch (_connectionState) {
      case BluetoothHidManager.stateConnected:
        statusColor = const Color(0xFF00FFCC);
        statusText = "Connected to $_connectedDeviceName";
        break;
      case BluetoothHidManager.stateConnecting:
        statusColor = const Color(0xFFF27121);
        statusText = "Connecting...";
        isPulse = true;
        break;
      case BluetoothHidManager.stateDisconnecting:
        statusColor = const Color(0xFFE94057);
        statusText = "Disconnecting...";
        break;
      case BluetoothHidManager.stateDisconnected:
      default:
        statusColor = Colors.white38;
        statusText = "Not Connected";
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    "AndPad",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Color(0xFF8A2387),
                          offset: Offset(-1, -1),
                          blurRadius: 4,
                        ),
                        Shadow(
                          color: Color(0xFF00FFCC),
                          offset: Offset(1, 1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8A2387).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF8A2387).withOpacity(0.4),
                        width: 0.5,
                      ),
                    ),
                    child: const Text(
                      "HID MOUSE",
                      style: TextStyle(
                        color: Color(0xFFE94057),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  _StatusDot(color: statusColor, pulse: isPulse),
                  const SizedBox(width: 6),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white70),
                onPressed: () {
                  _triggerHaptic(HapticFeedbackType.selection);
                  setState(() {
                    _isSettingsPanelOpen = !_isSettingsPanelOpen;
                  });
                },
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: _showDeviceManager,
                icon: const Icon(Icons.bluetooth_connected, size: 16),
                label: const Text("PC Connect"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F1D2B),
                  foregroundColor: const Color(0xFF00FFCC),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  side: const BorderSide(color: Color(0xFF00FFCC), width: 0.8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Device checking fallbacks
  Widget _buildFallbackUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 64,
              color: Color(0xFFE94057),
            ),
            const SizedBox(height: 24),
            const Text(
              "Bluetooth HID Unsupported",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              !_isBluetoothSupported
                  ? "This device does not have a physical Bluetooth adapter."
                  : "Your phone's Android Bluetooth stack does not support the Bluetooth HID Device profile. Android 9+ is required, and some manufacturers disable this feature.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, height: 1.5),
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => _checkSystemSupport(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white30),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text("Retry Connection Support Check"),
            ),
          ],
        ),
      ),
    );
  }

  // Bluetooth activation request page
  Widget _buildEnableBluetoothUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.bluetooth_disabled_rounded,
              size: 64,
              color: Color(0xFFF27121),
            ),
            const SizedBox(height: 24),
            const Text(
              "Bluetooth is Disabled",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Bluetooth must be turned on to pair and communicate with your PC as a virtual touchpad.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, height: 1.5),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                _triggerHaptic(HapticFeedbackType.selection);
                await _hidManager
                    .makeDiscoverable(); // Prompt to turn on & pair
                _checkSystemSupport();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FFCC),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Enable Bluetooth",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Permission request page
  Widget _buildRequestPermissionUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.security_rounded,
              size: 64,
              color: Color(0xFF8A2387),
            ),
            const SizedBox(height: 24),
            const Text(
              "Permissions Required",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "AndPad needs Bluetooth permissions to act as a virtual mouse and connect with other computers.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, height: 1.5),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _requestPermissions,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94057),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Grant Permissions",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTouchpadWorkspace(bool isLandscape) {
    if (isLandscape) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Row(
          children: [
            Expanded(child: _buildTouchpadAndScroll()),
            const SizedBox(width: 16),
            SizedBox(
              width: 180,
              child: Column(
                children: [
                  Expanded(
                    child: _buildClickButton(
                      label: "LEFT CLICK",
                      isLeft: true,
                      onPressed: _performLeftClick,
                      height: double.infinity,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _buildClickButton(
                      label: "RIGHT CLICK",
                      isLeft: false,
                      onPressed: _performRightClick,
                      height: double.infinity,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 8,
              bottom: 16,
            ),
            child: _buildTouchpadAndScroll(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
          child: Row(
            children: [
              Expanded(
                child: _buildClickButton(
                  label: "LEFT CLICK",
                  isLeft: true,
                  onPressed: _performLeftClick,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildClickButton(
                  label: "RIGHT CLICK",
                  isLeft: false,
                  onPressed: _performRightClick,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTouchpadAndScroll() {
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1F1D2B).withOpacity(0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isDraggingLocked
                    ? const Color(0xFFE94057).withOpacity(0.5)
                    : Colors.white.withOpacity(0.08),
                width: _isDraggingLocked ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                child: CustomPaint(
                  painter: TouchpadPainter(
                    activePoint: _activeTouchPoint,
                    points: _touchTrail,
                  ),
                  child: Center(
                    child: Opacity(
                      opacity: _activeTouchPoint == null ? 0.35 : 0.1,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isDraggingLocked
                                ? Icons.lock_outline_rounded
                                : Icons.gesture_rounded,
                            size: 40,
                            color: _isDraggingLocked
                                ? const Color(0xFFE94057)
                                : Colors.white60,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isDraggingLocked
                                ? "Drag Lock Enabled"
                                : "Touch & Slide to Move Cursor",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _isDraggingLocked
                                  ? const Color(0xFFE94057)
                                  : Colors.white60,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Tap = Click | Double Tap = Drag Lock",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white30,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Container(
          width: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF1F1D2B).withOpacity(0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Listener(
              onPointerDown: _onScrollDown,
              onPointerMove: _onScrollMove,
              onPointerUp: _onScrollUp,
              child: CustomPaint(
                painter: ScrollStripPainter(activePoint: _activeScrollPoint),
                child: const Center(
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Opacity(
                      opacity: 0.35,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.unfold_more_rounded,
                            size: 20,
                            color: Colors.white60,
                          ),
                          SizedBox(width: 4),
                          Text(
                            "SCROLL",
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isBluetoothSupported || !_isHidSupported) {
      return Scaffold(body: SafeArea(child: _buildFallbackUI()));
    }

    if (!_hasPermissions) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildRequestPermissionUI()),
            ],
          ),
        ),
      );
    }

    if (!_isBluetoothEnabled) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildEnableBluetoothUI()),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: OrientationBuilder(
                      builder: (context, orientation) {
                        return _buildTouchpadWorkspace(
                          orientation == Orientation.landscape,
                        );
                      },
                    ),
                  ),

                  // Overlay Settings Drawer Panel (Glassmorphic)
                  if (_isSettingsPanelOpen)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _isSettingsPanelOpen = false;
                          });
                        },
                        child: Container(
                          color: Colors.black45,
                          child: Align(
                            alignment: Alignment.topRight,
                            child: GestureDetector(
                              onTap: () {}, // Prevent tap propagation
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.8,
                                height: double.infinity,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1F1D2B),
                                  borderRadius: BorderRadius.horizontal(
                                    left: Radius.circular(24),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black54,
                                      blurRadius: 30,
                                      offset: Offset(-8, 0),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: ListView(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              "Settings",
                                              style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close),
                                              onPressed: () {
                                                setState(() {
                                                  _isSettingsPanelOpen = false;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                        const Divider(
                                          color: Colors.white10,
                                          height: 24,
                                        ),
                                        const Text(
                                          "TRACKPAD SENSITIVITY",
                                          style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.speed_rounded,
                                              size: 16,
                                              color: Colors.white60,
                                            ),
                                            Expanded(
                                              child: Slider(
                                                value: _sensitivity,
                                                min: 0.4,
                                                max: 3.0,
                                                activeColor: const Color(
                                                  0xFF00FFCC,
                                                ),
                                                inactiveColor: Colors.white10,
                                                onChanged: (val) {
                                                  setState(() {
                                                    _sensitivity = val;
                                                  });
                                                },
                                                onChangeEnd: (val) {
                                                  _saveSetting(
                                                    'sensitivity',
                                                    val,
                                                  );
                                                },
                                              ),
                                            ),
                                            Text(
                                              _sensitivity.toStringAsFixed(1),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 24),
                                        const Text(
                                          "SCROLL SPEED",
                                          style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.unfold_more_rounded,
                                              size: 16,
                                              color: Colors.white60,
                                            ),
                                            Expanded(
                                              child: Slider(
                                                value: _scrollSensitivity,
                                                min: 0.2,
                                                max: 2.0,
                                                activeColor: const Color(
                                                  0xFF00FFCC,
                                                ),
                                                inactiveColor: Colors.white10,
                                                onChanged: (val) {
                                                  setState(() {
                                                    _scrollSensitivity = val;
                                                  });
                                                },
                                                onChangeEnd: (val) {
                                                  _saveSetting(
                                                    'scrollSensitivity',
                                                    val,
                                                  );
                                                },
                                              ),
                                            ),
                                            Text(
                                              _scrollSensitivity
                                                  .toStringAsFixed(1),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 24),
                                        SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text(
                                            "Invert Scroll",
                                            style: TextStyle(fontSize: 15),
                                          ),
                                          subtitle: const Text(
                                            "Reverse scroll wheel direction",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white38,
                                            ),
                                          ),
                                          value: _invertScroll,
                                          activeColor: const Color(0xFF00FFCC),
                                          onChanged: (val) {
                                            setState(() {
                                              _invertScroll = val;
                                            });
                                            _saveSetting('invertScroll', val);
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text(
                                            "Haptic Feedback",
                                            style: TextStyle(fontSize: 15),
                                          ),
                                          subtitle: const Text(
                                            "Vibrate on click, drag and scroll",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white38,
                                            ),
                                          ),
                                          value: _hapticFeedbackEnabled,
                                          activeColor: const Color(0xFF00FFCC),
                                          onChanged: (val) {
                                            setState(() {
                                              _hapticFeedbackEnabled = val;
                                            });
                                            _saveSetting(
                                              'hapticFeedbackEnabled',
                                              val,
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text(
                                            "Landscape Mode",
                                            style: TextStyle(fontSize: 15),
                                          ),
                                          subtitle: const Text(
                                            "Use the wider touchpad layout",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white38,
                                            ),
                                          ),
                                          value: _landscapeModeEnabled,
                                          activeThumbColor: const Color(
                                            0xFF00FFCC,
                                          ),
                                          onChanged: (val) {
                                            setState(() {
                                              _landscapeModeEnabled = val;
                                            });
                                            _saveSetting(
                                              'landscapeModeEnabled',
                                              val,
                                            );
                                            _applyOrientationPreference(val);
                                          },
                                        ),
                                        const SizedBox(height: 24),
                                        const Center(
                                          child: Text(
                                            "AndPad v1.0.0",
                                            style: TextStyle(
                                              color: Colors.white24,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Click Button Widget
  Widget _buildClickButton({
    required String label,
    required bool isLeft,
    required VoidCallback onPressed,
    double height = 72,
  }) {
    final theme = Theme.of(context);
    final glowColor = isLeft
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary;

    return GestureDetector(
      onTapDown: (_) {
        _triggerHaptic(HapticFeedbackType.medium);
        // Press state
        _sendMouseEvent(buttons: isLeft ? 1 : 2);
      },
      onTapUp: (_) {
        _sendMouseEvent(buttons: 0);
      },
      onTapCancel: () {
        _sendMouseEvent(buttons: 0);
      },
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF1F1D2B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: glowColor.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: glowColor.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: glowColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// Custom Painter for the responsive, glowing Trackpad
class TouchpadPainter extends CustomPainter {
  final Offset? activePoint;
  final List<Offset> points;

  TouchpadPainter({this.activePoint, required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background grid lines with extremely low opacity
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.02)
      ..strokeWidth = 1.0;

    const double spacing = 45.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw the active trailing finger ribbon
    if (points.isNotEmpty) {
      final trailPaint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < points.length - 1; i++) {
        double opacity = (i / points.length).clamp(0.0, 1.0);
        trailPaint.color = const Color(0xFF00FFCC).withOpacity(opacity * 0.45);
        trailPaint.strokeWidth = opacity * 6.5 + 1.5;

        // Glowing overlay
        final glowPaint = Paint()
          ..color = const Color(0xFF00FFCC).withOpacity(opacity * 0.16)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = trailPaint.strokeWidth * 3.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
          ..style = PaintingStyle.stroke;

        canvas.drawLine(points[i], points[i + 1], glowPaint);
        canvas.drawLine(points[i], points[i + 1], trailPaint);
      }
    }

    // Active touch indicator (pulsing warm Sunset gradient)
    if (activePoint != null) {
      final outerGlow = Paint()
        ..color = const Color(0xFF8A2387).withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(activePoint!, 32, outerGlow);

      final midGlow = Paint()
        ..color = const Color(0xFFE94057).withOpacity(0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(activePoint!, 18, midGlow);

      final core = Paint()
        ..color = const Color(0xFF00FFCC)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(activePoint!, 6, core);
    }
  }

  @override
  bool shouldRepaint(covariant TouchpadPainter oldDelegate) => true;
}

// Custom Painter for the Scroll Strip
class ScrollStripPainter extends CustomPainter {
  final Offset? activePoint;

  ScrollStripPainter({this.activePoint});

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle centerline
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(size.width / 2, 16),
      Offset(size.width / 2, size.height - 16),
      linePaint,
    );

    // Glowing indicator following finger inside the Scroll Strip
    if (activePoint != null) {
      final center = Offset(
        size.width / 2,
        activePoint!.dy.clamp(16.0, size.height - 16.0),
      );

      final glowPaint = Paint()
        ..color = const Color(0xFFE94057).withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(center, 20, glowPaint);

      final corePaint = Paint()
        ..color = const Color(0xFFE94057)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 5, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant ScrollStripPainter oldDelegate) => true;
}

// Custom Status Indicator Dot (glowing/pulsing)
class _StatusDot extends StatefulWidget {
  final Color color;
  final bool pulse;

  const _StatusDot({required this.color, this.pulse = false});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.pulse) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (widget.pulse ? _controller.value * 0.6 : 0.0);
        final opacity = widget.pulse ? 1.0 - _controller.value * 0.5 : 1.0;

        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withOpacity(opacity),
                boxShadow: [
                  BoxShadow(
                    color: widget.color,
                    blurRadius: widget.pulse ? 6 : 2,
                    spreadRadius: widget.pulse ? 1 : 0,
                  ),
                ],
              ),
            ),
            if (widget.pulse)
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withOpacity(0.3),
                      width: 1.0,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
