import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';

/// Modifier son compte (§3.1).
///
/// Le numéro de téléphone n'est pas modifiable : c'est l'identifiant du compte
/// côté serveur, et il a été vérifié par OTP. Le changer reviendrait à changer
/// de compte — ce qui se fait en se reconnectant avec l'autre numéro.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late String _locale;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthController>().user;
    _name = TextEditingController(text: user?.name ?? '');
    _locale = user?.locale == 'fr' ? 'fr' : 'ar';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = context.read<AuthController>();
    final name = _name.text.trim();
    if (name.isEmpty) {
      showAppSnack(context, 'اكتب اسمك');
      return;
    }

    setState(() => _saving = true);
    final error = await auth.updateProfile(name: name, locale: _locale);
    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      showAppSnack(context, error);
      return;
    }
    showAppSnack(context, 'تسجّل ✅', success: true);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.text,
        title: Text('تعديل الحساب', style: AppTextStyle.playfair(size: 20)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _label('الاسم'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            style: AppTextStyle.dmSans(),
            decoration: _decoration('اسمك الكامل'),
          ),
          const SizedBox(height: 22),

          _label('رقم التليفون'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              const Icon(Icons.lock_rounded, size: 16, color: AppColors.sub),
              const SizedBox(width: 10),
              Expanded(
                child: Text(user?.phone ?? '',
                    style: AppTextStyle.dmSans(color: AppColors.sub)),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Text(
            'الرقم متثبّت بالكود وما يتبدّلش — هو هوية حسابك',
            style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
          ),
          const SizedBox(height: 22),

          _label('اللغة'),
          Row(children: [
            _localeChip('ar', 'العربية'),
            const SizedBox(width: 8),
            _localeChip('fr', 'Français'),
          ]),
          const SizedBox(height: 6),
          Text(
            'تبدّل اتجاه التطبيق ولغة الرسائل اللي توصلك',
            style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(54),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.black),
                    )
                  : Text('سجّل',
                      style: AppTextStyle.dmSans(
                          color: Colors.black, weight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _localeChip(String code, String label) {
    final active = _locale == code;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _locale = code),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: active ? AppColors.gold : AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? AppColors.gold : AppColors.border),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: AppTextStyle.dmSans(
                size: 13,
                color: active ? Colors.black : AppColors.sub,
                weight: active ? FontWeight.w700 : FontWeight.w400,
              )),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
      );

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyle.dmSans(size: 13, color: AppColors.sub),
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      );
}
