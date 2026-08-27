import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/env.dart';
import '../state/auth_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import '../widgets/common_widgets.dart';

/// Connexion par OTP SMS (§3.1) : numéro de téléphone puis code à 6 chiffres.
/// Pas de mot de passe — c'est le parcours retenu au cahier des charges.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onSuccess, required this.onBack});

  final VoidCallback onSuccess;
  final VoidCallback onBack;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _Step { phone, code }

class _AuthScreenState extends State<AuthScreen> {
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  _Step _step = _Step.phone;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String get _phone => _phoneCtrl.text.trim();

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _resendIn = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthController>();
    final sent = await auth.requestOtp(_phone);
    if (!mounted) return;

    if (!sent) {
      showAppSnack(context, auth.error ?? 'Envoi impossible');
      return;
    }
    setState(() => _step = _Step.code);
    _startCooldown();
    // En dev le backend renvoie le code : on le pré-remplit pour aller vite.
    final code = auth.devCode;
    if (code != null && Env.showDevOtpHint) _codeCtrl.text = code;
  }

  Future<void> _verify() async {
    final auth = context.read<AuthController>();
    final ok = await auth.verifyOtp(
      phone: _phone,
      code: _codeCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      widget.onSuccess();
    } else {
      showAppSnack(context, auth.error ?? 'Code invalide');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: _step == _Step.phone ? _phoneStep(auth) : _codeStep(auth),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_step == _Step.code) {
                setState(() => _step = _Step.phone);
              } else {
                widget.onBack();
              }
            },
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
          const Spacer(),
          Text('LAMSSA',
              style: AppTextStyle.playfair(size: 22, color: AppColors.gold)),
          const Spacer(),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _phoneStep(AuthController auth) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text('أهلا بيك 👋', style: AppTextStyle.playfair(size: 32)),
          const SizedBox(height: 10),
          Text(
            'Entre ton numéro, on t’envoie un code par SMS.',
            style: AppTextStyle.dmSans(color: AppColors.sub, size: 14),
          ),
          const SizedBox(height: 32),
          Text('Numéro de téléphone',
              style: AppTextStyle.dmSans(size: 13, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            style: AppTextStyle.dmSans(size: 16),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              LengthLimitingTextInputFormatter(16),
            ],
            decoration: const InputDecoration(
              hintText: '98 123 456',
              prefixIcon: Icon(Icons.phone_rounded, color: AppColors.sub, size: 20),
            ),
            validator: (value) {
              final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
              if (digits.length < 8) return 'Numéro incomplet';
              return null;
            },
          ),
          const SizedBox(height: 20),
          Text('Prénom (à la première connexion)',
              style: AppTextStyle.dmSans(size: 13, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: AppTextStyle.dmSans(size: 16),
            decoration: const InputDecoration(
              hintText: 'Mehdi',
              prefixIcon:
                  Icon(Icons.person_outline_rounded, color: AppColors.sub, size: 20),
            ),
          ),
          const SizedBox(height: 32),
          auth.busy
              ? const AppLoader()
              : GoldButton(text: 'Recevoir le code', onPressed: _sendCode),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Un numéro tunisien à 8 chiffres suffit — on ajoute +216.',
              style: AppTextStyle.dmSans(color: AppColors.sub, size: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeStep(AuthController auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text('Code de vérification', style: AppTextStyle.playfair(size: 28)),
        const SizedBox(height: 10),
        Text('Envoyé au $_phone',
            style: AppTextStyle.dmSans(color: AppColors.sub, size: 14)),
        const SizedBox(height: 32),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          autofocus: true,
          style: AppTextStyle.playfair(size: 30).copyWith(letterSpacing: 12),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(counterText: '', hintText: '••••••'),
          onChanged: (value) {
            if (value.length == 6 && !auth.busy) _verify();
          },
        ),
        if (Env.showDevOtpHint) ...[
          const SizedBox(height: 8),
          Text(
            'Mode dev : le code 000000 fonctionne aussi.',
            style: AppTextStyle.dmSans(color: AppColors.sub, size: 12),
          ),
        ],
        const SizedBox(height: 28),
        auth.busy
            ? const AppLoader()
            : GoldButton(
                text: 'Se connecter',
                enabled: _codeCtrl.text.trim().length >= 4,
                onPressed: _verify,
              ),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: _resendIn > 0 || auth.busy ? null : _sendCode,
            child: Text(
              _resendIn > 0
                  ? 'Renvoyer le code dans ${_resendIn}s'
                  : 'Renvoyer le code',
              style: AppTextStyle.dmSans(
                color: _resendIn > 0 ? AppColors.sub : AppColors.gold,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
