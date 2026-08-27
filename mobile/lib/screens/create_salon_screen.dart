import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../data/repositories/salon_admin_repository.dart';
import '../state/auth_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import '../widgets/common_widgets.dart';

/// Onboarding salon (§3.1) — le gérant crée son salon depuis le téléphone.
///
/// `POST /salons` promeut l'appelant au rôle OWNER : il faut recharger le
/// contexte de session juste après, sinon l'app reste en espace client.
class CreateSalonScreen extends StatefulWidget {
  const CreateSalonScreen({super.key});

  @override
  State<CreateSalonScreen> createState() => _CreateSalonScreenState();
}

class _CreateSalonScreenState extends State<CreateSalonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  SalonType _type = SalonType.barbershop;
  double _splitPct = 50;
  int _cancelWindowH = 2;

  double? _lat;
  double? _lng;
  bool _locating = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  /// La position est obligatoire : sans elle le salon n'apparaît dans aucune
  /// recherche « près de moi », qui est le premier canal d'acquisition (§3.2).
  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          showAppSnack(context, 'Autorise la localisation pour situer le salon');
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
      });
    } catch (_) {
      if (mounted) showAppSnack(context, 'Position indisponible');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lat == null || _lng == null) {
      showAppSnack(context, 'Enregistre la position du salon avant de continuer');
      return;
    }

    setState(() => _saving = true);
    try {
      final salon = await context.read<SalonAdminRepository>().createSalon(
            name: _nameCtrl.text.trim(),
            type: _type,
            lat: _lat!,
            lng: _lng!,
            address: _addressCtrl.text.trim(),
            city: _cityCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            defaultSplitPct: _splitPct,
            cancellationWindowH: _cancelWindowH,
          );
      if (!mounted) return;

      // Le rôle a changé côté serveur — sans ce rechargement l'app resterait
      // sur l'espace client et le nouveau salon serait invisible.
      await context.read<AuthController>().refreshContext();
      if (!mounted) return;

      Navigator.of(context).pop(salon);
      showAppSnack(context, 'صالونك تعمل ✅ زيد الخدمات والفريق', success: true);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  _label('اسم الصالون'),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: AppTextStyle.dmSans(size: 15),
                    decoration: const InputDecoration(hintText: 'King Barber'),
                    validator: (v) => (v ?? '').trim().length < 2
                        ? 'حطّ اسم (حرفين على الأقل)'
                        : null,
                  ),
                  const SizedBox(height: 20),

                  _label('نوع الصالون'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SalonType.values.map((type) {
                      final selected = _type == type;
                      return GestureDetector(
                        onTap: () => setState(() => _type = type),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.gold.withValues(alpha: 0.15)
                                : AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: selected ? AppColors.gold : AppColors.border),
                          ),
                          child: Text(type.label, style: AppTextStyle.dmSans(
                            size: 12,
                            weight: selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected ? AppColors.gold : AppColors.text,
                          )),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  _label('المدينة'),
                  TextFormField(
                    controller: _cityCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: AppTextStyle.dmSans(size: 15),
                    decoration: const InputDecoration(hintText: 'Tunis'),
                  ),
                  const SizedBox(height: 16),

                  _label('العنوان'),
                  TextFormField(
                    controller: _addressCtrl,
                    style: AppTextStyle.dmSans(size: 15),
                    decoration:
                        const InputDecoration(hintText: 'Av. Habib Bourguiba'),
                  ),
                  const SizedBox(height: 16),

                  _label('الهاتف'),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                      LengthLimitingTextInputFormatter(16),
                    ],
                    style: AppTextStyle.dmSans(size: 15),
                    decoration: const InputDecoration(hintText: '71 000 000'),
                  ),
                  const SizedBox(height: 20),

                  _buildLocation(),
                  const SizedBox(height: 24),

                  _buildSplit(),
                  const SizedBox(height: 20),

                  _buildCancelWindow(),
                  const SizedBox(height: 32),

                  _saving
                      ? const AppLoader()
                      : GoldButton(text: 'أنشئ الصالون', onPressed: _submit),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'تنجم تبدّل كل شيء من بعد.',
                      style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 20, 12),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 40, height: 40,
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
        Text('صالوني الجديد 🏪', style: AppTextStyle.playfair(size: 22)),
      ]),
    );
  }

  Widget _buildLocation() {
    final located = _lat != null && _lng != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: located
            ? AppColors.green.withValues(alpha: 0.07)
            : AppColors.gold.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (located ? AppColors.green : AppColors.gold)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(children: [
        Text(located ? '📍' : '🗺️', style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(located ? 'الموقع تسجّل' : 'موقع الصالون',
                style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              located
                  ? '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'
                  : 'ضروري باش الحرفاء يلقاوك في الخريطة',
              style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
            ),
          ]),
        ),
        GestureDetector(
          onTap: _locating ? null : _locate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: located ? AppColors.card : AppColors.gold,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                  color: located ? AppColors.border : AppColors.gold),
            ),
            child: _locating
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.gold),
                  )
                : Text(located ? 'بدّل' : 'سجّل موقعي',
                    style: AppTextStyle.dmSans(
                      size: 12,
                      weight: FontWeight.w700,
                      color: located ? AppColors.gold : Colors.black,
                    )),
          ),
        ),
      ]),
    );
  }

  Widget _buildSplit() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('تقسيم الكاسة الافتراضي'),
      Text(
        'الصالون ${(100 - _splitPct).toStringAsFixed(0)}% · '
        'الحجام ${_splitPct.toStringAsFixed(0)}%',
        style: AppTextStyle.dmSans(size: 13, weight: FontWeight.w600),
      ),
      Slider(
        value: _splitPct,
        min: 0,
        max: 100,
        divisions: 20,
        activeColor: AppColors.gold,
        inactiveColor: AppColors.border,
        label: '${_splitPct.toStringAsFixed(0)}%',
        onChanged: (v) => setState(() => _splitPct = v),
      ),
      Text(
        'تنجم تحدّد نسبة مختلفة لكل حجام من بعد.',
        style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
      ),
    ]);
  }

  Widget _buildCancelWindow() {
    const options = [0, 1, 2, 4, 12, 24];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('الإلغاء مسموح قبل'),
      Wrap(
        spacing: 8,
        children: options.map((hours) {
          final selected = _cancelWindowH == hours;
          return GestureDetector(
            onTap: () => setState(() => _cancelWindowH = hours),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.gold.withValues(alpha: 0.15)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected ? AppColors.gold : AppColors.border),
              ),
              child: Text(hours == 0 ? 'في أي وقت' : '$hours سا',
                  style: AppTextStyle.dmSans(
                    size: 12,
                    weight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? AppColors.gold : AppColors.text,
                  )),
            ),
          );
        }).toList(),
      ),
    ]);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: AppTextStyle.dmSans(
                size: 12, weight: FontWeight.w600, color: AppColors.sub)),
      );
}
