import 'package:flutter/material.dart';
import 'package:nomo_core/nomo_core.dart';

/// Prominent disclosure shown before the location permission prompt and the
/// first time the driver goes online (Google Play user-data policy).
class LocationDisclosure {
  static bool _accepted = false;

  static Future<bool> accepted(BuildContext context) async {
    if (_accepted) return true;
    final t = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.location_on_rounded, size: 36),
        title: Text(t.t('bg_location_title')),
        content: Text(t.t('bg_location_text')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.t('not_now'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.t('allow')),
          ),
        ],
      ),
    );
    _accepted = ok == true;
    return _accepted;
  }
}
