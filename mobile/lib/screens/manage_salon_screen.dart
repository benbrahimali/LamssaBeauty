import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../core/env.dart';
import '../data/repositories/salon_admin_repository.dart';
import '../data/repositories/salon_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import '../widgets/common_widgets.dart';
import '../widgets/reviews_moderation_sheet.dart';
import '../widgets/team_ranking_sheet.dart';
import '../widgets/time_off_sheet.dart';

/// Gestion du salon par son gérant : catalogue et équipe (§3.1, §3.5).
class ManageSalonScreen extends StatefulWidget {
  const ManageSalonScreen({
    super.key,
    required this.salonId,
    required this.salonName,
  });

  final String salonId;
  final String salonName;

  @override
  State<ManageSalonScreen> createState() => _ManageSalonScreenState();
}

class _ManageSalonScreenState extends State<ManageSalonScreen> {
  int _tab = 0;
  List<ServiceItem> _services = const [];
  List<Coiffeur> _team = const [];
  List<String> _photos = const [];
  bool _uploading = false;
  bool _loading = true;
  String? _error;

  SalonAdminRepository get _repo => context.read<SalonAdminRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.services(widget.salonId),
        _repo.staff(widget.salonId),
        // La fiche publique porte déjà les photos : pas besoin d'une route
        // dédiée pour les relire.
        context.read<SalonRepository>().detail(widget.salonId),
      ]);
      if (!mounted) return;
      setState(() {
        _services = results[0] as List<ServiceItem>;
        _team = results[1] as List<Coiffeur>;
        _photos = (results[2] as SalonDetail).salon.photos;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Exécute une action d'administration et resynchronise, en affichant
  /// l'erreur du serveur telle quelle (409 sur suppression d'un coiffeur
  /// occupé, par exemple).
  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      if (!mounted) return;
      await _load();
      if (mounted) showAppSnack(context, success, success: true);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message);
    }
  }

  // ── Services ───────────────────────────────────────────────────────────
  Future<void> _editService([ServiceItem? existing]) async {
    final payload = await showModalBottomSheet<_ServicePayload>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ServiceSheet(existing: existing),
    );
    if (payload == null || !mounted) return;

    await _run(
      () => existing == null
          ? _repo.createService(
              widget.salonId,
              name: payload.name,
              nameAr: payload.nameAr,
              price: payload.price,
              durationMin: payload.durationMin,
              bufferMin: payload.bufferMin,
            )
          : _repo.updateService(
              widget.salonId,
              existing.id,
              name: payload.name,
              nameAr: payload.nameAr,
              price: payload.price,
              durationMin: payload.durationMin,
              bufferMin: payload.bufferMin,
            ),
      existing == null ? 'الخدمة تزادت ✅' : 'الخدمة تبدّلت ✅',
    );
  }

  Future<void> _deleteService(ServiceItem service) async {
    final ok = await _confirm(
      'تنحّي « ${service.name} » ؟',
      'الخدمة ما تبقاش معروضة، أما الحجوزات القديمة تبقى موجودة.',
    );
    if (ok != true) return;
    await _run(
      () => _repo.deleteService(widget.salonId, service.id),
      'الخدمة تنحّات',
    );
  }

  // ── Équipe ─────────────────────────────────────────────────────────────
  Future<void> _editStaff([Coiffeur? existing]) async {
    if (_services.isEmpty) {
      showAppSnack(context, 'زيد خدمة قبل ما تزيد حجام');
      return;
    }
    final payload = await showModalBottomSheet<_StaffPayload>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StaffSheet(existing: existing, services: _services),
    );
    if (payload == null || !mounted) return;

    await _run(
      () => existing == null
          ? _repo.addStaff(
              widget.salonId,
              phone: payload.phone,
              displayName: payload.name,
              chairNumber: payload.chair,
              commissionPct: payload.commissionPct,
              serviceIds: payload.serviceIds,
            )
          : _repo.updateStaff(
              widget.salonId,
              existing.id,
              displayName: payload.name,
              chairNumber: payload.chair,
              commissionPct: payload.commissionPct,
              serviceIds: payload.serviceIds,
            ),
      existing == null ? 'الحجام تزاد ✅' : 'المعطيات تبدّلت ✅',
    );
  }

  Future<void> _removeStaff(Coiffeur member) async {
    final ok = await _confirm(
      'تنحّي ${member.name} ؟',
      'ما ينجمش يتنحّى كان عندو مواعيد جاية.',
    );
    if (ok != true) return;
    await _run(
      () => _repo.removeStaff(widget.salonId, member.id),
      'الحجام تنحّى',
    );
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.card2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: AppTextStyle.playfair(size: 17)),
          content: Text(body,
              style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('رجوع',
                  style: AppTextStyle.dmSans(color: AppColors.sub)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('نحّي',
                  style: AppTextStyle.dmSans(
                      color: AppColors.red, weight: FontWeight.w700)),
            ),
          ],
        ),
      );

  Widget _photosGrid() {
    if (_photos.isEmpty) {
      return const AppEmpty(
        emoji: '📷',
        title: 'ما فماش تصاور',
        subtitle: 'الحرفاء يختارو بعينيهم — زيد تصاور الصالون',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _photos.length,
      itemBuilder: (_, i) => GestureDetector(
        onLongPress: () => _removePhoto(_photos[i]),
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: Env.mediaUrl(_photos[i]),
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.card2),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.card2,
                alignment: Alignment.center,
                child: const Text('🖼️', style: TextStyle(fontSize: 24)),
              ),
            ),
          ),
          if (i == 0)
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(50),
                ),
                // La première photo est celle qui représente le salon partout
                // ailleurs : le gérant doit savoir laquelle c'est.
                child: Text('الرئيسية',
                    style: AppTextStyle.dmSans(
                        size: 10,
                        color: Colors.black,
                        weight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _addPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Réduit avant l'envoi : le serveur refuse au-delà de MAX_UPLOAD_MB, et
      // une photo de 8 Mo prend une éternité en 3G.
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final photos = await _repo.addPhoto(widget.salonId, File(picked.path));
      if (!mounted) return;
      setState(() => _photos = photos);
      showAppSnack(context, 'التصويرة تزادت ✅', success: true);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto(String url) async {
    final ok = await _confirm('تنحّي التصويرة ؟', 'ما تنجّمش ترجّعها بعد.');
    if (ok != true) return;
    try {
      final photos = await _repo.removePhoto(widget.salonId, url);
      if (!mounted) return;
      setState(() => _photos = photos);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton(
              backgroundColor: AppColors.gold,
              onPressed: _uploading
                  ? null
                  : () => switch (_tab) {
                        0 => _editService(),
                        1 => _editStaff(),
                        _ => _addPhoto(),
                      },
              child: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.black),
                    )
                  : const Icon(Icons.add_rounded, color: Colors.black),
            ),
      body: Column(
        children: [
          _header(),
          _tabs(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 16, 20, 12),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.arrow_back_rounded,
                size: 20, color: AppColors.text),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('إدارة الصالون',
                style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
            Text(widget.salonName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.playfair(size: 20)),
          ]),
        ),
        GestureDetector(
          onTap: () => ReviewsModerationSheet.show(context, widget.salonId),
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.star_rounded, size: 19, color: AppColors.gold),
          ),
        ),
        // Classement réservé au gérant : outil de motivation interne, pas
        // argument de vitrine — publié, il exposerait les moins bien notés.
        GestureDetector(
          onTap: () => TeamRankingSheet.show(context, widget.salonId),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.emoji_events_rounded,
                size: 19, color: AppColors.gold),
          ),
        ),
      ]),
    );
  }

  Widget _tabs() {
    final labels = [
      'الخدمات (${_services.length})',
      'الفريق (${_team.length})',
      'التصاور (${_photos.length})',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: List.generate(labels.length, (i) {
            final active = _tab == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: active ? AppColors.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(labels[i],
                      style: AppTextStyle.dmSans(
                        size: 13,
                        weight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active ? Colors.black : AppColors.sub,
                      )),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const AppLoader();
    if (_error != null) return AppError(message: _error!, onRetry: _load);
    return switch (_tab) {
      0 => _servicesList(),
      1 => _teamList(),
      _ => _photosGrid(),
    };
  }

  Widget _servicesList() {
    if (_services.isEmpty) {
      return const AppEmpty(
        emoji: '✂️',
        title: 'ما فماش خدمات',
        subtitle: 'زيد خدمة بالزر الذهبي — بلا خدمات الحرفاء ما ينجموش يحجزو.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: _services.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final service = _services[i];
        final title =
            service.nameAr.trim().isNotEmpty ? service.nameAr : service.name;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Text(service.icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.dmSans(
                            size: 14, weight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                        '⏱ ${service.duration} دقيقة · +${service.bufferMin} فاصل',
                        style: AppTextStyle.dmSans(
                            size: 11, color: AppColors.sub)),
                  ]),
            ),
            Text('${service.price.toStringAsFixed(0)} DT',
                style: AppTextStyle.playfair(size: 16, color: AppColors.gold)),
            const SizedBox(width: 6),
            _menu(
              onEdit: () => _editService(service),
              onDelete: () => _deleteService(service),
            ),
          ]),
        );
      },
    );
  }

  Widget _teamList() {
    if (_team.isEmpty) {
      return const AppEmpty(
        emoji: '👥',
        title: 'ما فماش فريق',
        subtitle: 'زيد حجام برقم تليفونو — الحساب يتعمل وحدو.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: _team.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final member = _team[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            InitialsAvatar(
              initials: member.initials,
              color: member.color,
              size: 46,
              showBadge: true,
              available: member.available,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.dmSans(
                            size: 14, weight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      'كرسي ${member.chairNumber} · '
                      'نسبة ${member.commissionPct.toStringAsFixed(0)}% · '
                      '${member.serviceIds.isEmpty ? 'كل الخدمات' : '${member.serviceIds.length} خدمة'}',
                      style:
                          AppTextStyle.dmSans(size: 11, color: AppColors.sub),
                    ),
                  ]),
            ),
            _menu(
              onEdit: () => _editStaff(member),
              onDelete: () => _removeStaff(member),
              onTimeOff: () => TimeOffSheet.show(
                context,
                salonId: widget.salonId,
                member: member,
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _menu({
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    VoidCallback? onTimeOff,
  }) {
    return PopupMenuButton<String>(
      color: AppColors.card2,
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.sub, size: 20),
      onSelected: (value) => switch (value) {
        'edit' => onEdit(),
        'timeoff' => onTimeOff?.call(),
        _ => onDelete(),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: Text('بدّل', style: AppTextStyle.dmSans(size: 13)),
        ),
        // Absent pour les services : seuls les coiffeurs prennent des congés.
        if (onTimeOff != null)
          PopupMenuItem(
            value: 'timeoff',
            child: Text('العطل', style: AppTextStyle.dmSans(size: 13)),
          ),
        PopupMenuItem(
          value: 'delete',
          child: Text('نحّي',
              style: AppTextStyle.dmSans(size: 13, color: AppColors.red)),
        ),
      ],
    );
  }
}

