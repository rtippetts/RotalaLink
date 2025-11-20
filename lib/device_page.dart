// lib/device_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble/ble_manager.dart';
import 'widgets/app_scaffold.dart';

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

    setState(() {
      _busy = true;
      _status = 'Requesting permissions…';
    });

    final ok = await _ble.ensurePermissions();
    if (!ok) {
      setState(() {
        _busy = false;
        _status = 'Bluetooth permission denied';
      });
      return;
    }

    setState(() => _status = 'Scanning…');

    await _scan?.cancel();
    _scan = _ble.startScan().listen((d) async {
      await _ble.stopScan();

      setState(() {
        _status = 'Connecting to ${d.name.isEmpty ? d.id : d.name}…';
      });

      await _ble.connect(d);

      if (_ble.isConnected) {
        setState(() {
          _busy = false;
          _status = 'Device connected';
        });

        await _notif?.cancel();
        _notif = _ble.notifications().listen((bytes) {
          final text = String.fromCharCodes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('From device: $text')),
            );
          }
        });
      } else {
        setState(() {
          _busy = false;
          _status = 'Failed to connect';
        });
      }
    }, onError: (e) {
      setState(() {
        _busy = false;
        _status = 'Scan error: $e';
      });
    });
  }

  Future<void> _disconnect() async {
    await _ble.disconnect();
    await _scan?.cancel();
    await _notif?.cancel();
    if (!mounted) return;
    setState(() {
      _status = 'Disconnected';
      _busy = false;
    });
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _ble.isConnected;

    return AppScaffold(
      currentIndex: 1, // Devices tab
      title: 'Device',
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: CircularProgressIndicator(),
              ),
            Text(
              _status,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: connected ? null : _connectTap,
              child: const Text('Connect Device'),
            ),
            if (connected) ...[
              const SizedBox(height: 8),
              const Text(
                'Connected ✔',
                style: TextStyle(color: Colors.greenAccent),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _disconnect,
                child: const Text('Disconnect'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
