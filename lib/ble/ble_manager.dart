// lib/ble/ble_manager.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

  // Nordic UART-style UUIDs
  final Uuid serviceUuid =
  Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
  final Uuid rxCharUuid =
  Uuid.parse("6E400002-B5A3-F393-E0A9-E50E24DCCA9E"); // write
  final Uuid txCharUuid =
  Uuid.parse("6E400003-B5A3-F393-E0A9-E50E24DCCA9E"); // notify

  QualifiedCharacteristic? _tx; // notify from ESP32 -> app
  QualifiedCharacteristic? _rx; // write from app -> ESP32

  // -------- Permissions --------
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;

    // Android 12+ BLE perms
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();

    // On Android <= 11 scanning needs location
    if (await Permission.locationWhenInUse.isDenied) {
      await Permission.locationWhenInUse.request();
    }

    return scan.isGranted && connect.isGranted;
  }

  // -------- Scanning --------
  Stream<DiscoveredDevice> startScan() {
    _scanSub?.cancel();
    final controller = StreamController<DiscoveredDevice>.broadcast();

    _scanSub = _ble
        .scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    )
        .listen(controller.add, onError: controller.addError);

    controller.onCancel = () async => await _scanSub?.cancel();
    return controller.stream;
  }

  Future<void> stopScan() async => _scanSub?.cancel();

  // -------- Single connection --------
  Future<void> connect(DiscoveredDevice device) async {
    await disconnect(); // enforce 1-at-a-time

    _deviceId = null;
    _deviceName = null;

    _connSub = _ble
        .connectToDevice(
      id: device.id,
      connectionTimeout: const Duration(seconds: 10),
    )
        .listen((update) async {
      if (update.connectionState == DeviceConnectionState.connected) {
        _deviceId = device.id;
        _deviceName = device.name;

        // Service discovery (legacy API that works across versions)
        // ignore: deprecated_member_use
        final List<DiscoveredService> services =
        await _ble.discoverServices(device.id);

        for (final s in services) {
          if (s.serviceId == serviceUuid) {
            for (final c in s.characteristics) {
              if (c.characteristicId == txCharUuid) {
                _tx = QualifiedCharacteristic(
                  deviceId: device.id,
                  serviceId: serviceUuid,
                  characteristicId: txCharUuid,
                );
              } else if (c.characteristicId == rxCharUuid) {
                _rx = QualifiedCharacteristic(
                  deviceId: device.id,
                  serviceId: serviceUuid,
                  characteristicId: rxCharUuid,
                );
              }
            }
          }
        }
      } else if (update.connectionState ==
          DeviceConnectionState.disconnected) {
        _deviceId = null;
        _deviceName = null;
        _tx = null;
        _rx = null;
      }
    });
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
    if (_tx == null) return const Stream.empty();
    return _ble.subscribeToCharacteristic(_tx!);
  }

  // Write text to ESP32 (UTF8)
  Future<void> writeUtf8(String text) async {
    if (_rx == null) throw StateError("Not connected");
    final data = Uint8List.fromList(text.codeUnits);
    await _ble.writeCharacteristicWithoutResponse(_rx!, value: data);
  }
}
