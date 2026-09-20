import 'dart:async';

import 'package:flutter/material.dart';

import '../app_model.dart';
import 'design.dart';

class AuthPage extends StatefulWidget {
  const AuthPage(this.app, {super.key});
  final AppModel app;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final account = TextEditingController(),
      password = TextEditingController(),
      username = TextEditingController(),
      confirm = TextEditingController(),
      code = TextEditingController(),
      company = TextEditingController();
  bool registering = false;
  int cooldown = 0;
  String industry = 'research';
  Timer? timer;
  static const industries = {
    'research': '科研人员',
    'inspection': '检测人员',
    'manufacturer': '生产商',
    'personal': '个人自用',
    'trade': '贸易行业',
  };
  @override
  void dispose() {
    timer?.cancel();
    for (final c in [account, password, username, confirm, code, company]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> sendCode() async {
    if (!await widget.app.sendCode(account.text) || !mounted) return;
    setState(() => cooldown = 60);
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => cooldown--);
      if (cooldown == 0) t.cancel();
    });
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    await widget.app.authenticate(
      account.text,
      password.text,
      username: registering ? username.text : null,
      confirm: confirm.text,
      code: code.text,
      company: company.text,
      industry: industries[industry]!,
    );
  }

  Widget field(
    TextEditingController controller,
    String key, {
    bool secret = false,
    TextInputType? keyboard,
    List<String>? hints,
  }) => TextField(
    controller: controller,
    obscureText: secret,
    keyboardType: keyboard,
    autocorrect: false,
    enableSuggestions: !secret,
    autofillHints: hints,
    decoration: InputDecoration(hintText: widget.app.t(key)),
    onChanged: (_) => setState(() {}),
  );
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final canSubmit =
        !app.busy &&
        account.text.trim().isNotEmpty &&
        password.text.length >= 6 &&
        (!registering ||
            (username.text.trim().isNotEmpty &&
                password.text == confirm.text &&
                code.text.trim().length >= 4));
    return Scaffold(
      body: SafeArea(
        child: PageBody(
          padding: 24,
          children: [
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF596FD1), indigo]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.monitor_heart_outlined, color: Colors.white, size: 32),
              ),
            ),
            const Text('FabricLab', style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
            Text(app.t('auth.tagline'), style: const TextStyle(color: muted, fontSize: 16)),
            Text(
              app.t(app.allowsPhone ? 'auth.region_cn' : 'auth.region_intl'),
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            BrandCard(
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Heading(app.t(registering ? 'auth.register_title' : 'auth.login_title')),
                    if (registering)
                      field(username, 'auth.username', hints: [AutofillHints.nickname]),
                    field(
                      account,
                      app.allowsPhone ? 'auth.account_cn' : 'auth.account_intl',
                      keyboard: TextInputType.emailAddress,
                      hints: [AutofillHints.username],
                    ),
                    field(
                      password,
                      'auth.password',
                      secret: true,
                      hints: [registering ? AutofillHints.newPassword : AutofillHints.password],
                    ),
                    if (registering) ...[
                      field(
                        confirm,
                        'auth.confirm_password',
                        secret: true,
                        hints: [AutofillHints.newPassword],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: field(
                              code,
                              'auth.code',
                              keyboard: TextInputType.number,
                              hints: [AutofillHints.oneTimeCode],
                            ),
                          ),
                          TextButton(
                            onPressed: cooldown > 0 || app.busy || account.text.trim().isEmpty
                                ? null
                                : sendCode,
                            child: Text(cooldown > 0 ? '${cooldown}s' : app.t('auth.get_code')),
                          ),
                        ],
                      ),
                      field(company, 'auth.company', hints: [AutofillHints.organizationName]),
                      DropdownButtonFormField<String>(
                        initialValue: industry,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: app.t('auth.industry')),
                        items: industries.keys
                            .map(
                              (key) =>
                                  DropdownMenuItem(value: key, child: Text(app.t('industry.$key'))),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => industry = value!),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: canSubmit ? submit : null,
                      child: Text(app.t(registering ? 'auth.register' : 'auth.login')),
                    ),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: app.busy ? null : () => setState(() => registering = !registering),
              child: Text(
                app.t(registering ? 'auth.to_login' : 'auth.to_register'),
                style: const TextStyle(color: muted),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, size: 18, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    app.t('auth.privacy'),
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
