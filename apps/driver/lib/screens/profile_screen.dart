import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomo_core/nomo_core.dart';

import '../state/driver_controller.dart';

class DriverProfileScreen extends ConsumerWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = S.of(context);
    final p = ref.watch(driverProvider.select((s) => s.profile));
    return Scaffold(
      appBar: AppBar(title: Text(t.t('profile'))),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Initials(p.name, size: 52),
                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                subtitle: Text(prettyPhone(p.phone)),
                trailing: RatingBadge(p.rating),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.directions_car_filled_rounded),
                title: Text('${p.carColor} ${p.carMake} ${p.carModel}, ${p.carYear}'),
                subtitle: Text(p.carPlate),
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text(p.classes.join(', ')),
              ),
              const Divider(),
              const AccountSettingsSection(),
              const SizedBox(height: 24),
            ]),
    );
  }
}
