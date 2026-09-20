import 'package:flutter/material.dart';

const indigo = Color(0xFF2E45B8);
const cyan = Color(0xFF14A6B8);
const muted = Color(0xFF727782);

ThemeData fabricTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: indigo,
    primary: indigo,
    secondary: cyan,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: const Color(0xFFF2F3F7),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontFamily: 'Roboto',
      fontFamilyFallback: ['PingFang SC', 'Noto Sans CJK SC'],
      color: Color(0xFF20232B),
      fontSize: 26,
      fontWeight: FontWeight.w700,
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E6EB))),
    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E6EB))),
    contentPadding: EdgeInsets.symmetric(vertical: 16),
  ),
  dividerTheme: const DividerThemeData(color: Color(0xFFE8E9ED), thickness: 1),
);

class BrandCard extends StatelessWidget {
  const BrandCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: .65)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .05),
          blurRadius: 28,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.padding = 16});
  final List<Widget> children;
  final double padding;
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF0F5FF), Color(0xFFF2F3F7)],
      ),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class Heading extends StatelessWidget {
  const Heading(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600));
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final IconData icon;
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 55, horizontal: 12),
    child: Column(
      children: [
        Icon(icon, size: 58, color: muted),
        const SizedBox(height: 18),
        Heading(title),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
        if (action != null) ...[const SizedBox(height: 22), action!],
      ],
    ),
  );
}

class SignalBars extends StatelessWidget {
  const SignalBars(this.level, {super.key});
  final int level;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      for (var i = 1; i <= 3; i++)
        Container(
          width: 3,
          height: 5.0 + i * 3,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: i <= level ? cyan : Colors.black12,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
    ],
  );
}
