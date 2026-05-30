# AndPad

AndPad は、Android 端末を Bluetooth HID デバイスとして動作させ、PC 向けの仮想タッチパッドおよびキーボードとして利用するための Flutter アプリケーションです。

本アプリケーションは Android の Bluetooth HID Device Profile を使用し、マウス移動、左クリック、右クリック、スクロール操作、キーボード入力を PC に送信します。

## 機能

- Bluetooth HID による仮想マウス操作
- Bluetooth HID による仮想キーボード操作
- タッチパッド領域でのカーソル移動
- 左クリックおよび右クリック
- 専用スクロール領域によるホイール操作
- ダブルタップによるドラッグロック
- Touchpad/Keyboard モード切り替え
- 英数字、Shift、Caps、Tab、Backspace、Enter、Space キー入力
- 接続済み PC への自動再接続
- 感度、スクロール速度、スクロール方向、振動フィードバックの設定
- 縦向きおよび横向きレイアウトの切り替え

## 動作要件

- Android 9.0 以降
- Bluetooth HID Device Profile に対応した Android 端末
- Bluetooth 接続に対応した PC
- Flutter 開発環境

Bluetooth HID Device Profile は Android 9.0 以降で利用可能ですが、端末メーカーや機種によっては無効化されている場合があります。そのため、Android のバージョン要件を満たしていても本アプリケーションが利用できない場合があります。

エミュレータでは Bluetooth HID の実機検証はできません。動作確認には物理 Android 端末が必要です。

## セットアップ

依存関係を取得します。

```bash
flutter pub get
```

接続された Android 端末で実行します。

```bash
flutter run
```

デバッグ APK を作成します。

```bash
flutter build apk --debug
```

リリース APK を作成します。

```bash
flutter build apk --release
```

USB 接続した端末へ APK を直接インストールする場合は、以下を実行します。

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## 使用方法

1. Android 端末で Bluetooth を有効にします。
2. PC 側の Bluetooth 設定を開きます。
3. AndPad から端末を検出可能にします。
4. PC と Android 端末をペアリングします。
5. AndPad の `PC Connect` から接続先 PC を選択します。
6. 接続完了後、画面上の `Touchpad` / `Keyboard` 切り替えで操作モードを選択します。
7. `Touchpad` ではカーソル、クリック、スクロールを操作できます。
8. `Keyboard` ではオンスクリーンキーから PC へ文字や制御キーを送信できます。

HID の登録情報を変更した場合、または PC 側が旧設定を保持している場合は、PC 側で一度ペアリング情報を削除してから再ペアリングしてください。

## 権限

本アプリケーションは Bluetooth HID として動作するため、Android のバージョンに応じて以下の権限を使用します。

- `BLUETOOTH`
- `BLUETOOTH_ADMIN`
- `BLUETOOTH_CONNECT`
- `BLUETOOTH_ADVERTISE`
- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`

位置情報権限は古い Android バージョンにおける Bluetooth 検出処理のために使用されます。

## 開発

静的解析を実行します。

```bash
flutter analyze
```

テストを実行します。

```bash
flutter test
```

Dart コードを整形します。

```bash
dart format lib test
```

## 構成

- `lib/main.dart`: Flutter UI、ジェスチャー処理、設定管理、MethodChannel 呼び出し
- `android/app/src/main/kotlin/com/example/andpad/MainActivity.kt`: Bluetooth HID の登録、接続管理、マウスレポート送信
- `android/app/src/main/AndroidManifest.xml`: Android 権限およびアプリケーション設定
- `test/`: Flutter ウィジェットテスト

## 注意事項

本アプリケーションは Bluetooth HID の仕様および Android 端末の実装に依存します。すべての Android 端末および PC 環境での動作を保証するものではありません。

ペアリング済み端末名および Bluetooth アドレスは、接続状態の復元と再接続のために端末内へ保存されます。これらの情報は外部サーバーへ送信されません。