// ── Feuille service ────────────────────────────────────────────────────────
class _ServicePayload {
  final String name;
  final String nameAr;
  final double price;
  final int durationMin;
  final int bufferMin;

  const _ServicePayload({
    required this.name,
    required this.nameAr,
    required this.price,
    required this.durationMin,
    required this.bufferMin,
  });
}

class _ServiceSheet extends StatefulWidget {
  const _ServiceSheet({this.existing});
  final ServiceItem? existing;

  @override
  State<_ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends State<_ServiceSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _nameAr;
  late final TextEditingController _price;
  late final TextEditingController _duration;
  late final TextEditingController _buffer;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _nameAr = TextEditingController(text: e?.nameAr ?? '');
    _price = TextEditingController(
        text: e == null ? '' : e.price.toStringAsFixed(0));
    _duration = TextEditingController(text: e == null ? '30' : '${e.duration}');
    _buffer = TextEditingController(text: e == null ? '10' : '${e.bufferMin}');
  }

  @override
  void dispose() {
    for (final c in [_name, _nameAr, _price, _duration, _buffer]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: widget.existing == null ? 'خدمة جديدة' : 'بدّل الخدمة',
      child: Form(
        key: _formKey,
        child: Column(children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            style: AppTextStyle.dmSans(size: 15),
            decoration: const InputDecoration(hintText: 'Nom (Skin fade)'),
            validator: (v) => (v ?? '').trim().length < 2
                ? 'حطّ اسم (حرفين على الأقل)'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nameAr,
            style: AppTextStyle.dmSans(size: 15),
            decoration:
                const InputDecoration(hintText: 'الاسم بالعربي (اختياري)'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: AppTextStyle.dmSans(size: 15),
                decoration: const InputDecoration(hintText: 'السعر (DT)'),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim()) ?? 0;
                  return n <= 0 ? 'سعر غالط' : null;
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _duration,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: AppTextStyle.dmSans(size: 15),
                decoration: const InputDecoration(hintText: 'المدة (دق)'),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim()) ?? 0;
                  return n <= 0 || n > 600 ? 'بين 1 و 600' : null;
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _buffer,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: AppTextStyle.dmSans(size: 15),
            decoration: const InputDecoration(
              hintText: 'وقت الفاصل بين موعدين (دق)',
            ),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim()) ?? -1;
              return n < 0 || n > 120 ? 'بين 0 و 120' : null;
            },
          ),
          const SizedBox(height: 20),
          GoldButton(
            text: 'سجّل',
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                _ServicePayload(
                  name: _name.text.trim(),
                  nameAr: _nameAr.text.trim(),
                  price: double.parse(_price.text.trim()),
                  durationMin: int.parse(_duration.text.trim()),
                  bufferMin: int.parse(_buffer.text.trim()),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }
}

