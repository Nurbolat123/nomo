import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nomo_core/nomo_core.dart';

import '../state/ride_controller.dart';
import 'sheet_card.dart';

/// No destination yet: pickup address, "Where to?" and saved places.
class IdlePanel extends ConsumerWidget {
  const IdlePanel({super.key, required this.state, required this.onSearch, required this.onEditFrom});
  final RideState state;
  final VoidCallback onSearch;
  final VoidCallback onEditFrom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final pickup = state.pickup?.addr ?? '';
    return SheetCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (state.locationDenied)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              const Icon(Icons.location_off_rounded, color: NomoColors.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(t.t('location_needed'))),
              TextButton(onPressed: Geolocator.openAppSettings, child: Text(t.t('open_settings'))),
            ]),
          ),
        Container(
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            InkWell(
              onTap: onEditFrom,
              child: SizedBox(
                height: 48,
                child: Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: cs.onSurface, shape: BoxShape.circle)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      pickup.isEmpty ? t.t('current_location') : pickup,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ),
            Divider(height: 1, color: cs.outline),
            InkWell(
              onTap: onSearch,
              child: SizedBox(
                height: 56,
                child: Row(children: [
                  Container(width: 10, height: 10, color: cs.onSurface),
                  const SizedBox(width: 14),
                  Text(t.t('where_to'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                ]),
              ),
            ),
          ]),
        ),
        if (state.places.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: state.places.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final p = state.places[i];
                return ActionChip(
                  avatar: Icon(p.label == t.t('home') ? Icons.home_rounded : p.label == t.t('work') ? Icons.work_rounded : Icons.star_rounded, size: 18),
                  label: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () => ref.read(rideProvider.notifier).setDestination(p.place).catchError((Object e) {
                    if (context.mounted) showError(context, e);
                  }),
                );
              },
            ),
          ),
        ],
      ]),
    );
  }
}
