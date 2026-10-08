import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_model.dart';
import '../gsm.dart';
import '../models.dart';
import 'design.dart';
import 'gsm_data.dart';
import 'gsm_scan.dart';

class GsmHistoryPage extends StatefulWidget {
  const GsmHistoryPage(this.app, {this.initialDeviceId, super.key});
  final AppModel app;
  final String? initialDeviceId;
  @override
  State<GsmHistoryPage> createState() => _GsmHistoryPageState();
}

class _GsmHistoryPageState extends State<GsmHistoryPage> {
  GsmDevice? device;
  List<GsmRecord> records = [];
  bool favorites = false;
  bool loading = true;
  bool selecting = false;
  int page = 1;
  int total = 0;
  int totalPages = 0;
  String error = '';
  final selected = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _boot();
    });
  }

  Future<void> _boot() async {
    setState(() => loading = true);
    await widget.app.refreshGsmDevices();
    if (!mounted) return;
    _pickDevice();
    if (device == null) {
      setState(() => loading = false);
      return;
    }
    await _load();
  }

  void _pickDevice() {
    final devices = widget.app.gsmDevices;
    if (devices.isEmpty) {
      device = null;
      return;
    }
    final wanted = device?.id ?? widget.initialDeviceId ?? widget.app.lastGsmDeviceId;
    device = devices.firstWhere((item) => item.id == wanted, orElse: () => devices.first);
  }

  Future<void> _load() async {
    final current = device;
    if (current == null) return;
    setState(() {
      loading = true;
      error = '';
    });
    await widget.app.selectGsmDevice(current.id);
    try {
      final result = await widget.app.gsmApi.history(current.id, page: page, favorite: favorites);
      if (!mounted || device?.id != current.id) return;
      setState(() {
        records = result.items;
        total = result.total;
        totalPages = result.totalPages;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        this.error = gsmErrorText(widget.app.t, error);
        loading = false;
      });
    }
  }

  Future<void> _switchDevice() async {
    final devices = widget.app.gsmDevices;
    final picked = await showModalBottomSheet<GsmDevice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in devices)
              ListTile(
                title: Text(item.label(widget.app.t('gsm.unknown_device'))),
                subtitle: Text(item.id),
                trailing: item.id == device?.id ? const Icon(Icons.check, color: indigo) : null,
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked.id == device?.id) return;
    setState(() {
      device = picked;
      page = 1;
      selecting = false;
      selected.clear();
    });
    await _load();
  }

  Future<void> _rename() async {
    final current = device;
    if (current == null) return;
    final app = widget.app;
    final next = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(
        initial: current.label(app.t('gsm.unknown_device')),
        title: app.t('gsm.rename'),
        cancel: app.t('common.cancel'),
        done: app.t('common.done'),
        invalid: (key) => app.t(key),
      ),
    );
    if (next == null || next == current.name) return;
    final ok = await app.perform(() async {
      final account = app.gsmAccount;
      if (account.isEmpty) throw const AppException('gsm.need_phone');
      await app.gsmApi.rename(account, current.id, next);
      await app.rememberGsmDevice(GsmDevice(id: current.id, name: next));
    });
    if (ok && mounted) {
      setState(() => device = GsmDevice(id: current.id, name: next));
      _toast(app.t('gsm.renamed'));
    }
  }

  Future<void> _share() async {
    final current = device;
    final app = widget.app;
    if (current == null) return;
    final phone = await showDialog<String>(
      context: context,
      builder: (context) => _PhoneDialog(
        title: app.t('gsm.share'),
        hint: app.t('gsm.share_phone'),
        cancel: app.t('common.cancel'),
        done: app.t('share.action'),
      ),
    );
    if (phone == null) return;
    final ok = await app.perform(() async {
      final owner = app.session?.phone ?? '';
      if (!RegExp(r'^1\d{10}$').hasMatch(owner)) throw const AppException('gsm.need_phone');
      await app.gsmApi.share(current.id, owner, phone);
    });
    if (ok && mounted) _toast(app.t('gsm.shared'));
  }

  Future<void> _sharedUsers() async {
    final current = device;
    final app = widget.app;
    if (current == null) return;
    List<String> phones = [];
    final ok = await app.perform(() async {
      phones = await app.gsmApi.sharedPhones(current.id);
    });
    if (!ok || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Heading(app.t('gsm.shared_users')),
              ),
              if (phones.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(app.t('gsm.shared_empty'), style: const TextStyle(color: muted)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final phone in phones)
                        ListTile(
                          title: Text(phone),
                          trailing: TextButton(
                            onPressed: () async {
                              final removed = await app.perform(
                                () => app.gsmApi.cancelShare(current.id, phone),
                              );
                              if (removed && context.mounted) {
                                setState(() => phones = [...phones]..remove(phone));
                                Navigator.pop(context);
                                _toast(app.t('gsm.unshared'));
                              }
                            },
                            child: Text(
                              app.t('gsm.unshare'),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(GsmRecord item) async {
    final current = device;
    if (current == null) return;
    final next = !item.favorite;
    final ok = await widget.app.perform(
      () => widget.app.gsmApi.setFavorite(current.id, item.id, favorite: next),
    );
    if (!ok || !mounted) return;
    setState(() {
      if (favorites && !next) {
        records = records.where((record) => record.id != item.id).toList();
      } else {
        records = [
          for (final record in records)
            if (record.id == item.id) record.copyWith(favorite: next) else record,
        ];
      }
    });
    _toast(widget.app.t(next ? 'gsm.favorite_on' : 'gsm.favorite_off'));
  }

  Future<void> _deleteSelected() async {
    final current = device;
    final app = widget.app;
    if (current == null || selected.isEmpty) {
      app.showMessage(app.t('gsm.need_selection'));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(app.t('common.alert')),
        content: Text(app.t('gsm.delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(app.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(app.t('gsm.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await app.perform(() async {
      final phone = app.session?.phone ?? '';
      if (!RegExp(r'^1\d{10}$').hasMatch(phone)) throw const AppException('gsm.need_phone');
      await app.gsmApi.deleteData(current.id, phone, selected.toList());
    });
    if (!ok || !mounted) return;
    setState(() {
      selecting = false;
      selected.clear();
    });
    _toast(app.t('gsm.deleted'));
    await _load();
  }

  Future<void> _open(GsmRecord item) async {
    final current = device;
    if (current == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(builder: (_) => GsmDataPage(widget.app, item.id)),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _scan() async {
    await widget.app.bluetooth.stopScan();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => GsmScanPage(widget.app)),
    );
    if (mounted) await _boot();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final current = device;
    final name = current?.label(app.t('gsm.unknown_device')) ?? app.t('gsm.unknown_device');
    return Scaffold(
      appBar: AppBar(title: Text(app.t('project.gsm'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: PageBody(
          children: [
            if (loading && current == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (current == null)
              EmptyPanel(
                icon: Icons.scale_outlined,
                title: app.t('gsm.no_device'),
                subtitle: app.t('gsm.no_device_hint'),
                action: FilledButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.add),
                  label: Text(app.t('gsm.add_device')),
                ),
              )
            else ...[
              BrandCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _switchDevice,
                      onLongPress: _rename,
                      child: Row(
                        children: [
                          Expanded(child: Heading(name)),
                          const Icon(Icons.arrow_drop_down, color: muted),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(app.t('gsm.device_id', current.id), style: const TextStyle(color: muted)),
                    Text(
                      app.t('gsm.long_press_edit'),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _share,
                          icon: const Icon(Icons.share_outlined, size: 18),
                          label: Text(app.t('gsm.share')),
                        ),
                        TextButton(onPressed: _sharedUsers, child: Text(app.t('gsm.shared_users'))),
                      ],
                    ),
                  ],
                ),
              ),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(app.t('gsm.all'))),
                  ButtonSegment(value: true, label: Text(app.t('gsm.favorites'))),
                ],
                selected: {favorites},
                showSelectedIcon: false,
                onSelectionChanged: (value) {
                  setState(() {
                    favorites = value.first;
                    page = 1;
                    selecting = false;
                    selected.clear();
                  });
                  _load();
                },
              ),
              if (selecting)
                Text(app.t('gsm.selected', selected.length), style: const TextStyle(color: indigo)),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (error.isNotEmpty)
                EmptyPanel(
                  icon: Icons.error_outline,
                  title: error,
                  subtitle: app.t('gsm.retry'),
                  action: OutlinedButton(onPressed: _load, child: Text(app.t('gsm.retry'))),
                )
              else if (records.isEmpty)
                EmptyPanel(
                  icon: Icons.inbox_outlined,
                  title: app.t(favorites ? 'gsm.favorites_empty' : 'gsm.empty'),
                  subtitle: app.t(favorites ? 'gsm.favorites_empty_hint' : 'gsm.empty_hint'),
                )
              else
                BrandCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final item in records)
                        ListTile(
                          onTap: selecting
                              ? () => setState(() {
                                  if (!selected.add(item.id)) selected.remove(item.id);
                                })
                              : () => _open(item),
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            setState(() {
                              selecting = true;
                              selected.add(item.id);
                            });
                          },
                          leading: selecting
                              ? Checkbox(
                                  value: selected.contains(item.id),
                                  onChanged: (value) => setState(() {
                                    if (value ?? false) {
                                      selected.add(item.id);
                                    } else {
                                      selected.remove(item.id);
                                    }
                                  }),
                                )
                              : _thumb(item.image),
                          title: Text(
                            item.product,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('${item.gsm} ${item.unit}  ·  ${item.time}'),
                          trailing: selecting
                              ? null
                              : IconButton(
                                  tooltip: app.t('gsm.favorite'),
                                  onPressed: () => _toggleFavorite(item),
                                  icon: Icon(
                                    item.favorite ? Icons.star : Icons.star_border,
                                    color: item.favorite ? const Color(0xFFE6B000) : muted,
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
              if (records.isNotEmpty && totalPages > 0)
                Text(
                  _pageText(app, total, page, totalPages),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              if (records.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: page > 1 && !loading
                            ? () {
                                setState(() => page -= 1);
                                _load();
                              }
                            : null,
                        child: Text(app.t('history.prev')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: page < totalPages && !loading
                            ? () {
                                setState(() => page += 1);
                                _load();
                              }
                            : null,
                        child: Text(app.t('history.next')),
                      ),
                    ),
                  ],
                ),
              if (selecting)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          selecting = false;
                          selected.clear();
                        }),
                        child: Text(app.t('common.cancel')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _deleteSelected,
                        child: Text(app.t('gsm.delete')),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _thumb(String image) {
    final bytes = decodeGsmImage(image);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: bytes == null
          ? Container(
              width: 44,
              height: 44,
              color: const Color(0xFFE9ECFA),
              child: const Icon(Icons.image_outlined, color: muted, size: 20),
            )
          : Image.memory(bytes, width: 44, height: 44, fit: BoxFit.cover),
    );
  }
}

String _pageText(AppModel app, int total, int page, int pages) {
  var text = app.t('gsm.page');
  for (final value in [total, page, pages]) {
    text = text.replaceFirst('%d', '$value');
  }
  return text;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.initial,
    required this.title,
    required this.cancel,
    required this.done,
    required this.invalid,
  });
  final String initial, title, cancel, done;
  final String Function(String key) invalid;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
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

class _PhoneDialog extends StatefulWidget {
  const _PhoneDialog({
    required this.title,
    required this.hint,
    required this.cancel,
    required this.done,
  });
  final String title, hint, cancel, done;
  @override
  State<_PhoneDialog> createState() => _PhoneDialogState();
}

class _PhoneDialogState extends State<_PhoneDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = RegExp(r'^1[3-9]\d{9}$').hasMatch(controller.text.trim());
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(hintText: widget.hint),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancel)),
        TextButton(
          onPressed: valid ? () => Navigator.pop(context, controller.text.trim()) : null,
          child: Text(widget.done),
        ),
      ],
    );
  }
}
