// lib/ble/ble_manager.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

class BleManager {
  BleManager._();
  static final BleManager I = BleManager._();

  final _ble = FlutterReactiveBle();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;

  String? _deviceId;
  String? _deviceName;

  // Nordic UART UUIDs
  final Uuid serviceUuid = Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
  final Uuid rxCharUuid = Uuid.parse(
    "6E400002-B5A3-F393-E0A9-E50E24DCCA9E",
  ); // write
  final Uuid txCharUuid = Uuid.parse(
    "6E400003-B5A3-F393-E0A9-E50E24DCCA9E",
  ); // notify

  QualifiedCharacteristic? _tx; // notify from ESP32 -> app
  QualifiedCharacteristic? _rx; // write from app   -> ESP32

  // -------- Permissions --------
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;

    // IMPORTANT: use a LIST, not a Set, so .request() exists.
    final statuses =
        await <Permission>[
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          // Some Android 10/11 devices still require location for scanning:
          Permission.locationWhenInUse,
        ].request();

    return statuses.values.every((s) => s.isGranted);
  }

  // -------- Scanning (unfiltered; we filter in UI) --------
  Stream<DiscoveredDevice> startScan() {
    _scanSub?.cancel();
    final controller = StreamController<DiscoveredDevice>.broadcast();

    _scanSub = _ble
        .scanForDevices(
          withServices: const [], // all devices
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .listen(controller.add, onError: controller.addError);

    controller.onCancel = () async => await _scanSub?.cancel();
    return controller.stream;
  }

  Future<void> stopScan() async => _scanSub?.cancel();

  // -------- Single connection --------
  Future<void> connect(DiscoveredDevice device) async {
    await disconnect(); // make sure only one at a time

    _deviceId = null;
    _deviceName = null;
    _tx = null;
    _rx = null;

    _connSub = _ble
        .connectToDevice(
          id: device.id,
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          (update) async {
            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                _deviceId = device.id;
                _deviceName = device.name;

                // Set up characteristics directly (we know the UUIDs)
                _tx = QualifiedCharacteristic(
                  deviceId: device.id,
                  serviceId: serviceUuid,
                  characteristicId: txCharUuid,
                );
                _rx = QualifiedCharacteristic(
                  deviceId: device.id,
                  serviceId: serviceUuid,
                  characteristicId: rxCharUuid,
                );

                // Ask for a larger MTU (ESP32 negotiated to 517 per your logs)
                try {
                  final mtu = await _ble.requestMtu(
                    deviceId: device.id,
                    mtu: 247,
                  );
                  if (kDebugMode) print('MTU set to $mtu');
                } catch (_) {}
                break;

              case DeviceConnectionState.disconnected:
                _deviceId = null;
                _deviceName = null;
                _tx = null;
                _rx = null;
                break;

              default:
                break;
            }
          },
          onError: (e) {
            if (kDebugMode) print('connect error: $e');
            _deviceId = null;
            _deviceName = null;
            _tx = null;
            _rx = null;
          },
        );
  }

  Future<void> disconnect() async {
    await _connSub?.cancel();
    _connSub = null;
    _deviceId = null;
    _deviceName = null;
    _tx = null;
    _rx = null;
  }

  bool get isConnected => _deviceId != null;
  String? get connectedId => _deviceId;
  String? get connectedName => _deviceName;

  // Notifications from ESP32 -> app
  Stream<List<int>> notifications() {
    final tx = _tx;
    if (tx == null) return const Stream.empty();
    return _ble.subscribeToCharacteristic(tx);
  }

  // Enable notifications (required for ESP32)
  Future<void> enableNotifications() async {
    final tx = _tx;
    if (tx == null) throw StateError("Not connected");
    await _ble.subscribeToCharacteristic(tx);
  }

  // Write text to ESP32 (UTF-8)
  Future<void> writeUtf8(String text) async {
    final rx = _rx;
    if (rx == null) throw StateError("Not connected");
    final data = Uint8List.fromList(text.codeUnits);
    // Use WithResponse for reliability while we debug
    await _ble.writeCharacteristicWithResponse(rx, value: data);
  }
}
