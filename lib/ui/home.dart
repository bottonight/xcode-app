import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../app_model.dart';
import '../models.dart';
import 'design.dart';

class HomePage extends StatelessWidget {
  const HomePage(this.app, {super.key});
  final AppModel app;
  @override
  Widget build(BuildContext context) => switch (app.route) {
    HomeRoute.projects => _projects(context),
    HomeRoute.discovery => _discovery(context),
    HomeRoute.modes => _modes(),
    HomeRoute.workbench => _workbench(context),
  };
  Widget _projects(BuildContext context) => PageBody(
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = MediaQuery.textScalerOf(context).scale(16) > 25 ? 1 : 2;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (var i = 0; i < 4; i++)
                SizedBox(
                  width: (constraints.maxWidth - 14 * (columns - 1)) / columns,
                  child: Semantics(
                    button: true,
                    enabled: i == 0,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: i == 0 ? app.discover : null,
                      child: BrandCard(
                        child: SizedBox(
                          height: 142,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                [
                                  Icons.monitor_heart_outlined,
                                  Icons.local_florist_outlined,
                                  Icons.show_chart,
                                  Icons.grid_on,
                                ][i],
                                size: 34,
                                color: i == 0 ? indigo : muted,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                app.t(i == 0 ? 'project.composition' : 'project.coming_soon'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: i == 0 ? Colors.black87 : muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
  String get bluetoothKey => app.bluetooth.scanning
      ? 'discovery.scanning'
      : switch (app.bluetooth.adapter) {
          BluetoothAdapterState.on => 'bt.ready',
          BluetoothAdapterState.off => 'bt.off',
          BluetoothAdapterState.unauthorized => 'bt.unauthorized',
          BluetoothAdapterState.unavailable => 'bt.unsupported',
          _ => 'bt.checking',
        };
  Widget _discovery(BuildContext context) => RefreshIndicator(
    onRefresh: () async {
      await app.perform(app.bluetooth.startScan);
    },
    child: PageBody(
      children: [
        Row(
          children: [
            Icon(
              Icons.bluetooth,
              color: app.bluetooth.adapter == BluetoothAdapterState.on ? indigo : Colors.orange,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(app.t(bluetoothKey))),
            if (app.bluetooth.scanning)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            IconButton(
              tooltip: app.t('discovery.rescan'),
              onPressed: () => app.perform(
                app.bluetooth.scanning ? app.bluetooth.stopScan : app.bluetooth.startScan,
              ),
              icon: Icon(app.bluetooth.scanning ? Icons.stop_circle_outlined : Icons.refresh),
            ),
          ],
        ),
        if (app.bluetooth.nearby.isEmpty)
          EmptyPanel(
            icon: Icons.sensors,
            title: app.t('discovery.empty'),
            subtitle: app.t('discovery.empty_hint'),
            action: FilledButton(
              onPressed: () => app.perform(app.bluetooth.startScan),
              child: Text(app.t('discovery.rescan')),
            ),
          ),
        for (final device in app.bluetooth.nearby)
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
                child: const Icon(Icons.sensors, color: indigo),
              ),
              title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(device.kind.label),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: app.t('a11y.signal', device.signal),
                    child: SignalBars(device.signal),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.chevron_right, color: muted),
                ],
              ),
              onTap: () async {
                await app.prepare(device);
                if (!context.mounted || !app.pendingBinding) return;
                final bind = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(app.t('discovery.bind_title')),
                    content: Text(app.t('discovery.bind_message')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(app.t('common.cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(app.t('discovery.bind_continue')),
                      ),
                    ],
                  ),
                );
                if (bind == true) {
                  if (!await app.bind()) await app.cancelBinding();
                } else {
                  await app.cancelBinding();
                }
              },
            ),
          ),
      ],
    ),
  );
  Widget _modes() => PageBody(
    children: [
      BrandCard(
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: cyan),
            const SizedBox(width: 10),
            Expanded(child: Text(app.selectedDevice?.name ?? '')),
          ],
        ),
      ),
      if (app.modes.isEmpty)
        EmptyPanel(
          icon: Icons.lock_outline,
          title: app.t('mode.title'),
          subtitle: app.t('error.device_unavailable'),
        ),
      for (final mode in app.modes)
        BrandCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE9ECFA),
              child: Icon(Icons.auto_awesome, color: indigo),
            ),
            title: Text(
              mode.title(app.english),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(app.t('mode.monthly_use', mode.monthlyUse)),
            trailing: const Icon(Icons.chevron_right, color: muted),
            onTap: () => app.chooseMode(mode),
          ),
        ),
    ],
  );

  Widget _workbench(BuildContext context) => PageBody(
    children: [
      BrandCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Heading(app.selectedDevice?.name ?? app.t('workbench.disconnected')),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        app.t('workbench.connected'),
                        style: const TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(app.selectedDevice?.kind.label ?? '', style: const TextStyle(color: muted)),
          ],
        ),
      ),
      BrandCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Heading(app.t('workbench.settings')),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(app.t('scan.single'))),
                ButtonSegment(value: true, label: Text(app.t('scan.multiple'))),
              ],
              selected: {app.multiple},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                app.multiple = value.first;
                app.clearMeasurements();
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<bool>(
              initialValue: app.defaultReference,
              isExpanded: true,
              decoration: InputDecoration(labelText: app.t('workbench.calibration')),
              items: [
                DropdownMenuItem(value: true, child: Text(app.t('cal.builtin'))),
                DropdownMenuItem(value: false, child: Text(app.t('cal.manual'))),
              ],
              onChanged: (value) {
                app.defaultReference = value!;
                app.clearMeasurements();
              },
            ),
            if (!app.defaultReference) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: app.calibrate,
                icon: const Icon(Icons.center_focus_strong),
                label: Text(app.t('workbench.start_manual_cal')),
              ),
            ],
          ],
        ),
      ),
      BrandCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              app.multiple
                  ? app.t('workbench.collected', app.captures.length)
                  : app.t('workbench.scan_and_predict'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: app.multiple ? Colors.black87 : muted,
                fontWeight: app.multiple ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              app.t('workbench.hardware_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: app.busy || (app.multiple && app.captures.length >= 9) ? null : app.scan,
              child: Text(app.t('workbench.start_scan')),
            ),
            if (app.multiple && app.captures.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: app.captures.length >= 2 ? app.predictMultiple : null,
                icon: const Icon(Icons.auto_awesome),
                label: Text(app.t('workbench.predict_n', app.captures.length)),
              ),
              TextButton(
                onPressed: app.clearMeasurements,
                child: Text(app.t('workbench.clear'), style: const TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
      if (app.result != null)
        BrandCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified, color: cyan),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      app.t('workbench.result'),
                      style: const TextStyle(color: cyan, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (app.resultTime != null)
                    Text(
                      TimeOfDay.fromDateTime(app.resultTime!).format(context),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(
                app.result!,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              if (app.multiple) ...[
                const SizedBox(height: 8),
                Text(
                  app.t('workbench.result_based', app.captures.length),
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      if ((app.session?.adminLevel ?? 0) >= 1)
        BrandCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Heading(app.t('workbench.more')),
              TextButton.icon(
                onPressed: () => _pending(context),
                icon: const Icon(Icons.save_alt),
                label: Text(app.t('workbench.save_spectrum')),
              ),
              if (app.selectedDevice?.kind == DeviceKind.ir2210 && app.session!.adminLevel >= 2)
                TextButton.icon(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => DeviceSettingsPage(app),
                  ),
                  icon: const Icon(Icons.tune),
                  label: Text(app.t('workbench.ir_config')),
                ),
            ],
          ),
        ),
    ],
  );
  void _pending(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(app.t('common.alert')),
      content: Text(app.t('workbench.save_pending')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(app.t('common.ok'))),
      ],
    ),
  );
}

