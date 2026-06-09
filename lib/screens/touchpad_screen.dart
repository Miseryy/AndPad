import 'dart:async';
import '../features/hid/bluetooth_hid_manager.dart';
import '../features/keyboard/keyboard_keys.dart';
import '../features/touchpad/touchpad_painters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'widgets/status_dot.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HapticFeedbackType { light, medium, heavy, selection }

enum InputMode { touchpad, keyboard }

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
  InputMode _inputMode = InputMode.touchpad;
  bool _keyboardCtrlEnabled = false;
  bool _keyboardShiftEnabled = false;
  bool _keyboardCapsEnabled = false;
  bool _keyboardSymbolsEnabled = false;

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

    _hidManager.onHidProfileAvailabilityChanged = (available) {
      _stopAutoReconnect();
      setState(() {
        _isHidSupported = available;
        if (!available) {
          _connectionState = BluetoothHidManager.stateDisconnected;
          _connectedDeviceName = "";
          _connectedDeviceAddress = "";
        }
      });
    };

    _hidManager.onAppStatusChanged = (registered) {
      debugPrint("HID app registered: $registered");
    };

    _hidManager.onHidDebugEvent = (action, detail) {
      debugPrint("Native HID debug: $action $detail");
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
      if (_connectionState == BluetoothHidManager.stateConnecting) {
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

      await _attemptReconnect(resetTransport: _reconnectAttempts >= 3);
      final state = await _hidManager.getConnectionState();
      if (mounted) {
        setState(() {
          _connectionState = state;
        });
      }
      if (state == BluetoothHidManager.stateConnected) {
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
            if (!sent) {
              _handleSendFailure();
            }
          });
    }
  }

  void _handleSendFailure() {
    if (!mounted || _isExplicitlyDisconnected) return;
    setState(() {
      _connectionState = BluetoothHidManager.stateDisconnected;
      _connectedDeviceName = "";
      _connectedDeviceAddress = "";
      _currentButtons = 0;
      _isDraggingLocked = false;
    });
    _recoverHidTransport();
  }

  Future<bool> _sendKeyboardEvent({
    int modifiers = 0,
    List<int> keyCodes = const [],
    String debugLabel = "release",
  }) async {
    if (_connectionState != BluetoothHidManager.stateConnected) {
      _updateKeyboardDebug(
        "$debugLabel blocked",
        modifiers: modifiers,
        keyCodes: keyCodes,
        sent: false,
        reason: "not connected",
      );
      return false;
    }

    final sent = await _hidManager.sendKeyboardEvent(
      modifiers: modifiers,
      keyCodes: keyCodes,
    );
    _updateKeyboardDebug(
      debugLabel,
      modifiers: modifiers,
      keyCodes: keyCodes,
      sent: sent,
    );
    if (!sent) {
      _handleSendFailure();
    }
    return sent;
  }

  Future<void> _tapKeyboardKey(KeyboardKeySpec key) async {
    _triggerHaptic(HapticFeedbackType.selection);
    final modifiers =
        key.modifiers | (_keyboardCtrlEnabled ? keyboardLeftCtrlModifier : 0);
    await _sendKeyboardEvent(
      modifiers: modifiers,
      keyCodes: [key.keyCode],
      debugLabel: "press ${key.label}",
    );
    await Future.delayed(const Duration(milliseconds: 35));
    await _sendKeyboardEvent(debugLabel: "release ${key.label}");

    if (_keyboardShiftEnabled && !key.isModifierAction) {
      setState(() {
        _keyboardShiftEnabled = false;
      });
    }
    if (_keyboardCtrlEnabled && !key.isModifierAction) {
      setState(() {
        _keyboardCtrlEnabled = false;
      });
    }
  }

  void _updateKeyboardDebug(
    String action, {
    required int modifiers,
    required List<int> keyCodes,
    required bool sent,
    String? reason,
  }) {
    final keyHex = keyCodes
        .map((code) => "0x${code.toRadixString(16)}")
        .join(", ");
    final modifierHex = "0x${modifiers.toRadixString(16)}";
    final status = sent ? "sent" : "failed";
    final reasonText = reason == null ? "" : " ($reason)";

    debugPrint(
      "Keyboard debug: $action modifier=$modifierHex keyCodes=[$keyHex] $status$reasonText",
    );
  }

  KeyboardKeySpec _keySpecForCharacter(String character) {
    const leftShift = 0x02;
    final lower = character.toLowerCase();

    if (lower.length == 1 &&
        lower.codeUnitAt(0) >= 97 &&
        lower.codeUnitAt(0) <= 122) {
      final shouldShift =
          _keyboardShiftEnabled ^
          _keyboardCapsEnabled ^
          (character.toUpperCase() == character &&
              character.toLowerCase() != character);
      return KeyboardKeySpec(
        label: shouldShift ? lower.toUpperCase() : lower,
        keyCode: lower.codeUnitAt(0) - 93,
        modifiers: shouldShift ? leftShift : 0,
      );
    }

    final base = plainKeyMap[character];
    if (base != null) {
      if (_keyboardShiftEnabled) {
        String? shiftedLabel;
        for (final entry in shiftedKeyMap.entries) {
          if (entry.value == base) {
            shiftedLabel = entry.key;
            break;
          }
        }
        if (shiftedLabel != null) {
          return KeyboardKeySpec(
            label: shiftedLabel,
            keyCode: base,
            modifiers: leftShift,
          );
        }
      }
      return KeyboardKeySpec(label: character, keyCode: base);
    }

    final shifted = shiftedKeyMap[character];
    if (shifted != null) {
      return KeyboardKeySpec(
        label: character,
        keyCode: shifted,
        modifiers: leftShift,
      );
    }

    return KeyboardKeySpec(label: character, keyCode: 0);
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
                                      ).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF00FFCC,
                                        ).withValues(alpha: 0.3),
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
                                  _lastDeviceName = device['name'] ?? "PC";
                                  _lastDeviceAddress = device['address'] ?? "";
                                });
                                _saveSetting('lastDeviceName', _lastDeviceName);
                                _saveSetting(
                                  'lastDeviceAddress',
                                  _lastDeviceAddress,
                                );
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
                      color: const Color(0xFF8A2387).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF8A2387).withValues(alpha: 0.4),
                        width: 0.5,
                      ),
                    ),
                    child: const Text(
                      "HID COMBO",
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
                  StatusDot(color: statusColor, pulse: isPulse),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
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
      },
    );
  }

  // Bluetooth activation request page
  Widget _buildEnableBluetoothUI() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
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
      },
    );
  }

  // Permission request page
  Widget _buildRequestPermissionUI() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
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
      },
    );
  }

  Widget _buildInputWorkspace(bool isLandscape) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, isLandscape ? 4 : 8, 20, 4),
          child: _buildModeSelector(),
        ),
        Expanded(
          child: _inputMode == InputMode.touchpad
              ? _buildTouchpadWorkspace(isLandscape)
              : _buildKeyboardWorkspace(isLandscape),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1D2B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _buildModeButton(
            mode: InputMode.touchpad,
            icon: Icons.touch_app_rounded,
            label: "Touchpad",
          ),
          const SizedBox(width: 4),
          _buildModeButton(
            mode: InputMode.keyboard,
            icon: Icons.keyboard_rounded,
            label: "Keyboard",
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required InputMode mode,
    required IconData icon,
    required String label,
  }) {
    final selected = _inputMode == mode;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _triggerHaptic(HapticFeedbackType.selection);
          setState(() {
            _inputMode = mode;
            _currentButtons = 0;
            _isDraggingLocked = false;
            _activeTouchPoint = null;
            _activeScrollPoint = null;
            _touchTrail.clear();
          });
          _sendMouseEvent(buttons: 0);
          _sendKeyboardEvent();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF00FFCC) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.black : Colors.white60,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white60,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyboardWorkspace(bool isLandscape) {
    final horizontalPadding = isLandscape ? 20.0 : 12.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 430 || constraints.maxHeight < 390;
          final rowGap = compact ? 5.0 : 8.0;
          final desiredKeyHeight = compact ? 40.0 : 46.0;
          final keyHeight =
              (constraints.maxHeight - (rowGap * 4)).clamp(
                0.0,
                desiredKeyHeight * 5,
              ) /
              5;
          final resolvedKeyHeight = keyHeight.clamp(32.0, desiredKeyHeight);

          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              children: [
                _buildKeyboardKeys(
                  compact: compact,
                  keyHeight: resolvedKeyHeight,
                  rowGap: rowGap,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildKeyboardKeys({
    required bool compact,
    required double keyHeight,
    required double rowGap,
  }) {
    final rows = _keyboardSymbolsEnabled
        ? _buildSymbolKeyboardRows()
        : _buildAlphaKeyboardRows();

    return Column(
      children: [
        for (final row in rows) ...[
          Row(
            children: [
              for (final key in row) ...[
                Expanded(
                  flex: key.flex,
                  child: _buildKeyboardKey(key, height: keyHeight),
                ),
                if (key != row.last) SizedBox(width: compact ? 5 : 8),
              ],
            ],
          ),
          if (row != rows.last) SizedBox(height: rowGap),
        ],
      ],
    );
  }

  List<List<KeyboardKeySpec>> _buildAlphaKeyboardRows() {
    return [
      "1234567890".split("").map(_keySpecForCharacter).toList(),
      "qwertyuiop".split("").map(_keySpecForCharacter).toList(),
      "asdfghjkl".split("").map(_keySpecForCharacter).toList(),
      [
        const KeyboardKeySpec(
          label: "Shift",
          keyCode: 0,
          flex: 2,
          isModifierAction: true,
        ),
        ..."zxcvbnm".split("").map(_keySpecForCharacter),
        const KeyboardKeySpec(label: "Bksp", keyCode: 0x2a, flex: 2),
      ],
      [
        const KeyboardKeySpec(
          label: "Sym",
          keyCode: 0,
          flex: 2,
          isModifierAction: true,
        ),
        const KeyboardKeySpec(
          label: "Ctrl",
          keyCode: 0,
          flex: 2,
          isModifierAction: true,
        ),
        const KeyboardKeySpec(
          label: "Caps",
          keyCode: 0,
          flex: 2,
          isModifierAction: true,
        ),
        const KeyboardKeySpec(label: "Tab", keyCode: 0x2b, flex: 2),
        const KeyboardKeySpec(label: "Space", keyCode: 0x2c, flex: 5),
        const KeyboardKeySpec(label: "Enter", keyCode: 0x28, flex: 3),
      ],
    ];
  }

  List<List<KeyboardKeySpec>> _buildSymbolKeyboardRows() {
    return [
      [
        '!',
        '@',
        '#',
        r'$',
        '%',
        '^',
        '&',
        '*',
        '(',
        ')',
      ].map(_keySpecForCharacter).toList(),
      [
        '-',
        '_',
        '=',
        '+',
        '[',
        ']',
        '{',
        '}',
      ].map(_keySpecForCharacter).toList(),
      [
        ';',
        ':',
        "'",
        '"',
        ',',
        '.',
        '<',
        '>',
      ].map(_keySpecForCharacter).toList(),
      [
        ...['`', '~', '\\', '|', '/', '?'].map(_keySpecForCharacter),
        const KeyboardKeySpec(label: "Bksp", keyCode: 0x2a, flex: 2),
      ],
      [
        const KeyboardKeySpec(
          label: "ABC",
          keyCode: 0,
          flex: 2,
          isModifierAction: true,
        ),
        const KeyboardKeySpec(
          label: "Ctrl",
          keyCode: 0,
          flex: 2,
          isModifierAction: true,
        ),
        const KeyboardKeySpec(label: "Space", keyCode: 0x2c, flex: 5),
        const KeyboardKeySpec(label: "Enter", keyCode: 0x28, flex: 3),
      ],
    ];
  }

  Widget _buildKeyboardKey(KeyboardKeySpec key, {required double height}) {
    final isCtrl = key.label == "Ctrl";
    final isShift = key.label == "Shift";
    final isCaps = key.label == "Caps";
    final isSymbolToggle = key.label == "Sym" || key.label == "ABC";
    final selected =
        (isCtrl && _keyboardCtrlEnabled) ||
        (isShift && _keyboardShiftEnabled) ||
        (isCaps && _keyboardCapsEnabled) ||
        (isSymbolToggle && _keyboardSymbolsEnabled);
    final accent = selected ? const Color(0xFF00FFCC) : Colors.white70;

    return GestureDetector(
      onTap: () async {
        if (isCtrl) {
          setState(() {
            _keyboardCtrlEnabled = !_keyboardCtrlEnabled;
          });
          _triggerHaptic(HapticFeedbackType.selection);
          return;
        }
        if (isShift) {
          setState(() {
            _keyboardShiftEnabled = !_keyboardShiftEnabled;
          });
          _triggerHaptic(HapticFeedbackType.selection);
          return;
        }
        if (isCaps) {
          setState(() {
            _keyboardCapsEnabled = !_keyboardCapsEnabled;
          });
          _triggerHaptic(HapticFeedbackType.selection);
          return;
        }
        if (isSymbolToggle) {
          setState(() {
            _keyboardSymbolsEnabled = !_keyboardSymbolsEnabled;
            _keyboardShiftEnabled = false;
          });
          _triggerHaptic(HapticFeedbackType.selection);
          return;
        }
        await _tapKeyboardKey(key);
      },
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00FFCC).withValues(alpha: 0.18)
              : const Color(0xFF1F1D2B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFF00FFCC).withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          key.label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(
            color: accent,
            fontSize: key.label.length > 1 ? 12 : 15,
            fontWeight: FontWeight.bold,
          ),
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
              color: const Color(0xFF1F1D2B).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isDraggingLocked
                    ? const Color(0xFFE94057).withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08),
                width: _isDraggingLocked ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
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
            color: const Color(0xFF1F1D2B).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
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
                        return _buildInputWorkspace(
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
                                          activeThumbColor: const Color(
                                            0xFF00FFCC,
                                          ),
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
                                          activeThumbColor: const Color(
                                            0xFF00FFCC,
                                          ),
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
          border: Border.all(color: glowColor.withValues(alpha: 0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.05),
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
