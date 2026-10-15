import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../strings.dart';
import '../theme.dart';

/// Shows an error as a snackbar.
void showError(BuildContext context, Object e) {
  final msg = e is ApiException ? e.message : S.of(context).t('error');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

void showInfo(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<void> openUrl(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
Future<void> dial(String phone) => launchUrl(Uri(scheme: 'tel', path: phone));

/// A filled button that shows a spinner while [onPressed] runs.
class BusyButton extends StatefulWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.color, this.textColor});
  final String label;
  final Future<void> Function()? onPressed;
  final Color? color;
  final Color? textColor;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.color == null ? null : FilledButton.styleFrom(backgroundColor: widget.color, foregroundColor: widget.textColor);
    return FilledButton(
      style: style,
      onPressed: widget.onPressed == null || _busy ? null : _run,
      child: _busy
          ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: widget.textColor ?? Theme.of(context).colorScheme.onPrimary))
          : Text(widget.label),
    );
  }
}

/// Round action button with a caption (call, chat, share…).
class RoundAction extends StatelessWidget {
  const RoundAction({super.key, required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: danger ? NomoColors.danger : cs.surfaceContainerHighest, shape: BoxShape.circle),
              child: Icon(icon, color: danger ? Colors.white : cs.onSurface),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Avatar circle with initials.
class Initials extends StatelessWidget {
  const Initials(this.name, {super.key, this.size = 48});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: NomoColors.black,
      child: Text(letter, style: TextStyle(color: NomoColors.gold, fontWeight: FontWeight.w800, fontSize: size * 0.42)),
    );
  }
}

class RatingBadge extends StatelessWidget {
  const RatingBadge(this.rating, {super.key});
  final double rating;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 16, color: NomoColors.gold),
        const SizedBox(width: 2),
        Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);
}

/// Five tappable stars.
class StarPicker extends StatelessWidget {
  const StarPicker({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              iconSize: 44,
              tooltip: '$i',
              onPressed: () => onChanged(i),
              icon: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, color: NomoColors.gold),
            ),
        ],
      );
}

Future<bool> confirm(BuildContext context, {required String title, String? text, required String ok, String? cancel, bool danger = false}) async {
  final s = S.of(context);
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: text == null ? null : Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(cancel ?? s.t('no'))),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok, style: TextStyle(color: danger ? NomoColors.danger : null, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return r == true;
}
