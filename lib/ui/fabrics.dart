import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_model.dart';
import '../models.dart';
import 'design.dart';

class TwoColumnHeader extends StatelessWidget {
  const TwoColumnHeader(this.app, {super.key});
  final AppModel app;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(app.t('history.time'), style: const TextStyle(color: muted, fontSize: 12)),
        ),
        Expanded(
          flex: 6,
          child: Text(
            app.t('history.components'),
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class TwoColumnRow extends StatelessWidget {
  const TwoColumnRow({
    super.key,
    required this.time,
    required this.components,
    this.selecting = false,
    this.checked = false,
    this.canCheck = true,
    this.onTap,
    this.onLongPress,
    this.onChecked,
  });
  final String time, components;
  final bool selecting, checked, canCheck;
  final VoidCallback? onTap, onLongPress;
  final ValueChanged<bool>? onChecked;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: selecting && canCheck ? () => onChecked?.call(!checked) : onTap,
    onLongPress: selecting ? null : onLongPress,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selecting) ...[
            SizedBox(
              width: 28,
              height: 24,
              child: Checkbox(
                value: canCheck && checked,
                onChanged: canCheck ? (value) => onChecked?.call(value ?? false) : null,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            flex: 5,
            child: Text(time.isEmpty ? '—' : time, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            flex: 6,
            child: Text(
              components.isEmpty ? '—' : components,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

class DeviceHistoryPage extends StatefulWidget {
  const DeviceHistoryPage(this.app, this.serial, {super.key});
  final AppModel app;
  final String serial;
  @override
  State<DeviceHistoryPage> createState() => _DeviceHistoryPageState();
}

class _DeviceHistoryPageState extends State<DeviceHistoryPage> {
  final items = <PredictionHistoryItem>[];
  int page = 1, total = 0;
  bool loadingMore = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reload();
    });
  }

  Future<void> reload() async {
    final ok = await widget.app.perform(() async {
      final loaded = await widget.app.loadDeviceHistory(widget.serial);
      if (!mounted) return;
      setState(() {
        items
          ..clear()
          ..addAll(loaded.items);
        page = loaded.page;
        total = loaded.total;
      });
    }, title: 'busy.loading');
    if (!ok && mounted) setState(() {});
  }

  Future<void> loadMore() async {
    if (loadingMore || items.length >= total) return;
    setState(() => loadingMore = true);
    try {
      final loaded = await widget.app.loadDeviceHistory(widget.serial, page: page + 1);
      if (!mounted) return;
      setState(() {
        items.addAll(loaded.items);
        page = loaded.page;
        total = loaded.total;
      });
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('devices.history'))),
      body: RefreshIndicator(
        onRefresh: reload,
        child: PageBody(
          children: [
            BrandCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TwoColumnHeader(app),
                  if (items.isEmpty)
                    Text(app.t('history.empty'), style: const TextStyle(color: muted))
                  else
                    for (final item in items)
                      TwoColumnRow(time: item.time, components: item.components),
                ],
              ),
            ),
            if (items.length < total)
              TextButton(
                onPressed: loadingMore ? null : loadMore,
                child: Text(app.t('history.load_more')),
              ),
          ],
        ),
      ),
    );
  }
}

class FabricsPage extends StatefulWidget {
  const FabricsPage(this.app, {super.key});
  final AppModel app;
  @override
  State<FabricsPage> createState() => _FabricsPageState();
}

class _FabricsPageState extends State<FabricsPage> {
  final items = <CustomerDataSummary>[];
  int page = 1, total = 0;
  bool loadingMore = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reload();
    });
  }

  Future<void> reload() async {
    await widget.app.perform(() async {
      final loaded = await widget.app.loadFabrics();
      if (!mounted) return;
      setState(() {
        items
          ..clear()
          ..addAll(loaded.items);
        page = loaded.page;
        total = loaded.total;
      });
    }, title: 'busy.loading');
  }

  Future<void> loadMore() async {
    if (loadingMore || items.length >= total) return;
    setState(() => loadingMore = true);
    try {
      final loaded = await widget.app.loadFabrics(page: page + 1);
      if (!mounted) return;
      setState(() {
        items.addAll(loaded.items);
        page = loaded.page;
        total = loaded.total;
      });
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('account.fabrics'))),
      body: RefreshIndicator(
        onRefresh: reload,
        child: PageBody(
          children: [
            BrandCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TwoColumnHeader(app),
                  if (items.isEmpty)
                    Text(app.t('fabrics.empty'), style: const TextStyle(color: muted))
                  else
                    for (final item in items)
                      TwoColumnRow(
                        time: item.time,
                        components: item.components,
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(builder: (_) => FabricDetailPage(app, item.id)),
                        ),
                      ),
                ],
              ),
            ),
            if (items.length < total)
              TextButton(
                onPressed: loadingMore ? null : loadMore,
                child: Text(app.t('history.load_more')),
              ),
          ],
        ),
      ),
    );
  }
}

class FabricDetailPage extends StatefulWidget {
  const FabricDetailPage(this.app, this.id, {super.key});
  final AppModel app;
  final int id;
  @override
  State<FabricDetailPage> createState() => _FabricDetailPageState();
}

