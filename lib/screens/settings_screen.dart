import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../services/watch_communication_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _freeFallThreshold = 0.5;
  double _impactThreshold = 2.5;
  double _tiltThreshold = 45.0;
  int _freeFallMinMs = 80;
  bool _loading = true;

  static const _kFreeFall = 'thresh_freefall';
  static const _kImpact = 'thresh_impact';
  static const _kTilt = 'thresh_tilt';
  static const _kFreeFallMs = 'thresh_freefall_ms';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _freeFallThreshold = prefs.getDouble(_kFreeFall) ?? 0.5;
      _impactThreshold = prefs.getDouble(_kImpact) ?? 2.5;
      _tiltThreshold = prefs.getDouble(_kTilt) ?? 45.0;
      _freeFallMinMs = prefs.getInt(_kFreeFallMs) ?? 80;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFreeFall, _freeFallThreshold);
    await prefs.setDouble(_kImpact, _impactThreshold);
    await prefs.setDouble(_kTilt, _tiltThreshold);
    await prefs.setInt(_kFreeFallMs, _freeFallMinMs);
    // Push updated thresholds to connected watch(es) — fire-and-forget
    unawaited(
      WatchCommunicationService.pushThresholds(
        freeFall: _freeFallThreshold,
        impact: _impactThreshold,
        tilt: _tiltThreshold,
        freeFallMs: _freeFallMinMs,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.settingsSaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        actions: [TextButton(onPressed: _save, child: Text(l10n.save))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _sectionHeader(l10n.thresholdsSection, cs),
                const SizedBox(height: 8),
                _infoCard(l10n.thresholdsInfo, cs),
                const SizedBox(height: 24),
                _sliderTile(
                  label: l10n.freeFallLabel,
                  value: _freeFallThreshold,
                  unit: l10n.unitG,
                  min: 0.1,
                  max: 1.0,
                  divisions: 18,
                  description: l10n.freeFallDesc,
                  onChanged: (v) => setState(() => _freeFallThreshold = v),
                  cs: cs,
                ),
                _sliderTile(
                  label: l10n.impactLabel,
                  value: _impactThreshold,
                  unit: l10n.unitG,
                  min: 1.5,
                  max: 5.0,
                  divisions: 35,
                  description: l10n.impactDesc,
                  onChanged: (v) => setState(() => _impactThreshold = v),
                  cs: cs,
                ),
                _sliderTile(
                  label: l10n.tiltLabel,
                  value: _tiltThreshold,
                  unit: l10n.unitDeg,
                  min: 20.0,
                  max: 90.0,
                  divisions: 70,
                  description: l10n.tiltDesc,
                  onChanged: (v) => setState(() => _tiltThreshold = v),
                  cs: cs,
                ),
                _sliderTile(
                  label: l10n.freeFallDurationLabel,
                  value: _freeFallMinMs.toDouble(),
                  unit: l10n.unitMs,
                  min: 40,
                  max: 200,
                  divisions: 32,
                  description: l10n.freeFallDurationDesc,
                  onChanged: (v) => setState(() => _freeFallMinMs = v.round()),
                  cs: cs,
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () async {
                    setState(() {
                      _freeFallThreshold = 0.5;
                      _impactThreshold = 2.5;
                      _tiltThreshold = 45.0;
                      _freeFallMinMs = 80;
                    });
                    await _save();
                  },
                  icon: const Icon(Icons.restore),
                  label: Text(l10n.resetDefaults),
                ),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title, ColorScheme cs) => Text(
        title,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      );

  Widget _infoCard(String text, ColorScheme cs) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      );

  Widget _sliderTile({
    required String label,
    required double value,
    required String unit,
    required double min,
    required double max,
    required int divisions,
    required String description,
    required ValueChanged<double> onChanged,
    required ColorScheme cs,
  }) {
    final displayVal = unit == AppLocalizations.of(context).unitMs
        ? '${value.round()}$unit'
        : '${value.toStringAsFixed(1)}$unit';

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                displayVal,
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Text(
            description,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
