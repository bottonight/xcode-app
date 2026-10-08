import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../app_model.dart';
import '../gsm.dart';
import '../services/gsm_ble.dart';
import 'design.dart';
import 'gsm_device.dart';

class GsmScanPage extends StatefulWidget {
  const GsmScanPage(this.app, {super.key});
  final AppModel app;
  @override
  State<GsmScanPage> createState() => _GsmScanPageState();
}

class _GsmScanPageState extends State<GsmScanPage> {
  final ble = GsmBle();

  @override
  void initState() {
    super.initState();
    ble.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scan();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ble.removeListener(_changed);
    unawaited(ble.close());
    super.dispose();
  }

  Future<void> _scan() async {
    await widget.app.bluetooth.stopScan();
    try {
      await ble.startScan();
    } catch (error) {
      if (!mounted) return;
      widget.app.showMessage(gsmErrorText(widget.app.t, error));
    }
  }

  Future<void> _open(GsmNearby device) async {
    final app = widget.app;
    final current = ble.link;
    GsmLink? link = current != null && current.id == device.id && current.connected
        ? current
        : null;
    if (link == null) {
      final ok = await app.perform(() async {
        link = await ble.connect(device);
      }, title: 'bt.op.connect');
      if (!ok || !mounted || link == null) return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => GsmDevicePage(app, link!)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final ready = ble.adapter == BluetoothAdapterState.on;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('gsm.scan_title'))),
      body: PageBody(
        children: [
          Row(
            children: [
              Icon(Icons.bluetooth, color: ready ? indigo : Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  app.t(
                    ble.scanning
                        ? 'discovery.scanning'
                        : ready
                        ? 'bt.ready'
                        : ble.adapter == BluetoothAdapterState.off
                        ? 'bt.off'
                        : ble.adapter == BluetoothAdapterState.unauthorized
                        ? 'bt.unauthorized'
                        : 'bt.checking',
                  ),
                ),
              ),
              if (ble.scanning)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          Text(
            '${app.t('gsm.scan_found')} (${ble.nearby.length})',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (ble.nearby.isEmpty)
            EmptyPanel(
              icon: Icons.sensors,
              title: app.t(ble.scanning ? 'gsm.scanning' : 'gsm.scan_empty'),
              subtitle: app.t('gsm.scan_hint'),
            ),
          for (final device in ble.nearby)
            BrandCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: indigo.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.scale_outlined, color: indigo),
                ),
                title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(app.t('gsm.signal', device.rssi)),
                trailing: ble.link?.id == device.id && (ble.link?.connected ?? false)
                    ? Text(app.t('gsm.connected'), style: const TextStyle(color: cyan))
                    : const Icon(Icons.chevron_right, color: muted),
                onTap: () => _open(device),
              ),
            ),
          FilledButton(
            onPressed: ble.scanning ? null : _scan,
            child: Text(app.t(ble.scanning ? 'gsm.scanning_button' : 'gsm.scan')),
          ),
        ],
      ),
    );
  }
}