// ── Feuille coiffeur ───────────────────────────────────────────────────────
class _StaffPayload {
  final String phone;
  final String name;
  final int chair;
  final double commissionPct;
  final List<String> serviceIds;

  const _StaffPayload({
    required this.phone,
    required this.name,
    required this.chair,
    required this.commissionPct,
    required this.serviceIds,
  });
}

class _StaffSheet extends StatefulWidget {
  const _StaffSheet({this.existing, required this.services});
  final Coiffeur? existing;
  final List<ServiceItem> services;

  @override
  State<_StaffSheet> createState() => _StaffSheetState();
}

class _StaffSheetState extends State<_StaffSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  late final TextEditingController _name;
  late int _chair;
  late double _commission;
  late Set<String> _serviceIds;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _phone = TextEditingController();
    _name = TextEditingController(text: e?.name ?? '');
    _chair = e?.chairNumber ?? 1;
    _commission = e?.commissionPct ?? 50;
    _serviceIds = {...?e?.serviceIds};
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return _SheetShell(
      title: isNew ? 'زيد حجام' : 'بدّل الحجام',
      child: Form(
        key: _formKey,
        child: Column(children: [
          if (isNew) ...[
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                LengthLimitingTextInputFormatter(16),
              ],
              style: AppTextStyle.dmSans(size: 15),
              decoration: const InputDecoration(hintText: 'رقم التليفون'),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length < 8 ? 'رقم ناقص' : null;
              },
            ),
            const SizedBox(height: 6),
            Text(
              'كان ما عندوش حساب، يتعمّلو وحدو.',
              style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            style: AppTextStyle.dmSans(size: 15),
            decoration: const InputDecoration(hintText: 'الاسم'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'حطّ الاسم' : null,
          ),
          const SizedBox(height: 16),
          _row('الكرسي', '$_chair'),
          Slider(
            value: _chair.toDouble(),
            min: 1,
            max: 12,
            divisions: 11,
            activeColor: AppColors.gold,
            inactiveColor: AppColors.border,
            onChanged: (v) => setState(() => _chair = v.round()),
          ),
          _row('نسبتو', '${_commission.toStringAsFixed(0)}%'),
          Slider(
            value: _commission,
            min: 0,
            max: 100,
            divisions: 20,
            activeColor: AppColors.gold,
            inactiveColor: AppColors.border,
            onChanged: (v) => setState(() => _commission = v),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _serviceIds.isEmpty
                  ? 'الخدمات المسموحة : الكل'
                  : 'الخدمات المسموحة : ${_serviceIds.length}',
              style: AppTextStyle.dmSans(
                  size: 12, weight: FontWeight.w600, color: AppColors.sub),
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.services.map((service) {
                  final selected = _serviceIds.contains(service.id);
                  final title = service.nameAr.trim().isNotEmpty
                      ? service.nameAr
                      : service.name;
                  return GestureDetector(
                    onTap: () => setState(() {
                      selected
                          ? _serviceIds.remove(service.id)
                          : _serviceIds.add(service.id);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.gold.withValues(alpha: 0.15)
                            : AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                selected ? AppColors.gold : AppColors.border),
                      ),
                      child: Text(title,
                          style: AppTextStyle.dmSans(
                            size: 12,
                            color: selected ? AppColors.gold : AppColors.text,
                          )),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          GoldButton(
            text: 'سجّل',
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(
                context,
                _StaffPayload(
                  phone: _phone.text.trim(),
                  name: _name.text.trim(),
                  chair: _chair,
                  commissionPct: _commission,
                  serviceIds: _serviceIds.toList(),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }

  Widget _row(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTextStyle.dmSans(
                  size: 12, weight: FontWeight.w600, color: AppColors.sub)),
          Text(value,
              style: AppTextStyle.dmSans(size: 13, weight: FontWeight.w700)),
        ],
      );
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: const BoxDecoration(
          color: AppColors.card2,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(50),
              ),
            ),
            const SizedBox(height: 18),
            Text(title, style: AppTextStyle.playfair(size: 20)),
            const SizedBox(height: 20),
            child,
          ]),
        ),
      ),
    );
  }
}
