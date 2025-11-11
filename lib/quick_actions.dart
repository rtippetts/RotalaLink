import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QuickActionsCard extends StatelessWidget {
  const QuickActionsCard({
    super.key,
    required this.tankStream,
    required this.onOpenAlerts,
    required this.onAddReading,
    required this.greetingName,
  });

  final Stream<List<Map<String, dynamic>>> tankStream;
  final VoidCallback onOpenAlerts;
  final VoidCallback onAddReading;
  final String greetingName;

  Future<_DeviceStatus> _fetchDeviceStatus() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return const _DeviceStatus.unknown();
      final rows = await Supabase.instance.client
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

  int _countDueToday(List<Map<String, dynamic>> tanks) {
    int due = 0;
    for (final t in tanks) {
      final wt = (t['water_type'] ?? 'freshwater').toString();
      final cadence = wt == 'saltwater'
          ? const Duration(days: 3)
          : wt == 'brackish'
              ? const Duration(days: 5)
              : const Duration(days: 7);
      final lastStr = t['last_measurement_at']?.toString();
      DateTime last = DateTime.now().subtract(const Duration(days: 30));
      if (lastStr != null) {
        final parsed = DateTime.tryParse(lastStr);
        if (parsed != null) last = parsed;
      }
      final next = last.add(cadence);
      final now = DateTime.now();
      final sameDay = next.year == now.year &&
          next.month == now.month &&
          next.day == now.day;
      final overdue = next.isBefore(now) && !sameDay;
      if (sameDay || overdue) due += 1;
    }
    return due;
  }

  static String _fmtDateShort(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}"
        "/${d.month.toString().padLeft(2, '0')}"
        "/${d.day.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final name = greetingName.isEmpty ? 'there' : greetingName;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF122033),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting row
          Row(
            children: [
              const Icon(Icons.handshake_outlined,
                  color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Welcome back, $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Tasks summary
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: tankStream,
            builder: (context, snap) {
              final tanks = snap.data ?? const [];
              final due = _countDueToday(tanks);
              return Row(
                children: [
                  const Icon(Icons.waves_outlined,
                      color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      due == 0
                          ? 'All tanks look good today'
                          : '$due tank${due == 1 ? '' : 's'} need attention today',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),

          // Actions row
          Row(
            children: [
              // Alerts
              Expanded(
                child: ActionPill(
                  icon: Icons.notifications,
                  labelBuilder: (ctx) =>
                      AlertsCountBadge(onTap: onOpenAlerts),
                  onTap: onOpenAlerts,
                ),
              ),
              const SizedBox(width: 8),

              // Device status
              Expanded(
                child: FutureBuilder<_DeviceStatus>(
                  future: _fetchDeviceStatus(),
                  builder: (context, snap) {
                    final st = snap.data ?? const _DeviceStatus.unknown();
                    final online = st.online;
                    final icon =
                        online ? Icons.check_circle : Icons.portable_wifi_off;
                    final color =
                        online ? Colors.greenAccent : Colors.orangeAccent;
                    final text = online ? 'Device online' : 'Device offline';
                    return ActionPill(
                      icon: icon,
                      iconColor: color,
                      label: text,
                      onTap: () {},
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Add reading
              Expanded(
                child: ActionPill(
                  icon: Icons.add_chart,
                  label: 'Add reading',
                  onTap: onAddReading,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.icon,
    this.iconColor,
    this.label,
    this.labelBuilder,
    required this.onTap,
  }) : assert(label != null || labelBuilder != null);

  final IconData icon;
  final Color? iconColor;
  final String? label;
  final Widget Function(BuildContext)? labelBuilder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0b1220),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: iconColor ?? Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: labelBuilder != null
                  ? labelBuilder!(context)
                  : Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class AlertsCountBadge extends StatelessWidget {
  const AlertsCountBadge({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      return const Text('Alerts', style: TextStyle(color: Colors.white));
    }

    final stream = Supabase.instance.client
        .from('alerts')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (_, snap) {
        final items = (snap.data ?? const []);
        final mine = items.where((r) => r['user_id'] == uid);
        final count = mine.where((r) => r['acknowledged'] == false).length;

        if (count <= 0) {
          return const Text('Alerts', style: TextStyle(color: Colors.white));
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Alerts', style: TextStyle(color: Colors.white)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
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
