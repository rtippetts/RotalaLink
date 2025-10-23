// lib/ble/ble_manager_mock.dart
// Mock BLE manager for testing in web environment

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BleManagerMock {
  BleManagerMock._();
  static final BleManagerMock I = BleManagerMock._();

  final _ble = FlutterReactiveBle();
  final _random = Random();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;

  String? _deviceId;
  String? _deviceName;

  // Nordic UART UUIDs
  final Uuid serviceUuid = Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
  final Uuid rxCharUuid = Uuid.parse("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
  final Uuid txCharUuid = Uuid.parse("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

  QualifiedCharacteristic? _tx;
  QualifiedCharacteristic? _rx;

  // Mock device data
  final List<DiscoveredDevice> _mockDevices = [
    DiscoveredDevice(
      id: "AA:BB:CC:DD:EE:FF",
      name: "AquaSpec-Device-1",
      rssi: -45,
      serviceUuids: const [],
      manufacturerData: Uint8List(0),
      serviceData: const {},
    ),
    DiscoveredDevice(
      id: "11:22:33:44:55:66",
      name: "AquaSpec-Device-2",
      rssi: -67,
      serviceUuids: const [],
      manufacturerData: Uint8List(0),
      serviceData: const {},
    ),
  ];

  Future<bool> ensurePermissions() async {
    // Mock: always return true for web testing
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }

  Stream<DiscoveredDevice> startScan() {
    _scanSub?.cancel();
    final controller = StreamController<DiscoveredDevice>.broadcast();

    // Simulate scanning with mock devices
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_scanSub == null) {
        timer.cancel();
        return;
      }

      final device = _mockDevices[_random.nextInt(_mockDevices.length)];
      controller.add(device);

      // Stop after finding a few devices
      if (timer.tick >= 3) {
        timer.cancel();
      }
    });

    controller.onCancel = () async => await _scanSub?.cancel();
    return controller.stream;
  }

  Future<void> stopScan() async => _scanSub?.cancel();

  Future<void> connect(DiscoveredDevice device) async {
    await disconnect();

    _deviceId = device.id;
    _deviceName = device.name;
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

    // Simulate connection delay
    await Future.delayed(const Duration(seconds: 2));
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

  Stream<List<int>> notifications() {
    final tx = _tx;
    if (tx == null) return const Stream.empty();

    // Mock notifications - simulate device responses
    return Stream.periodic(const Duration(seconds: 5), (i) {
      final responses = [
        "WiFi credentials received. Connecting...\n",
        "WiFi connected successfully!\n",
        "Tank names set: 3\n",
        "Tank IDs set: 3\n",
        "Device name set: Living Room Probe\n",
        "Selected tank: tank-123\n",
        "Reading sent: T=25.3 pH=7.2 TDS=180\n",
      ];

      final response = responses[i % responses.length];
      return response.codeUnits;
    });
  }

  Future<void> writeUtf8(String text) async {
    final rx = _rx;
    if (rx == null) throw StateError("Not connected");

    // Mock: simulate sending command
    if (kDebugMode) {
      print('[MOCK BLE TX] ${text.replaceAll('\n', r'\n')}');
    }

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
