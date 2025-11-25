import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../home.dart';
import '../devices.dart';
import '../chatbot.dart';
import '../community.dart';
import '../login_page.dart';
import '../theme/rotala_brand.dart';
import '../ble/ble_manager.dart';

class AppScaffold extends StatefulWidget {
  final int currentIndex;
  final String title;
  final Widget body;

  const AppScaffold({
    super.key,
    required this.currentIndex,
    required this.title,
    required this.body,
  });

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _bleSheetOpen = false;

  Future<_DeviceStatus> _fetchDeviceStatus() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return const _DeviceStatus.unknown();

      final rows = await client
          .from('devices')
          .select('connected,last_seen')
          .eq('user_id', uid)
          .order('last_seen', ascending: false)
          .limit(1);

      if (rows is List && rows.isNotEmpty) {
        final r = rows.first as Map<String, dynamic>;
        final connected = (r['connected'] == true);
        final lastSeenStr = r['last_seen']?.toString();
        final lastSeen = DateTime.tryParse(lastSeenStr ?? '');
        final online = connected ||
            (lastSeen != null &&
                DateTime.now().difference(lastSeen).inMinutes <= 5);

        return _DeviceStatus(online: online, lastSeen: lastSeen);
      }

      return const _DeviceStatus.unknown();
    } catch (_) {
      return const _DeviceStatus.unknown();
    }
  }

  void _goTab(int index) {
    if (index == widget.currentIndex) {
      return;
    }

    if (index == 2 || index == 3) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coming soon'),
          duration: Duration(milliseconds: 800),
        ),
      );
      return;
    }

    HapticFeedback.selectionClick();

    Widget page;
    switch (index) {
      case 0:
        page = const HomePage();
        break;
      case 1:
        page = const DevicesPage();
        break;
      default:
        page = const HomePage();
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 260),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          final offsetAnimation = Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved);
          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
      ),
    );
  }

  Future<void> _signOut() async {
  HapticFeedback.mediumImpact();

  // Close the drawer if open, but don't crash if it cannot pop
  if (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }

  try {
    await Supabase.instance.client.auth.signOut();
  } catch (_) {
    // ignore for now, still send user to login
  }

  // After an await, always make sure the State is still mounted
  if (!mounted) return;

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginPage()),
    (route) => false,
  );
}


  Widget _comingSoonLabel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6F4D),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Soon',
        style: TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _openBleSheet() {
    if (_bleSheetOpen) return;
    _bleSheetOpen = true;

    final ble = BleManager.I;
    StreamSubscription<DiscoveredDevice>? scanSub;
    StreamSubscription<List<int>>? notifSub;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1f2937),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        bool busy = false;
        String status =
            ble.isConnected ? 'Device connected' : 'No device connected';
        List<DiscoveredDevice> devices = [];

        Future<void> startScan(StateSetter setSheet) async {
          if (busy) return;

          setSheet(() {
            busy = true;
            status = 'Requesting permissions…';
          });

          final ok = await ble.ensurePermissions();
          if (!ok) {
            setSheet(() {
              busy = false;
              status = 'Bluetooth permission denied';
            });
            return;
          }

          setSheet(() {
            status = 'Scanning for devices…';
            devices = [];
          });

          await scanSub?.cancel();
          scanSub = ble.startScan().listen((d) {
            setSheet(() {
              if (!devices.any((x) => x.id == d.id)) {
                devices.add(d);
              }
            });
          }, onError: (e) {
            setSheet(() {
              busy = false;
              status = 'Scan error: $e';
            });
          });
        }

        Future<void> connectTo(
          DiscoveredDevice d,
          StateSetter setSheet,
        ) async {
          setSheet(() {
            busy = true;
            status = 'Connecting to ${d.name.isEmpty ? d.id : d.name}…';
          });

          await scanSub?.cancel();
          await ble.connect(d);

          if (ble.isConnected) {
            setSheet(() {
              busy = false;
              status = 'Device connected';
            });

            await notifSub?.cancel();
            notifSub = ble.notifications().listen((bytes) {
              final text = String.fromCharCodes(bytes);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('From device: $text')),
                );
              }
            });
          } else {
            setSheet(() {
              busy = false;
              status = 'Failed to connect';
            });
          }
        }

        Future<void> disconnect(StateSetter setSheet) async {
          await ble.disconnect();
          await scanSub?.cancel();
          await notifSub?.cancel();
          setSheet(() {
            busy = false;
            status = 'Disconnected';
          });
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              final connected = ble.isConnected;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    'AquaSpec device',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (busy) ...[
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: CircularProgressIndicator(),
                    ),
                  ],
                  if (!connected) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const Text(
                        'Nearby devices',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (devices.isEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            const Icon(Icons.search, color: Colors.white70),
                        title: const Text(
                          'No devices found yet',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: const Text(
                          'Turn your AquaSpec on and scan below',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          itemCount: devices.length,
                          itemBuilder: (ctx, index) {
                            final d = devices[index];
                            final name = d.name.isEmpty ? d.id : d.name;
                            return Card(
                              color: const Color(0xFF111827),
                              child: ListTile(
                                title: Text(
                                  name,
                                  style:
                                      const TextStyle(color: Colors.white),
                                ),
                                subtitle: Text(
                                  d.id,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: RotalaColors.teal,
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () => connectTo(d, setSheet),
                                  child: const Text(
                                    'Connect',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: RotalaColors.teal,
                        ),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text(
                          'Scan for devices',
                          style: TextStyle(fontSize: 14),
                        ),
                        onPressed: busy ? null : () => startScan(setSheet),
                      ),
                    ),
                  ] else ...[
                    Card(
                      color: const Color(0xFF111827),
                      child: const ListTile(
                        leading: Icon(
                          Icons.bluetooth_connected,
                          color: Colors.tealAccent,
                        ),
                        title: Text(
                          'Device connected',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          'Your AquaSpec is linked to this phone',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                        ),
                        icon: const Icon(Icons.link_off, size: 18),
                        label: const Text(
                          'Disconnect device',
                          style: TextStyle(fontSize: 14),
                        ),
                        onPressed: () => disconnect(setSheet),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    ).whenComplete(() async {
      _bleSheetOpen = false;
      await scanSub?.cancel();
      await notifSub?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0b1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0b1220),
        elevation: 0,
        leading: IconButton(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () {
            HapticFeedback.selectionClick();
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: Transform.translate(
          offset: const Offset(0, -4),
          child: Image.asset(
            'assets/brand/rotalanew2.png',
            height: 60,
            fit: BoxFit.contain,
          ),
        ),
        centerTitle: true,
        actions: [
          FutureBuilder<_DeviceStatus>(
            future: _fetchDeviceStatus(),
            builder: (context, snapshot) {
              final st = snapshot.data ?? const _DeviceStatus.unknown();
              final icon = st.online
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled;
              final color =
                  st.online ? RotalaColors.teal : Colors.white70;

              return IconButton(
                tooltip: st.online
                    ? 'Device connected'
                    : 'Connect your AquaSpec device',
                icon: Icon(icon, color: color),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  if (_bleSheetOpen) return;
                  _openBleSheet();
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF0b1220),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                color: const Color(0xFF111827),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/brand/rotalalink.png',
                      height: 35,
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white24),
              _DrawerItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: widget.currentIndex == 0,
                onTap: () => _goTab(0),
              ),
              _DrawerItem(
                icon: Icons.smart_toy_rounded,
                label: 'RALA',
                selected: widget.currentIndex == 2,
                comingSoon: true,
                onTap: () => _goTab(2),
              ),
              _DrawerItem(
                icon: Icons.groups_rounded,
                label: 'Community',
                selected: widget.currentIndex == 3,
                comingSoon: true,
                onTap: () => _goTab(3),
              ),
              const Spacer(),
              const Divider(height: 1, color: Colors.white24),
              ListTile(
                leading: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Log out',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: _signOut,
              ),
            ],
          ),
        ),
      ),
      body: widget.body,
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    this.comingSoon = false,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool comingSoon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? RotalaColors.teal : Colors.white70;
    final bg = selected ? const Color(0xFF111827) : Colors.transparent;

    return Material(
      color: bg,
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            if (comingSoon) ...[
              const SizedBox(width: 6),
              _comingSoonChip(),
            ],
          ],
        ),
        title: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop();
          onTap();
        },
      ),
    );
  }

  Widget _comingSoonChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6F4D),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Soon',
        style: TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _DeviceStatus {
  final bool online;
  final DateTime? lastSeen;

  const _DeviceStatus({required this.online, this.lastSeen});
  const _DeviceStatus.unknown()
      : online = false,
        lastSeen = null;
}
