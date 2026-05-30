import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:andpad/main.dart';

void main() {
  const channel = MethodChannel('com.example.andpad/hid');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isBluetoothSupported':
            case 'isHidSupported':
            case 'isBluetoothEnabled':
            case 'checkPermissions':
            case 'registerApp':
            case 'sendKeyboardEvent':
            case 'sendMouseEvent':
              return true;
            case 'getConnectionState':
              return BluetoothHidManager.stateDisconnected;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows touchpad connection controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('AndPad'), findsOneWidget);
    expect(find.text('PC Connect'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth_connected), findsOneWidget);
  });

  testWidgets('settings include landscape mode toggle', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('Landscape Mode'), findsOneWidget);
  });

  testWidgets('keyboard mode sends key reports', (WidgetTester tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isBluetoothSupported':
            case 'isHidSupported':
            case 'isBluetoothEnabled':
            case 'checkPermissions':
            case 'registerApp':
            case 'sendKeyboardEvent':
            case 'sendMouseEvent':
              return true;
            case 'getConnectionState':
              return BluetoothHidManager.stateConnected;
            default:
              return null;
          }
        });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keyboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a'));
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('Keyboard Ready'), findsNothing);

    final keyboardCalls = calls
        .where(
          (call) =>
              call.method == 'sendKeyboardEvent' &&
              ((call.arguments as Map<dynamic, dynamic>)['keyCodes']
                      as List<dynamic>)
                  .isNotEmpty,
        )
        .toList();
    final releaseCalls = calls
        .where(
          (call) =>
              call.method == 'sendKeyboardEvent' &&
              ((call.arguments as Map<dynamic, dynamic>)['keyCodes']
                      as List<dynamic>)
                  .isEmpty,
        )
        .toList();
    expect(keyboardCalls, isNotEmpty);
    expect(keyboardCalls.first.arguments, containsPair('keyCodes', [0x04]));
    expect(releaseCalls, isNotEmpty);
  });

  testWidgets('keyboard symbol mode sends symbol reports', (
    WidgetTester tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isBluetoothSupported':
            case 'isHidSupported':
            case 'isBluetoothEnabled':
            case 'checkPermissions':
            case 'registerApp':
            case 'sendKeyboardEvent':
            case 'sendMouseEvent':
              return true;
            case 'getConnectionState':
              return BluetoothHidManager.stateConnected;
            default:
              return null;
          }
        });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keyboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sym'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('!'));
    await tester.pump(const Duration(milliseconds: 60));

    final symbolCalls = calls
        .where(
          (call) =>
              call.method == 'sendKeyboardEvent' &&
              ((call.arguments as Map<dynamic, dynamic>)['keyCodes']
                      as List<dynamic>)
                  .isNotEmpty,
        )
        .toList();
    expect(symbolCalls, isNotEmpty);
    expect(symbolCalls.last.arguments, containsPair('modifiers', 0x02));
    expect(symbolCalls.last.arguments, containsPair('keyCodes', [0x1e]));
  });

  testWidgets('keyboard ctrl key modifies next key report', (
    WidgetTester tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isBluetoothSupported':
            case 'isHidSupported':
            case 'isBluetoothEnabled':
            case 'checkPermissions':
            case 'registerApp':
            case 'sendKeyboardEvent':
            case 'sendMouseEvent':
              return true;
            case 'getConnectionState':
              return BluetoothHidManager.stateConnected;
            default:
              return null;
          }
        });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keyboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ctrl'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('c'));
    await tester.pump(const Duration(milliseconds: 60));

    final ctrlCalls = calls
        .where(
          (call) =>
              call.method == 'sendKeyboardEvent' &&
              ((call.arguments as Map<dynamic, dynamic>)['keyCodes']
                      as List<dynamic>)
                  .isNotEmpty,
        )
        .toList();
    expect(ctrlCalls, isNotEmpty);
    expect(ctrlCalls.last.arguments, containsPair('modifiers', 0x01));
    expect(ctrlCalls.last.arguments, containsPair('keyCodes', [0x06]));
  });

  testWidgets('keyboard mode fits compact landscape viewport', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keyboard'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Space'), findsOneWidget);
  });
}
