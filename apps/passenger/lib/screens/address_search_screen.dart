import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomo_core/nomo_core.dart';

import '../state/ride_controller.dart';

class AddressPick {
  const AddressPick({this.from, this.to, this.pickToOnMap = false});
  final Place? from;
  final Place? to;
  final bool pickToOnMap;
}

/// Full-screen search for pickup and destination addresses.
class AddressSearchScreen extends ConsumerStatefulWidget {
  const AddressSearchScreen({super.key, this.from, this.to, this.editFrom = false});
  final Place? from;
  final Place? to;
  final bool editFrom;

  @override
  ConsumerState<AddressSearchScreen> createState() => _AddressSearchScreenState();
}

class _AddressSearchScreenState extends ConsumerState<AddressSearchScreen> {
  late final _fromCtl = TextEditingController(text: widget.from?.addr ?? '');
  late final _toCtl = TextEditingController(text: widget.to?.addr ?? '');
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();
  late bool _editingFrom = widget.editFrom;
  Place? _from;
  List<Place> _results = [];
  bool _loading = false;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.from;
    WidgetsBinding.instance.addPostFrameCallback((_) => (_editingFrom ? _fromFocus : _toFocus).requestFocus());
    _fromFocus.addListener(() {
      if (_fromFocus.hasFocus) setState(() => _editingFrom = true);
    });
    _toFocus.addListener(() {
      if (_toFocus.hasFocus) setState(() => _editingFrom = false);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _fromCtl.dispose();
    _toCtl.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(q));
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final near = widget.from;
    final r = await ref.read(geocoderProvider).search(q, nearLat: near?.lat, nearLng: near?.lng);
    if (!mounted || seq != _seq) return;
    setState(() {
      _results = r;
      _loading = false;
    });
  }

  void _choose(Place p) {
    if (_editingFrom) {
      _from = p;
      _fromCtl.text = p.addr;
      setState(() {
        _results = [];
        _editingFrom = false;
      });
      if (widget.to != null && !widget.editFrom) {
        Navigator.pop(context, AddressPick(from: p, to: widget.to));
      } else if (widget.editFrom && widget.to == null) {
        Navigator.pop(context, AddressPick(from: p));
      } else {
        _toFocus.requestFocus();
      }
      return;
    }
    Navigator.pop(context, AddressPick(from: _from != widget.from ? _from : null, to: p));
  }

  Future<void> _savePlace(Place p) async {
    final t = S.of(context);
    final ctl = TextEditingController(text: t.t('home'));
    final label = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.t('save_place')),
        content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(labelText: t.t('place_name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t.t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(t.t('save'))),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;
    try {
      await ref.read(apiProvider).addPlace(label, p);
      await ref.read(rideProvider.notifier).loadPlaces();
      if (mounted) showInfo(context, '✓ $label');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final places = ref.watch(rideProvider.select((s) => s.places));
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.t('where_to'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              _Field(
                controller: _fromCtl,
                focus: _fromFocus,
                hint: t.t('from'),
                marker: const _Dot(square: false),
                onChanged: _onChanged,
              ),
              Divider(height: 1, indent: 44, color: cs.outline),
              _Field(
                controller: _toCtl,
                focus: _toFocus,
                hint: t.t('where_to'),
                marker: const _Dot(square: true),
                onChanged: _onChanged,
                bold: true,
              ),
            ]),
          ),
        ),
        Expanded(
          child: ListView(children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (!_editingFrom)
              ListTile(
                leading: const Icon(Icons.pin_drop_outlined),
                title: Text(t.t('pick_on_map')),
                onTap: () => Navigator.pop(context, AddressPick(from: _from != widget.from ? _from : null, pickToOnMap: true)),
              ),
            if (_results.isEmpty)
              for (final p in places)
                ListTile(
                  leading: Icon(p.label == t.t('home') ? Icons.home_rounded : p.label == t.t('work') ? Icons.work_rounded : Icons.star_rounded),
                  title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(p.place.addr, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _choose(p.place),
                ),
            for (final r in _results)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(r.addr, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: IconButton(tooltip: t.t('save_place'), icon: const Icon(Icons.bookmark_add_outlined), onPressed: () => _savePlace(r)),
                onTap: () => _choose(r),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.focus, required this.hint, required this.marker, required this.onChanged, this.bold = false});
  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final Widget marker;
  final ValueChanged<String> onChanged;
  final bool bold;

  @override
  Widget build(BuildContext context) => Row(children: [
        const SizedBox(width: 16),
        marker,
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focus,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: TextStyle(fontSize: bold ? 18 : 16, fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
            decoration: InputDecoration(
              hintText: hint,
              filled: false,
              border: InputBorder.none,
              suffixIcon: IconButton(
                tooltip: S.of(context).t('cancel'),
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
            ),
          ),
        ),
      ]);
}

class _Dot extends StatelessWidget {
  const _Dot({required this.square});
  final bool square;

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface,
          shape: square ? BoxShape.rectangle : BoxShape.circle,
        ),
      );
}
