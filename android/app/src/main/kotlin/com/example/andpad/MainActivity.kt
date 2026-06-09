package com.example.andpad

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.andpad/hid"
    private var channel: MethodChannel? = null

    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var hidDevice: BluetoothHidDevice? = null
    private var isHidProfileInitializationPending = false
    private var isHidProfileAvailable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
    private var hidProfileInitializationAttemptId = 0
    private var connectedDevice: BluetoothDevice? = null
    private var isAppRegistered = false
    private var isAppRegistrationPending = false
    private var pendingConnectionAddress: String? = null
    private var currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
    private var currentProtocol = BluetoothHidDevice.PROTOCOL_REPORT_MODE
    private val mainHandler = Handler(Looper.getMainLooper())
    private var connectionAttemptId = 0
    private val connectionTimeoutMs = 12_000L

    private var permissionResult: MethodChannel.Result? = null
    private val PERMISSION_REQUEST_CODE = 1001

    private fun sendHidDebugEvent(action: String, detail: String) {
        runOnUiThread {
            channel?.invokeMethod("onHidDebugEvent", mapOf(
                "action" to action,
                "detail" to detail
            ))
        }
    }

    // HID Report Descriptor for a 5-button Mouse and a boot keyboard.
    private val HID_DESCRIPTOR = byteArrayOf(
        0x05.toByte(), 0x01.toByte(), // USAGE_PAGE (Generic Desktop)
        0x09.toByte(), 0x02.toByte(), // USAGE (Mouse)
        0xa1.toByte(), 0x01.toByte(), // COLLECTION (Application)
        0x09.toByte(), 0x01.toByte(), //   USAGE (Pointer)
        0xa1.toByte(), 0x00.toByte(), //   COLLECTION (Physical)
        0x85.toByte(), 0x01.toByte(), //     REPORT_ID (1)
        
        // Buttons: Left, Right, Middle, Back, Forward
        0x05.toByte(), 0x09.toByte(), //     USAGE_PAGE (Button)
        0x19.toByte(), 0x01.toByte(), //     USAGE_MINIMUM (Button 1)
        0x29.toByte(), 0x05.toByte(), //     USAGE_MAXIMUM (Button 5)
        0x15.toByte(), 0x00.toByte(), //     LOGICAL_MINIMUM (0)
        0x25.toByte(), 0x01.toByte(), //     LOGICAL_MAXIMUM (1)
        0x95.toByte(), 0x05.toByte(), //     REPORT_COUNT (5)
        0x75.toByte(), 0x01.toByte(), //     REPORT_SIZE (1)
        0x81.toByte(), 0x02.toByte(), //     INPUT (Data,Var,Abs)
        
        // Padding (3 bits to complete the first byte)
        0x95.toByte(), 0x01.toByte(), //     REPORT_COUNT (1)
        0x75.toByte(), 0x03.toByte(), //     REPORT_SIZE (3)
        0x81.toByte(), 0x03.toByte(), //     INPUT (Cnst,Var,Abs)
        
        // X, Y Relative Displacement
        0x05.toByte(), 0x01.toByte(), //     USAGE_PAGE (Generic Desktop)
        0x09.toByte(), 0x30.toByte(), //     USAGE (X)
        0x09.toByte(), 0x31.toByte(), //     USAGE (Y)
        0x15.toByte(), 0x81.toByte(), //     LOGICAL_MINIMUM (-127)
        0x25.toByte(), 0x7f.toByte(), //     LOGICAL_MAXIMUM (127)
        0x75.toByte(), 0x08.toByte(), //     REPORT_SIZE (8)
        0x95.toByte(), 0x02.toByte(), //     REPORT_COUNT (2)
        0x81.toByte(), 0x06.toByte(), //     INPUT (Data,Var,Rel)
        
        // Wheel Scroll
        0x09.toByte(), 0x38.toByte(), //     USAGE (Wheel)
        0x15.toByte(), 0x81.toByte(), //     LOGICAL_MINIMUM (-127)
        0x25.toByte(), 0x7f.toByte(), //     LOGICAL_MAXIMUM (127)
        0x75.toByte(), 0x08.toByte(), //     REPORT_SIZE (8)
        0x95.toByte(), 0x01.toByte(), //     REPORT_COUNT (1)
        0x81.toByte(), 0x06.toByte(), //     INPUT (Data,Var,Rel)
        
        0xc0.toByte(),                //   END_COLLECTION
        0xc0.toByte(),                // END_COLLECTION

        0x05.toByte(), 0x01.toByte(), // USAGE_PAGE (Generic Desktop)
        0x09.toByte(), 0x06.toByte(), // USAGE (Keyboard)
        0xa1.toByte(), 0x01.toByte(), // COLLECTION (Application)
        0x85.toByte(), 0x02.toByte(), //   REPORT_ID (2)

        // Modifier keys: Left Ctrl through Right GUI
        0x05.toByte(), 0x07.toByte(), //   USAGE_PAGE (Keyboard)
        0x19.toByte(), 0xe0.toByte(), //   USAGE_MINIMUM (Keyboard LeftControl)
        0x29.toByte(), 0xe7.toByte(), //   USAGE_MAXIMUM (Keyboard Right GUI)
        0x15.toByte(), 0x00.toByte(), //   LOGICAL_MINIMUM (0)
        0x25.toByte(), 0x01.toByte(), //   LOGICAL_MAXIMUM (1)
        0x75.toByte(), 0x01.toByte(), //   REPORT_SIZE (1)
        0x95.toByte(), 0x08.toByte(), //   REPORT_COUNT (8)
        0x81.toByte(), 0x02.toByte(), //   INPUT (Data,Var,Abs)

        // Reserved byte
        0x95.toByte(), 0x01.toByte(), //   REPORT_COUNT (1)
        0x75.toByte(), 0x08.toByte(), //   REPORT_SIZE (8)
        0x81.toByte(), 0x03.toByte(), //   INPUT (Cnst,Var,Abs)

        // LED output report: Num Lock through Kana
        0x95.toByte(), 0x05.toByte(), //   REPORT_COUNT (5)
        0x75.toByte(), 0x01.toByte(), //   REPORT_SIZE (1)
        0x05.toByte(), 0x08.toByte(), //   USAGE_PAGE (LEDs)
        0x19.toByte(), 0x01.toByte(), //   USAGE_MINIMUM (Num Lock)
        0x29.toByte(), 0x05.toByte(), //   USAGE_MAXIMUM (Kana)
        0x91.toByte(), 0x02.toByte(), //   OUTPUT (Data,Var,Abs)

        // LED output padding
        0x95.toByte(), 0x01.toByte(), //   REPORT_COUNT (1)
        0x75.toByte(), 0x03.toByte(), //   REPORT_SIZE (3)
        0x91.toByte(), 0x03.toByte(), //   OUTPUT (Cnst,Var,Abs)

        // Six simultaneous key slots
        0x95.toByte(), 0x06.toByte(), //   REPORT_COUNT (6)
        0x75.toByte(), 0x08.toByte(), //   REPORT_SIZE (8)
        0x15.toByte(), 0x00.toByte(), //   LOGICAL_MINIMUM (0)
        0x25.toByte(), 0x65.toByte(), //   LOGICAL_MAXIMUM (101)
        0x05.toByte(), 0x07.toByte(), //   USAGE_PAGE (Keyboard)
        0x19.toByte(), 0x00.toByte(), //   USAGE_MINIMUM (Reserved)
        0x29.toByte(), 0x65.toByte(), //   USAGE_MAXIMUM (Keyboard Application)
        0x81.toByte(), 0x00.toByte(), //   INPUT (Data,Ary,Abs)
        0xc0.toByte()                 // END_COLLECTION
    )

    private val hidCallback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            super.onAppStatusChanged(pluggedDevice, registered)
            isAppRegistered = registered
            isAppRegistrationPending = false
            sendHidDebugEvent("appRegistration", "registered=$registered")
            if (registered) {
                connectPendingDevice()
            } else {
                pendingConnectionAddress = null
            }
            runOnUiThread {
                channel?.invokeMethod("onAppStatusChanged", registered)
            }
        }

        override fun onConnectionStateChanged(device: BluetoothDevice?, state: Int) {
            super.onConnectionStateChanged(device, state)
            if (state != BluetoothProfile.STATE_CONNECTING) {
                connectionAttemptId++
            }
            currentConnectionState = state
            if (state == BluetoothProfile.STATE_CONNECTED) {
                connectedDevice = device
                currentProtocol = BluetoothHidDevice.PROTOCOL_REPORT_MODE
            } else if (state == BluetoothProfile.STATE_DISCONNECTED) {
                if (connectedDevice?.address == device?.address) {
                    connectedDevice = null
                }
            }
            sendHidDebugEvent("connection", "state=$state device=${device?.name ?: ""}")
            runOnUiThread {
                channel?.invokeMethod("onConnectionStateChanged", mapOf(
                    "state" to state,
                    "deviceName" to (device?.name ?: ""),
                    "deviceAddress" to (device?.address ?: "")
                ))
            }
        }

        override fun onGetReport(device: BluetoothDevice?, type: Byte, id: Byte, bufferSize: Int) {
            super.onGetReport(device, type, id, bufferSize)
            sendHidDebugEvent("getReport", "type=${type.toInt()} id=${id.toInt()} size=$bufferSize")
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || device == null) {
                return
            }

            try {
                if (!hasBluetoothConnectPermission()) {
                    return
                }

                val reportData = when (id.toInt()) {
                    0 -> ByteArray(8) // Boot keyboard report.
                    1 -> ByteArray(4) // Mouse: buttons, dx, dy, wheel.
                    2 -> ByteArray(8) // Keyboard: modifiers, reserved, six key slots.
                    else -> null
                }

                if (reportData == null) {
                    hidDevice?.reportError(device, BluetoothHidDevice.ERROR_RSP_INVALID_RPT_ID)
                } else {
                    hidDevice?.replyReport(device, type, id, reportData)
                }
            } catch (e: SecurityException) {
                e.printStackTrace()
            }
        }

        override fun onSetReport(device: BluetoothDevice?, type: Byte, id: Byte, data: ByteArray?) {
            super.onSetReport(device, type, id, data)
            sendHidDebugEvent("setReport", "type=${type.toInt()} id=${id.toInt()} bytes=${data?.size ?: 0}")
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || device == null) {
                return
            }

            try {
                if (hasBluetoothConnectPermission()) {
                    hidDevice?.reportError(device, BluetoothHidDevice.ERROR_RSP_SUCCESS)
                }
            } catch (e: SecurityException) {
                e.printStackTrace()
            }
        }

        override fun onSetProtocol(device: BluetoothDevice?, protocol: Byte) {
            super.onSetProtocol(device, protocol)
            currentProtocol = protocol
            val protocolName = if (protocol == BluetoothHidDevice.PROTOCOL_BOOT_MODE) {
                "boot"
            } else {
                "report"
            }
            sendHidDebugEvent("setProtocol", protocolName)
        }
    }

    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                if (state == BluetoothAdapter.STATE_ON) {
                    isHidProfileAvailable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                    initHidProfile()
                }
                runOnUiThread {
                    channel?.invokeMethod("onBluetoothStateChanged", state == BluetoothAdapter.STATE_ON)
                }
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter

        registerReceiver(bluetoothReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
        initHidProfile()
    }

    override fun onDestroy() {
        unregisterReceiver(bluetoothReceiver)
        unregisterHidApp()
        closeHidProfile()
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (hidDevice == null && isHidProfileAvailable) {
                initHidProfile()
            } else if (!isAppRegistered) {
                registerHidApp()
            } else {
                syncConnectionStateFromProfile()
            }
        }
    }

    private fun initHidProfile() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P ||
            hidDevice != null ||
            isHidProfileInitializationPending ||
            !isHidProfileAvailable ||
            bluetoothAdapter?.isEnabled != true ||
            !hasBluetoothConnectPermission()
        ) {
            return
        }

        isHidProfileInitializationPending = true
        val accepted = bluetoothAdapter?.getProfileProxy(
            this,
            object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
                    if (profile == BluetoothProfile.HID_DEVICE) {
                        hidProfileInitializationAttemptId++
                        isHidProfileInitializationPending = false
                        setHidProfileAvailable(true)
                        hidDevice = proxy as BluetoothHidDevice
                        registerHidApp()
                    }
                }

                override fun onServiceDisconnected(profile: Int) {
                    if (profile == BluetoothProfile.HID_DEVICE) {
                        hidProfileInitializationAttemptId++
                        isHidProfileInitializationPending = false
                        hidDevice = null
                        isAppRegistered = false
                        isAppRegistrationPending = false
                    }
                }
            },
            BluetoothProfile.HID_DEVICE
        ) == true

        if (!accepted) {
            hidProfileInitializationAttemptId++
            isHidProfileInitializationPending = false
            setHidProfileAvailable(false)
            return
        }

        val attemptId = ++hidProfileInitializationAttemptId
        mainHandler.postDelayed({
            if (attemptId != hidProfileInitializationAttemptId ||
                !isHidProfileInitializationPending ||
                hidDevice != null
            ) {
                return@postDelayed
            }

            isHidProfileInitializationPending = false
            pendingConnectionAddress = null
            connectedDevice = null
            currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
            setHidProfileAvailable(false)
            sendConnectionStateChanged(null, BluetoothProfile.STATE_DISCONNECTED)
        }, 5_000L)
    }

    private fun setHidProfileAvailable(available: Boolean) {
        if (isHidProfileAvailable == available) {
            return
        }
        isHidProfileAvailable = available
        sendHidDebugEvent("hidProfile", "available=$available")
        runOnUiThread {
            channel?.invokeMethod("onHidProfileAvailabilityChanged", available)
        }
    }

    private fun closeHidProfile() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && hidDevice != null) {
            bluetoothAdapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, hidDevice)
            hidDevice = null
        }
        hidProfileInitializationAttemptId++
        isHidProfileInitializationPending = false
    }

    private fun registerHidApp() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            hidDevice != null &&
            !isAppRegistered &&
            !isAppRegistrationPending
        ) {
            val sdp = BluetoothHidDeviceAppSdpSettings(
                "AndPad Touchpad",
                "Virtual Bluetooth Mouse and Keyboard",
                "AndPad",
                BluetoothHidDevice.SUBCLASS1_COMBO,
                HID_DESCRIPTOR
            )
            val executor = Executors.newSingleThreadExecutor()
            try {
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                    isAppRegistrationPending = hidDevice?.registerApp(
                        sdp,
                        null,
                        null,
                        executor,
                        hidCallback
                    ) == true
                    sendHidDebugEvent(
                        "registerApp",
                        "accepted=$isAppRegistrationPending"
                    )
                }
            } catch (e: SecurityException) {
                isAppRegistrationPending = false
                e.printStackTrace()
            }
        }
    }

    private fun unregisterHidApp() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && hidDevice != null && isAppRegistered) {
            try {
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                    hidDevice?.unregisterApp()
                    isAppRegistered = false
                    isAppRegistrationPending = false
                }
            } catch (e: SecurityException) {
                e.printStackTrace()
            }
        }
    }

    private fun resetHidProfile() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return
        }

        unregisterHidApp()
        closeHidProfile()
        connectedDevice = null
        pendingConnectionAddress = null
        connectionAttemptId++
        currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
        currentProtocol = BluetoothHidDevice.PROTOCOL_REPORT_MODE
        isAppRegistered = false
        isHidProfileAvailable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
        mainHandler.postDelayed({
            initHidProfile()
        }, 500)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isBluetoothSupported" -> {
                result.success(bluetoothAdapter != null)
            }
            "isHidSupported" -> {
                result.success(isHidProfileAvailable)
            }
            "isBluetoothEnabled" -> {
                result.success(bluetoothAdapter?.isEnabled ?: false)
            }
            "makeDiscoverable" -> {
                makeDiscoverable(result)
            }
            "openBluetoothSettings" -> {
                openBluetoothSettings(result)
            }
            "checkPermissions" -> {
                val granted = checkPermissions()
                result.success(granted)
            }
            "requestPermissions" -> {
                requestPermissions(result)
            }
            "getPairedDevices" -> {
                getPairedDevices(result)
            }
            "connectDevice" -> {
                val address = call.argument<String>("address")
                if (address != null) {
                    connectDevice(address, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Address cannot be null", null)
                }
            }
            "disconnectDevice" -> {
                disconnectDevice(result)
            }
            "sendMouseEvent" -> {
                val buttons = call.argument<Int>("buttons") ?: 0
                val dx = call.argument<Int>("dx") ?: 0
                val dy = call.argument<Int>("dy") ?: 0
                val wheel = call.argument<Int>("wheel") ?: 0
                val success = sendMouseEvent(buttons.toByte(), dx.toByte(), dy.toByte(), wheel.toByte())
                result.success(success)
            }
            "sendKeyboardEvent" -> {
                val modifiers = call.argument<Int>("modifiers") ?: 0
                val keyCodes = call.argument<List<Int>>("keyCodes") ?: emptyList()
                val success = sendKeyboardEvent(modifiers.toByte(), keyCodes)
                result.success(success)
            }
            "getConnectionState" -> {
                syncConnectionStateFromProfile()
                result.success(currentConnectionState)
            }
            "registerApp" -> {
                registerHidApp()
                result.success(true)
            }
            "resetHidProfile" -> {
                resetHidProfile()
                result.success(true)
            }
            "unregisterApp" -> {
                unregisterHidApp()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun checkPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        permissionResult = result
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE),
                PERMISSION_REQUEST_CODE
            )
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                PERMISSION_REQUEST_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            if (allGranted) {
                initHidProfile()
            }
            permissionResult?.success(allGranted)
            permissionResult = null
        }
    }

    private fun makeDiscoverable(result: MethodChannel.Result) {
        val discoverableIntent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).apply {
            putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120)
        }
        try {
            startActivity(discoverableIntent)
            result.success(true)
        } catch (e: Exception) {
            result.error("DISCOVERABLE_FAILED", e.message, null)
        }
    }

    private fun openBluetoothSettings(result: MethodChannel.Result) {
        try {
            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
            result.success(true)
        } catch (e: Exception) {
            result.error("OPEN_SETTINGS_FAILED", e.message, null)
        }
    }

    private fun getPairedDevices(result: MethodChannel.Result) {
        if (bluetoothAdapter == null) {
            result.error("BLUETOOTH_NOT_SUPPORTED", "Bluetooth is not supported on this device", null)
            return
        }
        try {
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                val bondedDevices = bluetoothAdapter?.bondedDevices
                val devicesList = bondedDevices?.map { device ->
                    mapOf(
                        "name" to (device.name ?: "Unknown Device"),
                        "address" to device.address
                    )
                } ?: emptyList()
                result.success(devicesList)
            } else {
                result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
            }
        } catch (e: SecurityException) {
            result.error("SECURITY_EXCEPTION", e.message, null)
        }
    }

    private fun hasBluetoothConnectPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED ||
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S
    }

    private fun syncConnectionStateFromProfile() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || hidDevice == null) {
            currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
            connectedDevice = null
            return
        }

        try {
            if (!hasBluetoothConnectPermission()) {
                return
            }

            val actualConnectedDevice = hidDevice?.connectedDevices?.firstOrNull()
            if (actualConnectedDevice != null) {
                connectedDevice = actualConnectedDevice
                currentConnectionState = BluetoothProfile.STATE_CONNECTED
            } else if (currentConnectionState == BluetoothProfile.STATE_CONNECTED) {
                currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
                connectedDevice = null
                runOnUiThread {
                    channel?.invokeMethod("onConnectionStateChanged", mapOf(
                        "state" to BluetoothProfile.STATE_DISCONNECTED,
                        "deviceName" to "",
                        "deviceAddress" to ""
                    ))
                }
            }
        } catch (e: SecurityException) {
            e.printStackTrace()
        }
    }

    private fun connectDevice(address: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error("HID_NOT_SUPPORTED", "HID is not supported", null)
            return
        }
        if (!isHidProfileAvailable) {
            result.error("HID_NOT_SUPPORTED", "Bluetooth HID Device service is unavailable", null)
            return
        }
        if (!hasBluetoothConnectPermission()) {
            result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
            return
        }
        if (bluetoothAdapter?.getRemoteDevice(address) == null) {
            result.error("DEVICE_NOT_FOUND", "Device not found for address $address", null)
            return
        }

        pendingConnectionAddress = address
        currentConnectionState = BluetoothProfile.STATE_CONNECTING

        if (hidDevice == null) {
            initHidProfile()
            if (!isHidProfileAvailable) {
                pendingConnectionAddress = null
                currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
                result.error("HID_NOT_SUPPORTED", "Bluetooth HID Device service is unavailable", null)
                return
            }
            sendHidDebugEvent("connect", "queued while HID profile initializes")
            result.success(true)
            return
        }
        if (!isAppRegistered) {
            registerHidApp()
            if (!isAppRegistered && !isAppRegistrationPending) {
                pendingConnectionAddress = null
                currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
                result.success(false)
                return
            }
            sendHidDebugEvent("connect", "queued while HID app registers")
            result.success(true)
            return
        }

        result.success(connectPendingDevice())
    }

    private fun connectPendingDevice(): Boolean {
        val address = pendingConnectionAddress ?: return false
        val profile = hidDevice ?: return false
        val device = bluetoothAdapter?.getRemoteDevice(address) ?: run {
            pendingConnectionAddress = null
            return false
        }

        return try {
            if (!hasBluetoothConnectPermission()) {
                false
            } else {
                val alreadyConnected = profile.connectedDevices.any { it.address == address }
                val accepted = alreadyConnected || profile.connect(device)
                sendHidDebugEvent(
                    "connect",
                    "accepted=$accepted alreadyConnected=$alreadyConnected"
                )
                if (accepted) {
                    pendingConnectionAddress = null
                    connectedDevice = device
                    currentConnectionState = if (alreadyConnected) {
                        BluetoothProfile.STATE_CONNECTED
                    } else {
                        BluetoothProfile.STATE_CONNECTING
                    }
                    if (!alreadyConnected) {
                        scheduleConnectionTimeout(device)
                    }
                } else {
                    currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
                }
                accepted
            }
        } catch (e: SecurityException) {
            currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
            false
        }
    }

    private fun scheduleConnectionTimeout(device: BluetoothDevice) {
        val attemptId = ++connectionAttemptId
        mainHandler.postDelayed({
            if (attemptId != connectionAttemptId ||
                currentConnectionState != BluetoothProfile.STATE_CONNECTING
            ) {
                return@postDelayed
            }

            try {
                val connected = hasBluetoothConnectPermission() &&
                    hidDevice?.connectedDevices?.any { it.address == device.address } == true
                if (connected) {
                    connectedDevice = device
                    currentConnectionState = BluetoothProfile.STATE_CONNECTED
                    sendConnectionStateChanged(device, BluetoothProfile.STATE_CONNECTED)
                } else {
                    if (hasBluetoothConnectPermission()) {
                        hidDevice?.disconnect(device)
                    }
                    connectedDevice = null
                    currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
                    sendHidDebugEvent("connectTimeout", "device=${device.name ?: ""}")
                    sendConnectionStateChanged(device, BluetoothProfile.STATE_DISCONNECTED)
                }
            } catch (e: SecurityException) {
                connectedDevice = null
                currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
                sendConnectionStateChanged(device, BluetoothProfile.STATE_DISCONNECTED)
            }
        }, connectionTimeoutMs)
    }

    private fun sendConnectionStateChanged(device: BluetoothDevice?, state: Int) {
        runOnUiThread {
            channel?.invokeMethod("onConnectionStateChanged", mapOf(
                "state" to state,
                "deviceName" to (device?.name ?: ""),
                "deviceAddress" to (device?.address ?: "")
            ))
        }
    }

    private fun disconnectDevice(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || hidDevice == null) {
            result.error("HID_NOT_SUPPORTED", "HID is not supported or profile is not initialized", null)
            return
        }
        val device = connectedDevice ?: hidDevice?.connectedDevices?.firstOrNull()
        if (device == null) {
            result.success(true) // already disconnected
            return
        }
        try {
            if (hasBluetoothConnectPermission()) {
                val success = hidDevice?.disconnect(device) ?: false
                if (success) {
                    connectedDevice = null
                    currentConnectionState = BluetoothProfile.STATE_DISCONNECTING
                }
                result.success(success)
            } else {
                result.error("PERMISSION_DENIED", "BLUETOOTH_CONNECT permission is required", null)
            }
        } catch (e: SecurityException) {
            result.error("SECURITY_EXCEPTION", e.message, null)
        }
    }

    private fun sendMouseEvent(buttons: Byte, dx: Byte, dy: Byte, wheel: Byte): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || hidDevice == null) {
            return false
        }
        return try {
            if (hasBluetoothConnectPermission()) {
                val actualDevice = hidDevice?.connectedDevices?.firstOrNull()
                val device = actualDevice ?: connectedDevice ?: return false
                if (actualDevice == null && currentConnectionState == BluetoothProfile.STATE_CONNECTED) {
                    currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
                    connectedDevice = null
                    runOnUiThread {
                        channel?.invokeMethod("onConnectionStateChanged", mapOf(
                            "state" to BluetoothProfile.STATE_DISCONNECTED,
                            "deviceName" to "",
                            "deviceAddress" to ""
                        ))
                    }
                    return false
                }
                val reportData = byteArrayOf(buttons, dx, dy, wheel)
                val sent = hidDevice?.sendReport(device, 1, reportData) ?: false
                if (!sent) {
                    currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
                    connectedDevice = null
                    runOnUiThread {
                        channel?.invokeMethod("onConnectionStateChanged", mapOf(
                            "state" to BluetoothProfile.STATE_DISCONNECTED,
                            "deviceName" to "",
                            "deviceAddress" to ""
                        ))
                    }
                }
                sent
            } else {
                false
            }
        } catch (e: SecurityException) {
            false
        }
    }

    private fun sendKeyboardEvent(modifiers: Byte, keyCodes: List<Int>): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || hidDevice == null) {
            return false
        }
        return try {
            if (hasBluetoothConnectPermission()) {
                val actualDevice = hidDevice?.connectedDevices?.firstOrNull()
                val device = actualDevice ?: connectedDevice ?: return false
                if (actualDevice == null && currentConnectionState == BluetoothProfile.STATE_CONNECTED) {
                    currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
                    connectedDevice = null
                    runOnUiThread {
                        channel?.invokeMethod("onConnectionStateChanged", mapOf(
                            "state" to BluetoothProfile.STATE_DISCONNECTED,
                            "deviceName" to "",
                            "deviceAddress" to ""
                        ))
                    }
                    return false
                }

                val reportData = ByteArray(8)
                reportData[0] = modifiers
                keyCodes.take(6).forEachIndexed { index, keyCode ->
                    reportData[index + 2] = keyCode.toByte()
                }
                val reportId = if (currentProtocol == BluetoothHidDevice.PROTOCOL_BOOT_MODE) {
                    0
                } else {
                    2
                }
                val sent = hidDevice?.sendReport(device, reportId, reportData) ?: false
                sendHidDebugEvent(
                    "sendKeyboard",
                    "reportId=$reportId protocol=${currentProtocol.toInt()} sent=$sent data=${reportData.joinToString(",") { it.toUByte().toString(16) }}"
                )
                if (!sent) {
                    currentConnectionState = BluetoothProfile.STATE_DISCONNECTED
                    connectedDevice = null
                    runOnUiThread {
                        channel?.invokeMethod("onConnectionStateChanged", mapOf(
                            "state" to BluetoothProfile.STATE_DISCONNECTED,
                            "deviceName" to "",
                            "deviceAddress" to ""
                        ))
                    }
                }
                sent
            } else {
                false
            }
        } catch (e: SecurityException) {
            false
        }
    }
}
