import 'package:flutter/material.dart';

import '../app_model.dart';
import '../gsm.dart';
import '../models.dart';
import '../services/gsm_ble.dart';
import 'design.dart';

class GsmDevicePage extends StatefulWidget {
  const GsmDevicePage(this.app, this.link, {super.key});
  final AppModel app;
  final GsmLink link;
  @override
  State<GsmDevicePage> createState() => _GsmDevicePageState();
}

class _GsmDevicePageState extends State<GsmDevicePage> {
  bool loading = true;
  String? error;
  int? guideStep;
  String bindStatus = '';
  String boundPhone = '';
  bool leaving = false;

  GsmLink get link => widget.link;

  @override
  void initState() {
    super.initState();
    link.addListener(_onLink);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prepare();
    });
  }

  void _onLink() {
    if (!mounted || leaving || link.connected) {
      if (mounted) setState(() {});
      return;
    }
    leaving = true;
    final app = widget.app;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(app.t('common.alert')),
        content: Text(app.t('bt.device_lost')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(app.t('common.ok'))),
        ],
      ),
    ).then((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    link.removeListener(_onLink);
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final info = await link.readInfo();
      if (!mounted) return;
      await widget.app.rememberGsmDevice(GsmDevice(id: info.deviceId, name: _name));
      await _syncName(info);
      await _checkBind(info);
    } catch (error) {
      if (!mounted) return;
      setState(() => this.error = gsmErrorText(widget.app.t, error));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String get _name {
    final fallback = widget.app.t('gsm.default_name');
    return link.displayName.trim().isEmpty ? fallback : link.displayName.trim();
  }

  Future<void> _syncName(GsmHardwareInfo info) async {
    final account = widget.app.gsmAccount;
    if (account.isEmpty) return;
    try {
      final server = await widget.app.gsmApi.deviceName(account, info.deviceId);
      if (!mounted) return;
      if (server == null) {
        await widget.app.gsmApi.rename(account, info.deviceId, _name);
        return;
      }
      if (server != link.displayName) {
        await link.writeName(server);
        await widget.app.rememberGsmDevice(GsmDevice(id: info.deviceId, name: server));
      }
    } catch (_) {}
  }

  Future<void> _checkBind(GsmHardwareInfo info) async {
    final phone = widget.app.session?.phone ?? '';
    try {
      final bindings = await widget.app.gsmApi.bindStatus(info.deviceId);
      if (!mounted) return;
      final mine = phone.isNotEmpty && bindings.contains(phone);
      setState(() {
        if (bindings.isEmpty) {
          bindStatus = 'unbound';
          guideStep = 0;
        } else if (mine) {
          bindStatus = 'self';
        } else {
          bindStatus = 'other';
          boundPhone = bindings.first;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        bindStatus = 'unbound';
        guideStep = 0;
      });
    }
  }

  Future<void> _rename() async {
    final app = widget.app;
    final next = await showDialog<String>(
      context: context,
      builder: (context) => _GsmNameDialog(
        initial: _name,
        title: app.t('gsm.rename'),
        cancel: app.t('common.cancel'),
        done: app.t('common.done'),
        invalid: app.t,
      ),
    );
    if (next == null) return;
    final info = link.hardware;
    final ok = await app.perform(() async {
      if (info != null && app.gsmAccount.isNotEmpty) {
        await app.gsmApi.rename(app.gsmAccount, info.deviceId, next);
      }
      await link.writeName(next);
      if (info != null) {
        await app.rememberGsmDevice(GsmDevice(id: info.deviceId, name: next));
      }
    });
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.t('gsm.renamed'))));
    }
  }

  Future<void> _info() async {
    if (link.hardware == null) {
      final ok = await widget.app.perform(() => link.readInfo(), title: 'gsm.reading_info');
      if (!ok || !mounted) return;
    }
    final info = link.hardware;
    if (info == null || !mounted) return;
    final app = widget.app;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(app.t('gsm.info')),
        content: SelectableText(
          '${app.t('gsm.field_id')}: ${info.deviceId}\n'
          '${app.t('gsm.field_hardware')}: ${info.hardware}\n'
          '${app.t('gsm.field_mac')}: ${info.mac}\n'
          '${app.t('gsm.field_software')}: ${info.software}\n'
          '${app.t(info.supports5g ? 'gsm.wifi_both' : 'gsm.wifi_24g')}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(app.t('common.ok'))),
        ],
      ),
    );
  }

  Future<void> _wifi() async {
    final result = await showDialog<_WifiChoice>(
      context: context,
      builder: (context) => _WifiDialog(
        app: widget.app,
        supports5g: link.hardware?.supports5g ?? false,
        guided: guideStep == 0,
      ),
    );
    if (!mounted || result == null) return;
    if (result.skip) {
      setState(() => guideStep = 1);
      return;
    }
    final ok = await widget.app.perform(
      () => link.setWifi(result.name, result.password),
      title: 'gsm.wifi_connecting',
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.app.t('gsm.wifi_ok'))));
      if (guideStep == 0) setState(() => guideStep = 1);
    }
  }

  Future<void> _update() async {
    final info = link.hardware;
    if (info == null) {
      widget.app.showMessage(widget.app.t('gsm.need_info'));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _UpdateDialog(app: widget.app, link: link, info: info),
    );
  }

  Future<void> _network() async {
    final app = widget.app;
    if (link.networkStatus == 'connected') {
      var address = link.ip;
      if (address.isEmpty) {
        final ok = await app.perform(() async {
          address = await link.readIp();
        }, title: 'gsm.reading_ip');
        if (!ok || !mounted) return;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(app.t('gsm.ip')),
          content: SelectableText(address),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(app.t('common.ok'))),
          ],
        ),
      );
      return;
    }
    app.showMessage(
      app.t(link.networkStatus == 'disconnected' ? 'gsm.network_off' : 'gsm.network_unknown'),
    );
  }

  Future<void> _finishGuide() async {
    final info = link.hardware;
    final app = widget.app;
    final ok = await app.perform(() async {
      await link.notifyBound();
      final account = app.gsmAccount;
      if (info == null || account.isEmpty) throw const AppException('gsm.need_phone');
      await app.gsmApi.bind(account, info.deviceId);
      await app.rememberGsmDevice(GsmDevice(id: info.deviceId, name: _name));
    }, title: 'gsm.binding');
    if (!ok || !mounted) return;
    setState(() {
      guideStep = null;
      bindStatus = 'self';
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final networkColor = link.networkStatus == 'connected'
        ? cyan
        : link.networkStatus == 'disconnected'
        ? Colors.red
        : muted;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('gsm.device_title'))),
      body: PageBody(
        children: [
          if (guideStep != null)
            BrandCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(app.t(guideStep == 0 ? 'gsm.guide_wifi' : 'gsm.guide_cal')),
                  const SizedBox(height: 12),
                  if (guideStep == 0)
                    FilledButton(onPressed: _wifi, child: Text(app.t('gsm.wifi')))
                  else
                    FilledButton(onPressed: _finishGuide, child: Text(app.t('gsm.guide_done'))),
                ],
              ),
            ),
          BrandCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.scale_outlined, color: indigo, size: 42),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        InkWell(
                          onTap: _network,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wifi, color: networkColor, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                app.t(
                                  link.networkStatus == 'connected'
                                      ? 'gsm.network_on'
                                      : link.networkStatus == 'disconnected'
                                      ? 'gsm.network_off'
                                      : 'gsm.network_unknown',
                                ),
                                style: TextStyle(color: networkColor, fontSize: 12),
                              ),
                              if (link.networkStatus == 'connected' && link.wifiSignal > 0)
                                Text(' (${link.wifiSignal})', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bluetooth, color: indigo, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              '${app.t('gsm.ble_signal')} (${link.bluetoothSignal})',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _rename,
                  child: Row(
                    children: [
                      Expanded(child: Heading(_name)),
                      Text(
                        app.t('gsm.tap_edit'),
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(link.id, style: const TextStyle(color: muted, fontSize: 12)),
                if (loading) ...[const SizedBox(height: 16), const LinearProgressIndicator()],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
                if (bindStatus.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    bindStatus == 'self'
                        ? app.t('gsm.bound_self')
                        : bindStatus == 'other'
                        ? app.t('gsm.bound_other', boundPhone)
                        : app.t('gsm.unbound'),
                    style: TextStyle(
                      color: bindStatus == 'other' ? Colors.orange.shade800 : indigo,
                    ),
                  ),
                ],
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _info,
            icon: const Icon(Icons.info_outline),
            label: Text(app.t('gsm.info')),
          ),
          FilledButton.icon(
            onPressed: link.connected ? _wifi : null,
            icon: const Icon(Icons.wifi),
            label: Text(app.t('gsm.wifi')),
          ),
          FilledButton.icon(
            onPressed: link.connected ? _update : null,
            icon: const Icon(Icons.system_update_alt),
            label: Text(app.t('gsm.update')),
          ),
        ],
      ),
    );
  }
}

