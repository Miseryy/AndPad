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
}
