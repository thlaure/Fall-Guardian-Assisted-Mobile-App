import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/fall_event.dart';
import '../repositories/fall_events_repository.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _repo = FallEventsRepository();
  List<FallEvent> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final events = await _repo.getAll();
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load history.')),
        );
      }
    }
  }

  Future<void> _clearHistory() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.clearHistoryTitle),
        content: Text(l10n.clearHistoryBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.clear, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _repo.clear();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          if (_events.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history,
                        size: 72,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.historyEmpty,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _events.length,
                  itemBuilder: (_, i) =>
                      _EventTile(event: _events[i], l10n: l10n),
                ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final FallEvent event;
  final AppLocalizations l10n;
  const _EventTile({required this.event, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('MMM d, yyyy — h:mm a');
    final (icon, color, label) = switch (event.status) {
      FallEventStatus.alertSent => (
          Icons.send,
          Colors.redAccent,
          l10n.statusAlertSent,
        ),
      FallEventStatus.alertFailed => (
          Icons.sms_failed,
          Colors.deepOrange,
          l10n.statusAlertFailed,
        ),
      FallEventStatus.cancelled => (
          Icons.cancel,
          Colors.green,
          l10n.statusCancelled,
        ),
      FallEventStatus.timedOutNoSms => (
          Icons.timer_off,
          Colors.orangeAccent,
          l10n.statusTimedOut,
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  fmt.format(event.timestamp.toLocal()),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
            if (event.notifiedContacts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.notifiedLabel(event.notifiedContacts.join(', ')),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
            if (event.latitude != null && event.longitude != null) ...[
              const SizedBox(height: 4),
              Text(
                l10n.locationLabel(
                  '${event.latitude!.toStringAsFixed(5)}, '
                  '${event.longitude!.toStringAsFixed(5)}',
                ),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
