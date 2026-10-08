import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../app_model.dart';
import '../gsm.dart';
import 'design.dart';

class GsmDataPage extends StatefulWidget {
  const GsmDataPage(this.app, this.dataId, {super.key});
  final AppModel app;
  final String dataId;
  @override
  State<GsmDataPage> createState() => _GsmDataPageState();
}

class _GsmDataPageState extends State<GsmDataPage> {
  final picker = ImagePicker();
  final controllers = <String, TextEditingController>{};
  GsmDetail? detail;
  List<GsmField> custom = [];
  String weaving = '';
  String customImage = '';
  String error = '';
  bool loading = true;
  bool dirty = false;
  bool changed = false;
  bool adding = false;
  int editing = -1;
  final label = TextEditingController();
  final value = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final name in [...gsmCommonLabels, ...gsmWovenLabels, ...gsmKnitLabels]) {
      if (name == '织造方式') continue;
      controllers[name] = TextEditingController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    label.dispose();
    value.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final loaded = await widget.app.gsmApi.detail(widget.dataId);
      if (!mounted) return;
      for (final entry in controllers.entries) {
        entry.value.text = loaded.extra[entry.key] ?? '';
      }
      setState(() {
        detail = loaded;
        weaving = loaded.extra['织造方式'] ?? '';
        customImage = loaded.extra['custom_image'] ?? '';
        custom = gsmCustomFields(loaded.extra);
        dirty = false;
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

  void _mark() => setState(() => dirty = true);

  void _cancelCommon() {
    final loaded = detail;
    if (loaded == null) return;
    for (final entry in controllers.entries) {
      entry.value.text = loaded.extra[entry.key] ?? '';
    }
    setState(() {
      weaving = loaded.extra['织造方式'] ?? '';
      dirty = false;
    });
  }

  Map<String, String> _payload() {
    final data = <String, String>{};
    for (final field in custom) {
      data[field.label] = field.value;
    }
    for (final name in gsmCommonLabels) {
      if (name == '织造方式') {
        if (weaving.trim().isNotEmpty) data[name] = weaving.trim();
        continue;
      }
      final text = controllers[name]?.text.trim() ?? '';
      if (text.isNotEmpty) data[name] = text;
    }
    for (final name in gsmDynamicLabels(weaving)) {
      final text = controllers[name]?.text.trim() ?? '';
      if (text.isNotEmpty) data[name] = text;
    }
    if (customImage.isNotEmpty) data['custom_image'] = customImage;
    return data;
  }

  Future<bool> _save() async {
    final current = detail;
    if (current == null) return false;
    final extra = _payload();
    final ok = await widget.app.perform(() => widget.app.gsmApi.saveExtra(current.id, extra));
    if (!ok || !mounted) return false;
    setState(() {
      detail = GsmDetail(
        id: current.id,
        time: current.time,
        gsm: current.gsm,
        unit: current.unit,
        image: current.image,
        extra: extra,
      );
      dirty = false;
      changed = true;
      adding = false;
      editing = -1;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.app.t('gsm.saved'))));
    return true;
  }

  Future<void> _commitField() async {
    final name = label.text.trim();
    final text = value.text.trim();
    if (name.isEmpty || text.isEmpty) {
      widget.app.showMessage(widget.app.t('gsm.field_required'));
      return;
    }
    if (gsmReservedKeys.contains(name)) {
      widget.app.showMessage(widget.app.t('gsm.field_reserved'));
      return;
    }
    setState(() {
      final next = [...custom];
      if (editing >= 0 && editing < next.length) {
        next[editing] = GsmField(name, text);
      } else {
        next.add(GsmField(name, text));
      }
      custom = next;
      adding = false;
      editing = -1;
      label.clear();
      value.clear();
    });
    await _save();
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await picker.pickImage(source: source, imageQuality: 40, maxWidth: 1280);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => customImage = base64Encode(bytes));
    await _save();
  }

  Future<void> _chooseImage() async {
    final app = widget.app;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: Text(app.t('history.album')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(app.t('history.camera')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickImage(source);
  }

  Future<void> _share() async {
    final current = detail;
    if (current == null) return;
    final buffer = StringBuffer()
      ..writeln('${widget.app.t('gsm.detail_gsm')}: ${current.gsm} ${current.unit}')
      ..writeln('${widget.app.t('gsm.detail_time')}: ${current.time}');
    for (final entry in _payload().entries) {
      if (entry.key == 'custom_image') continue;
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.app.t('gsm.copied'))));
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final current = detail;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (dirty) {
          final leave = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(app.t('common.alert')),
              content: Text(app.t('gsm.unsaved')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(app.t('common.cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(app.t('common.ok')),
                ),
              ],
            ),
          );
          if (leave != true || !context.mounted) return;
        }
        if (context.mounted) Navigator.pop(context, changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(app.t('gsm.detail_title'))),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : current == null
            ? PageBody(
                children: [
                  EmptyPanel(
                    icon: Icons.error_outline,
                    title: error.isEmpty ? app.t('error.decode') : error,
                    subtitle: app.t('gsm.retry'),
                    action: OutlinedButton(onPressed: _load, child: Text(app.t('gsm.retry'))),
                  ),
                ],
              )
            : PageBody(
                children: [
                  BrandCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Heading(app.t('gsm.common')),
                        const SizedBox(height: 8),
                        for (final name in gsmCommonLabels)
                          if (name == '织造方式')
                            DropdownButtonFormField<String>(
                              key: ValueKey(weaving),
                              initialValue: weaving == gsmWeavingWoven || weaving == gsmWeavingKnit
                                  ? weaving
                                  : null,
                              isExpanded: true,
                              decoration: InputDecoration(labelText: name),
                              items: const [
                                DropdownMenuItem(
                                  value: gsmWeavingWoven,
                                  child: Text(gsmWeavingWoven),
                                ),
                                DropdownMenuItem(
                                  value: gsmWeavingKnit,
                                  child: Text(gsmWeavingKnit),
                                ),
                              ],
                              onChanged: adding
                                  ? null
                                  : (value) => setState(() {
                                      weaving = value ?? '';
                                      dirty = true;
                                    }),
                            )
                          else
                            TextField(
                              controller: controllers[name],
                              decoration: InputDecoration(labelText: name),
                              onChanged: (_) => _mark(),
                            ),
                        for (final name in gsmDynamicLabels(weaving))
                          TextField(
                            controller: controllers[name],
                            decoration: InputDecoration(labelText: name),
                            onChanged: (_) => _mark(),
                          ),
                        if (dirty) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _cancelCommon,
                                  child: Text(app.t('common.cancel')),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _save,
                                  child: Text(app.t('gsm.save')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (custom.isNotEmpty || customImage.isNotEmpty || adding)
                    BrandCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Heading(app.t('gsm.custom')),
                          if (customImage.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _image(customImage, 180),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () async {
                                  setState(() => customImage = '');
                                  await _save();
                                },
                                child: Text(
                                  app.t('gsm.delete'),
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ),
                          ],
                          for (var i = 0; i < custom.length; i++)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('${custom[i].label}: ${custom[i].value}'),
                              trailing: IconButton(
                                onPressed: () async {
                                  setState(() => custom = [...custom]..removeAt(i));
                                  await _save();
                                },
                                icon: const Icon(Icons.close, color: muted),
                              ),
                              onTap: () => setState(() {
                                adding = true;
                                editing = i;
                                label.text = custom[i].label;
                                value.text = custom[i].value;
                              }),
                            ),
                          if (adding) ...[
                            TextField(
                              controller: label,
                              maxLength: 20,
                              decoration: InputDecoration(labelText: app.t('gsm.label')),
                            ),
                            TextField(
                              controller: value,
                              maxLength: 50,
                              decoration: InputDecoration(labelText: app.t('gsm.value')),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => setState(() {
                                      adding = false;
                                      editing = -1;
                                      label.clear();
                                      value.clear();
                                    }),
                                    child: Text(app.t('common.cancel')),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _commitField,
                                    child: Text(app.t('gsm.confirm')),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (!adding)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => setState(() {
                              adding = true;
                              editing = -1;
                              label.clear();
                              value.clear();
                            }),
                            icon: const Icon(Icons.add),
                            label: Text(app.t('gsm.add_custom')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _chooseImage,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: Text(app.t('gsm.add_image')),
                          ),
                        ),
                      ],
                    ),
                  BrandCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${app.t('gsm.detail_time')}: ${current.time}'),
                        const SizedBox(height: 8),
                        Text('${app.t('gsm.detail_gsm')}: ${current.gsm} ${current.unit}'),
                        if (current.image.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(app.t('gsm.detail_image')),
                          const SizedBox(height: 8),
                          _image(current.image, 220),
                        ],
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share_outlined),
                    label: Text(app.t('gsm.share_data')),
                  ),
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.help_outline),
                    label: Text(app.t('gsm.find_supplier')),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _image(String raw, double height) {
    final bytes = decodeGsmImage(raw);
    if (bytes == null) {
      return Text(widget.app.t('error.image_failed'), style: const TextStyle(color: muted));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(bytes, height: height, width: double.infinity, fit: BoxFit.contain),
    );
  }
}