class _FabricDetailPageState extends State<FabricDetailPage> {
  CustomerDataDetail? detail;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  Future<void> load() async {
    await widget.app.perform(() async {
      final loaded = await widget.app.loadFabric(widget.id);
      if (mounted) setState(() => detail = loaded);
    }, title: 'busy.loading');
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final data = detail;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('fabrics.detail'))),
      body: PageBody(
        children: [
          BrandCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Heading(app.t('history.components')),
                const SizedBox(height: 8),
                if (data == null || data.components.where((text) => text.isNotEmpty).isEmpty)
                  Text(app.t('fabrics.no_components'), style: const TextStyle(color: muted))
                else
                  for (final line in data.components.where((text) => text.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(line, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
              ],
            ),
          ),
          BrandCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Heading(app.t('fabrics.images')),
                const SizedBox(height: 12),
                if (data == null || data.images.isEmpty)
                  Text(app.t('fabrics.no_images'), style: const TextStyle(color: muted))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final image in data.images)
                        if (decodeDataImage(image) != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              decodeDataImage(image)!,
                              width: 108,
                              height: 108,
                              fit: BoxFit.cover,
                            ),
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
                Heading(app.t('fabrics.data')),
                const SizedBox(height: 12),
                if (data == null || data.data.isEmpty)
                  Text(app.t('fabrics.no_data'), style: const TextStyle(color: muted))
                else
                  for (final entry in data.data.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(entry.key, style: const TextStyle(color: muted)),
                          ),
                          Expanded(
                            child: Text(
                              entry.value,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SaveCustomerDataSheet extends StatefulWidget {
  const SaveCustomerDataSheet(this.app, this.preIds, {super.key});
  final AppModel app;
  final List<String> preIds;
  @override
  State<SaveCustomerDataSheet> createState() => _SaveCustomerDataSheetState();
}

class _SaveCustomerDataSheetState extends State<SaveCustomerDataSheet> {
  final picker = ImagePicker();
  final images = <String>[];
  final fields = <(TextEditingController, TextEditingController)>[];
  @override
  void initState() {
    super.initState();
    fields.add((TextEditingController(), TextEditingController()));
  }

  @override
  void dispose() {
    for (final field in fields) {
      field.$1.dispose();
      field.$2.dispose();
    }
    super.dispose();
  }

  Map<String, String> get extraData {
    final data = <String, String>{};
    for (final field in fields) {
      final key = field.$1.text.trim();
      if (key.isEmpty) continue;
      data[key] = field.$2.text.trim();
    }
    return data;
  }

  Future<void> addImage(ImageSource source) async {
    try {
      final file = await picker.pickImage(source: source, imageQuality: 85, maxWidth: 1600);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() => images.add('data:image/jpeg;base64,${base64Encode(bytes)}'));
    } catch (_) {
      if (!mounted) return;
      widget.app.showMessage(widget.app.t('error.image_failed'));
    }
  }

  Future<void> submit() async {
    final ok = await widget.app.saveCustomerData(
      preIds: widget.preIds,
      images: images,
      data: extraData,
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: .92,
        child: Scaffold(
          appBar: AppBar(
            title: Text(app.t('history.save_title')),
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          body: PageBody(
            children: [
              BrandCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Heading(app.t('fabrics.images')),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < images.length; i++)
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  decodeDataImage(images[i]) ?? Uint8List(0),
                                  width: 88,
                                  height: 88,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton.filledTonal(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setState(() => images.removeAt(i)),
                                  icon: const Icon(Icons.close, size: 16),
                                ),
                              ),
                            ],
                          ),
                        OutlinedButton.icon(
                          onPressed: () => addImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(app.t('history.album')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => addImage(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: Text(app.t('history.camera')),
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
                    Heading(app.t('fabrics.data')),
                    const SizedBox(height: 8),
                    for (var i = 0; i < fields.length; i++)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: fields[i].$1,
                              decoration: InputDecoration(hintText: app.t('history.key')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: fields[i].$2,
                              decoration: InputDecoration(hintText: app.t('history.value')),
                            ),
                          ),
                          IconButton(
                            onPressed: fields.length == 1
                                ? null
                                : () => setState(() {
                                    final removed = fields.removeAt(i);
                                    removed.$1.dispose();
                                    removed.$2.dispose();
                                  }),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ),
                    TextButton.icon(
                      onPressed: () => setState(
                        () => fields.add((TextEditingController(), TextEditingController())),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(app.t('history.add_field')),
                    ),
                  ],
                ),
              ),
              FilledButton(onPressed: app.busy ? null : submit, child: Text(app.t('history.save'))),
            ],
          ),
        ),
      ),
    );
  }
}

Uint8List? decodeDataImage(String source) {
  if (source.isEmpty) return null;
  final comma = source.indexOf(',');
  try {
    final decoded = base64Decode(comma >= 0 ? source.substring(comma + 1) : source);
    return decoded.isEmpty ? null : decoded;
  } catch (_) {
    return null;
  }
}
