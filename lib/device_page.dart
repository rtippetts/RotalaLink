// lib/device_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'ble/ble_manager.dart';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key});
  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final _ble = BleManager.I;
  StreamSubscription<DiscoveredDevice>? _scan;
  StreamSubscription<List<int>>? _notif;

  String _status = 'Disconnected';
  bool _busy = false;

  Future<void> _connectTap() async {
    if (_ble.isConnected || _busy) return;
    setState(() { _busy = true; _status = 'Requesting permissions…'; });

    final ok = await _ble.ensurePermissions();
    if (!ok) {
      setState(() { _busy = false; _status = 'Bluetooth permission denied'; });
      return;
    }

    setState(() => _status = 'Scanning…');
    _scan?.cancel();
    _scan = _ble.startScan().listen((d) async {
      // Got a device advertising our service: stop scan and connect
      await _ble.stopScan();
      setState(() => _status = 'Connecting to ${d.name.isEmpty ? d.id : d.name}…');
      await _ble.connect(d);

      if (_ble.isConnected) {
        setState(() { _busy = false; _status = 'Device connected'; });
        _notif?.cancel();
        _notif = _ble.notifications().listen((bytes) {
          final text = String.fromCharCodes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('From device: $text')),
            );
          }
        });
      } else {
        setState(() { _busy = false; _status = 'Failed to connect'; });
      }
    }, onError: (e) {
      setState(() { _busy = false; _status = 'Scan error: $e'; });
    });
  }

  Future<void> _disconnect() async {
    await _ble.disconnect();
    await _scan?.cancel();
    await _notif?.cancel();
    setState(() { _status = 'Disconnected'; _busy = false; });
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _ble.isConnected;

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Device'),
        actions: [
          if (connected)
            IconButton(
              icon: const Icon(Icons.link_off),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy) const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: CircularProgressIndicator(),
            ),
            Text(_status, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: connected ? null : _connectTap,
              child: const Text('Connect Device'),
            ),
            if (connected) ...[
              const SizedBox(height: 8),
              const Text('Connected ✔', style: TextStyle(color: Colors.greenAccent)),
            ],
          ],
        ),
      ),
    );
  }
}
