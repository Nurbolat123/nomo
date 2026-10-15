import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nomo_core/nomo_core.dart';

import '../state/driver_controller.dart';

const _docKinds = ['license', 'sts', 'osago', 'car_photo', 'selfie'];

/// Sign-up: name and car, five document photos, submit for review, status.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  late final DriverProfile _p = ref.read(driverProvider).profile!;
  late final _name = TextEditingController(text: _p.name);
  late final _make = TextEditingController(text: _p.carMake);
  late final _model = TextEditingController(text: _p.carModel);
  late final _color = TextEditingController(text: _p.carColor);
  late final _plate = TextEditingController(text: _p.carPlate);
  late final _year = TextEditingController(text: _p.carYear == 0 ? '' : '${_p.carYear}');
  final Set<String> _uploading = {};

  @override
  void dispose() {
    for (final c in [_name, _make, _model, _color, _plate, _year]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveCar() async {
    if (!_form.currentState!.validate()) throw ApiException(S.of(context).t('reg_car'));
    await ref.read(apiProvider).updateCar(
          name: _name.text.trim(),
          make: _make.text.trim(),
          model: _model.text.trim(),
          color: _color.text.trim(),
          plate: _plate.text.trim(),
          year: int.parse(_year.text.trim()),
        );
    await ref.read(driverProvider.notifier).reloadProfile();
  }

  Future<void> _upload(String kind) async {
    final t = S.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Камера'), onTap: () => Navigator.pop(c, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Галерея'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2000,
      imageQuality: 85,
      preferredCameraDevice: kind == 'selfie' ? CameraDevice.front : CameraDevice.rear,
    );
    if (file == null) return;
    setState(() => _uploading.add(kind));
    try {
      await ref.read(apiProvider).uploadDocument(kind, file.path);
      await ref.read(driverProvider.notifier).reloadProfile();
      if (mounted) showInfo(context, t.t('uploaded'));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading.remove(kind));
    }
  }

  Future<void> _submit() async {
    await _saveCar();
    await ref.read(apiProvider).submitForReview();
    await ref.read(driverProvider.notifier).reloadProfile();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? '—' : null;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final p = ref.watch(driverProvider.select((s) => s.profile))!;
    final pending = p.status == 'pending';
    final allDocs = _docKinds.every(p.hasDoc);
    return Scaffold(
      appBar: AppBar(
        title: const NomoLogo(size: 26, suffix: 'driver'),
        actions: [
          IconButton(tooltip: t.t('logout'), icon: const Icon(Icons.logout_rounded), onPressed: () => ref.read(authProvider.notifier).signOut()),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(driverProvider.notifier).reloadProfile(),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          if (p.status != 'new') _StatusCard(profile: p),
          Text(t.t('reg_title'), style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          Text(t.t('reg_car'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Form(
            key: _form,
            child: Column(children: [
              _field(_name, t.t('name'), TextCapitalization.words),
              Row(children: [
                Expanded(child: _field(_make, t.t('car_make'), TextCapitalization.words)),
                const SizedBox(width: 10),
                Expanded(child: _field(_model, t.t('car_model'), TextCapitalization.words)),
              ]),
              Row(children: [
                Expanded(child: _field(_color, t.t('car_color'), TextCapitalization.sentences)),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(_year, t.t('car_year'), TextCapitalization.none,
                      keyboard: TextInputType.number,
                      validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1990 ? '—' : null),
                ),
              ]),
              _field(_plate, t.t('car_plate'), TextCapitalization.characters),
            ]),
          ),
          const SizedBox(height: 16),
          Text(t.t('reg_docs'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final k in _docKinds)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(p.hasDoc(k) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: p.hasDoc(k) ? NomoColors.success : null),
              title: Text(t.t('doc_$k')),
              trailing: _uploading.contains(k)
                  ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : TextButton(onPressed: () => _upload(k), child: Text(p.hasDoc(k) ? t.t('uploaded') : t.t('upload'))),
            ),
          const SizedBox(height: 24),
          BusyButton(label: t.t('submit_review'), onPressed: allDocs && !pending ? _submit : null),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, TextCapitalization cap,
          {TextInputType? keyboard, String? Function(String?)? validator}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: c,
          textCapitalization: cap,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label),
          validator: validator ?? _required,
        ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.profile});
  final DriverProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final (title, text, color) = switch (profile.status) {
      'pending' => (t.t('status_pending'), t.t('status_pending_hint'), NomoColors.gold),
      'rejected' => (t.t('status_rejected'), profile.statusNote, NomoColors.danger),
      _ => (t.t('status_blocked'), profile.statusNote, NomoColors.danger),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: color, width: 2), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        if (text.isNotEmpty) ...[const SizedBox(height: 4), Text(text)],
      ]),
    );
  }
}
