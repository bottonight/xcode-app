import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_model.dart';
import '../models.dart';
import 'design.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage(this.app, {super.key});
  final AppModel app;
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async {
      await app.loadDevices();
    },
    child: PageBody(
      children: [
        if (app.managedDevices.isEmpty)
          EmptyPanel(
            icon: Icons.sensors,
            title: app.t('devices.empty'),
            subtitle: app.t('devices.empty_hint'),
            action: OutlinedButton.icon(
              onPressed: app.loadDevices,
              icon: const Icon(Icons.refresh),
              label: Text(app.t('discovery.rescan')),
            ),
          ),
        for (final device in app.managedDevices)
          BrandCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(device.serial),
                  const SizedBox(height: 6),
                  Text(
                    app.t('mode.monthly_use', device.monthlyUse),
                    style: const TextStyle(color: indigo),
                  ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => DeviceDetailPage(app, device)),
              ),
            ),
          ),
      ],
    ),
  );
}

class DeviceDetailPage extends StatelessWidget {
  const DeviceDetailPage(this.app, this.device, {super.key});
  final AppModel app;
  final ManagedDevice device;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) {
      final months = device.history.keys.toList()..sort();
      final maxCount = device.history.values.fold<int>(1, math.max);
      return Scaffold(
        appBar: AppBar(title: Text(app.t('devices.detail'))),
        body: PageBody(
          children: [
            BrandCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Heading(device.name),
                  const SizedBox(height: 8),
                  SelectableText(device.serial, style: const TextStyle(color: muted)),
                  const Divider(height: 28),
                  Row(
                    children: [
                      Expanded(child: Text(app.t('devices.monthly_count'))),
                      Text('${device.monthlyUse}'),
                    ],
                  ),
                ],
              ),
            ),
            BrandCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Heading(app.t('devices.trend')),
                  const SizedBox(height: 18),
                  if (months.isEmpty)
                    const Text('—', style: TextStyle(color: muted))
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        height: 215,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final month in months)
                              Semantics(
                                label: '$month: ${device.history[month]}',
                                child: SizedBox(
                                  width: 68,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${device.history[month]}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        width: 32,
                                        height: math.max(
                                          2,
                                          148 * device.history[month]! / maxCount,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [Color(0xFF6175D3), indigo],
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        month,
                                        style: const TextStyle(fontSize: 11, color: muted),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (device.shareable)
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => SharingPage(app, device)),
                ),
                icon: const Icon(Icons.manage_accounts_outlined),
                label: Text(app.t('devices.manage_share')),
              ),
          ],
        ),
      );
    },
  );
}

class SharingPage extends StatefulWidget {
  const SharingPage(this.app, this.device, {super.key});
  final AppModel app;
  final ManagedDevice device;
  @override
  State<SharingPage> createState() => _SharingPageState();
}

class _SharingPageState extends State<SharingPage> {
  final phone = TextEditingController();
  List<String> users = [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reload();
    });
  }

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  Future<void> reload() => widget.app
      .perform(() async {
        final loaded = await widget.app.api.sharedUsers(widget.device, widget.app.session!);
        if (mounted) setState(() => users = loaded);
      })
      .then((_) {});
  Future<void> update(String number, {bool revoke = false}) async {
    final app = widget.app;
    final ok = await app.perform(() async {
      await app.api.share(widget.device, app.session!, number, revoke: revoke);
      final loaded = await app.api.sharedUsers(widget.device, app.session!);
      if (mounted) {
        setState(() {
          users = loaded;
          if (!revoke) phone.clear();
        });
      }
    });
    if (ok && !revoke && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.t('notice.shared'))));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.app,
    builder: (context, _) {
      final app = widget.app;
      return Scaffold(
        appBar: AppBar(title: Text(app.t('share.title'))),
        body: PageBody(
          children: [
            BrandCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Heading(app.t('share.add')),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(hintText: app.t('share.phone')),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: RegExp(r'^1\d{10}$').hasMatch(phone.text.trim())
                        ? () => update(phone.text.trim())
                        : null,
                    child: Text(app.t('share.action')),
                  ),
                ],
              ),
            ),
            BrandCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Heading(app.t('share.existing')),
                  const SizedBox(height: 12),
                  if (users.isEmpty)
                    Text(app.t('share.empty'), style: const TextStyle(color: muted)),
                  for (final user in users)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_circle_outlined),
                      title: Text(user),
                      trailing: TextButton(
                        onPressed: () => update(user, revoke: true),
                        child: Text(
                          app.t('share.revoke'),
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class AccountPage extends StatelessWidget {
  const AccountPage(this.app, {super.key});
  final AppModel app;

  Future<void> _editNickname(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _NicknameDialog(
        initial: app.session?.username ?? '',
        title: app.t('account.edit_title'),
        hint: app.t('account.nickname'),
        cancelLabel: app.t('common.cancel'),
        doneLabel: app.t('common.done'),
      ),
    );
    if (result != null && context.mounted) {
      await app.updateUsername(result);
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      BrandCard(
        child: Row(
          children: [
            const Icon(Icons.account_circle, color: indigo, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Heading(
                        (app.session?.username.trim().isNotEmpty ?? false)
                            ? app.session!.username
                            : app.t('common.user'),
                      ),
                      GestureDetector(
                        onTap: () => _editNickname(context),
                        child: Text(
                          app.t('account.edit'),
                          style: const TextStyle(color: indigo, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  Text(app.session?.account ?? '', style: const TextStyle(color: muted)),
                ],
              ),
            ),
          ],
        ),
      ),
      BrandCard(
        child: DropdownButtonFormField<bool>(
          initialValue: app.english,
          isExpanded: true,
          decoration: InputDecoration(labelText: app.t('account.language')),
          items: const [
            DropdownMenuItem(value: false, child: Text('中文')),
            DropdownMenuItem(value: true, child: Text('English')),
          ],
          onChanged: (value) => app.perform(() => app.setLanguage(value!)),
        ),
      ),
      if ((app.session?.adminLevel ?? 0) >= 1)
        BrandCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Heading(app.t('account.permissions')),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text(app.t('account.admin_level'))),
                  Text('${app.session!.adminLevel}'),
                ],
              ),
            ],
          ),
        ),
      BrandCard(
        child: TextButton(
          onPressed: () => app.perform(app.signOut),
          child: Text(app.t('account.sign_out'), style: const TextStyle(color: Colors.red)),
        ),
      ),
    ],
  );
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({
    required this.initial,
    required this.title,
    required this.hint,
    required this.cancelLabel,
    required this.doneLabel,
  });
  final String initial, title, hint, cancelLabel, doneLabel;
  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController controller = TextEditingController(text: widget.initial);
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
      decoration: InputDecoration(hintText: widget.hint),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
      TextButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: Text(widget.doneLabel),
      ),
    ],
  );
}