class DeviceSettingsPage extends StatefulWidget {
  const DeviceSettingsPage(this.app, {super.key});
  final AppModel app;
  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  double integration = 10;
  bool light = true, average = false;
  int count = 3;
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return FractionallySizedBox(
      heightFactor: .9,
      child: Scaffold(
        appBar: AppBar(
          title: Text(app.t('device.settings.title')),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        body: PageBody(
          children: [
            Text(
              app.english
                  ? 'These controls are a preview. Device configuration is not connected in the original app.'
                  : '原版尚未接入设备参数写入，以下控件仅供预览。',
              style: const TextStyle(color: muted),
            ),
            BrandCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Heading(app.t('device.settings.params')),
                  const SizedBox(height: 12),
                  Text('${app.t('device.settings.integration')}  ${integration.round()} ms'),
                  Slider(
                    value: integration,
                    min: 1,
                    max: 50,
                    divisions: 49,
                    onChanged: (v) => setState(() => integration = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(app.t('device.settings.instant')),
                    value: light,
                    onChanged: (v) => setState(() => light = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(app.t('device.settings.average')),
                    value: average,
                    onChanged: (v) => setState(() => average = v),
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(app.t('device.settings.average_count', count))),
                      IconButton(
                        onPressed: average && count > 2 ? () => setState(() => count--) : null,
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        onPressed: average && count < 10 ? () => setState(() => count++) : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            BrandCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Heading(app.t('device.settings.cal')),
                  for (final key in ['ti', 'aopu', 'dark'])
                    TextButton(onPressed: null, child: Text(app.t('device.settings.$key'))),
                ],
              ),
            ),
            FilledButton(onPressed: null, child: Text(app.t('device.settings.save'))),
          ],
        ),
      ),
    );
  }
}
