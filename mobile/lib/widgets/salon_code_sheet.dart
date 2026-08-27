import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../data/repositories/salon_repository.dart';
import '../theme/app_theme.dart';

/// Ouvrir un salon depuis le code de sa vitrine (§3.2, §8.3).
///
/// Complète le QR : un client qui n'arrive pas à scanner — appareil photo qui
/// ne reconnaît pas les QR, code abîmé, capture d'écran floue — doit pouvoir
/// taper le code qu'il lit. C'est pour ça qu'il est court et sans 0/O ni 1/I/L.
class SalonCodeSheet extends StatefulWidget {
  const SalonCodeSheet({super.key, required this.onFound});

  final void Function(Salon salon) onFound;

  static Future<void> show(BuildContext context, void Function(Salon) onFound) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SalonCodeSheet(onFound: onFound),
    );
  }

  @override
  State<SalonCodeSheet> createState() => _SalonCodeSheetState();
}

class _SalonCodeSheetState extends State<SalonCodeSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;

    setState(() { _busy = true; _error = null; });
    try {
      final detail = await context.read<SalonRepository>().detailByCode(code);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onFound(detail.salon);
    } on ApiException catch (e) {
      if (!mounted) return;
      // 404 = code inexistant : c'est le cas courant, il mérite un message
      // clair plutôt que l'erreur brute du serveur.
      setState(() {
        _error = e.statusCode == 404 ? 'كود ماهوش موجود' : e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text('كود الصالون', style: AppTextStyle.playfair(size: 20)),
          const SizedBox(height: 6),
          Text(
            'اكتب الكود اللي في الفيترينة',
            style: AppTextStyle.dmSans(size: 13, color: AppColors.sub),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: AppTextStyle.playfair(size: 22).copyWith(letterSpacing: 3),
            // Le serveur normalise casse, espaces et tirets : on laisse
            // l'utilisateur écrire comme il lit.
            inputFormatters: [LengthLimitingTextInputFormatter(16)],
            decoration: InputDecoration(
              hintText: 'BARBIE 7K2M',
              hintStyle: AppTextStyle.playfair(size: 22, color: AppColors.sub)
                  .copyWith(letterSpacing: 3),
              filled: true,
              fillColor: AppColors.card2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(52),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.black),
                    )
                  : Text('افتح الصالون',
                      style: AppTextStyle.dmSans(
                          color: Colors.black, weight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