class _WifiChoice {
  const _WifiChoice(this.name, this.password, {this.skip = false});
  final String name, password;
  final bool skip;
}

class _WifiDialog extends StatefulWidget {
  const _WifiDialog({required this.app, required this.supports5g, required this.guided});
  final AppModel app;
  final bool supports5g, guided;
  @override
  State<_WifiDialog> createState() => _WifiDialogState();
}

class _WifiDialogState extends State<_WifiDialog> {
  final name = TextEditingController();
  final password = TextEditingController();
  bool visible = false;
  @override
  void dispose() {
    name.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return AlertDialog(
      title: Text(app.t('gsm.wifi_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.supports5g)
            Text(app.t('gsm.wifi_24g'), style: const TextStyle(color: Colors.orange)),
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: app.t('gsm.wifi_name')),
          ),
          TextField(
            controller: password,
            obscureText: !visible,
            decoration: InputDecoration(
              labelText: app.t('gsm.wifi_password'),
              suffixIcon: IconButton(
                onPressed: () => setState(() => visible = !visible),
                icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, widget.guided ? const _WifiChoice('', '', skip: true) : null),
          child: Text(app.t(widget.guided ? 'gsm.guide_skip' : 'common.cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isEmpty || password.text.trim().isEmpty) {
              app.showMessage(app.t('gsm.wifi_required'));
              return;
            }
            Navigator.pop(context, _WifiChoice(name.text.trim(), password.text.trim()));
          },
          child: Text(app.t('common.ok')),
        ),
      ],
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.app, required this.link, required this.info});
  final AppModel app;
  final GsmLink link;
  final GsmHardwareInfo info;
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  String status = 'fetching';
  String latest = '';
  String message = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final version = await widget.app.gsmApi.latestVersion(
        mac: widget.info.mac,
        hardware: widget.info.hardware,
        software: widget.info.software,
      );
      if (!mounted) return;
      setState(() {
        latest = version;
        status = version == widget.info.software ? 'same' : 'compare';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        status = 'error';
        message = gsmErrorText(widget.app.t, error);
      });
    }
  }

  Future<void> _push() async {
    setState(() => status = 'updating');
    try {
      final result = await widget.link.pushUpdate(latest);
      if (!mounted) return;
      setState(() {
        status = result == 'success' ? 'success' : 'error';
        message = result == 'success' ? widget.app.t('gsm.update_ok') : result;
      });
      if (result == 'success') widget.link.hardware = null;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        status = 'error';
        message = gsmErrorText(widget.app.t, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final info = widget.info;
    return AlertDialog(
      title: Text(app.t('gsm.update_title')),
      content: switch (status) {
        'fetching' => Text(app.t('gsm.update_fetching')),
        'compare' => Text(
          '${app.t('gsm.update_current', info.software)}\n${app.t('gsm.update_latest', latest)}\n${app.t('gsm.update_ask')}',
        ),
        'same' => Text(app.t('gsm.update_same', latest)),
        'updating' => Text(app.t('gsm.update_pushing')),
        'success' => Text(app.t('gsm.update_ok')),
        _ => Text(message),
      },
      actions: [
        if (status == 'compare') ...[
          TextButton(onPressed: () => Navigator.pop(context), child: Text(app.t('common.cancel'))),
          FilledButton(onPressed: _push, child: Text(app.t('gsm.update_push'))),
        ] else if (status != 'fetching' && status != 'updating')
          TextButton(onPressed: () => Navigator.pop(context), child: Text(app.t('common.ok'))),
      ],
    );
  }
}

class _GsmNameDialog extends StatefulWidget {
  const _GsmNameDialog({
    required this.initial,
    required this.title,
    required this.cancel,
    required this.done,
    required this.invalid,
  });
  final String initial, title, cancel, done;
  final String Function(String key, [Object? value]) invalid;
  @override
  State<_GsmNameDialog> createState() => _GsmNameDialogState();
}

class _GsmNameDialogState extends State<_GsmNameDialog> {
  late final controller = TextEditingController(text: widget.initial);
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      autofocus: true,
      decoration: InputDecoration(errorText: error == null ? null : widget.invalid(error!)),
      onChanged: (value) {
        final sanitized = sanitizeGsmName(value);
        if (sanitized.value != value) {
          controller.value = TextEditingValue(
            text: sanitized.value,
            selection: TextSelection.collapsed(offset: sanitized.value.length),
          );
        }
        setState(() => error = sanitized.errorKey);
      },
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancel)),
      TextButton(
        onPressed: () {
          final message = validateGsmName(controller.text);
          if (message != null) {
            setState(() => error = message);
            return;
          }
          Navigator.pop(context, controller.text.trim());
        },
        child: Text(widget.done),
      ),
    ],
  );
}
