import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';

import '../services/withu_couple_auth_service.dart';
import '../ui/hyperos/hyperos.dart';
import '../utils/app_toast.dart';

/// 首启注册页：手机号 + 昵称 + 性别 + 密码（不用短信验证码）。
///
/// 注册成功即自动登录（服务端直接下发会话），携带登录结果返回给
/// [OnboardingAuthScreen]，由它接「绑定另一半」引导。
class OnboardingRegisterScreen extends StatefulWidget {
  const OnboardingRegisterScreen({super.key, required this.authService});

  /// 借用宿主的认证服务，借用方不得 dispose。
  final WithuCoupleAuthService authService;

  @override
  State<OnboardingRegisterScreen> createState() =>
      _OnboardingRegisterScreenState();
}

class _OnboardingRegisterScreenState extends State<OnboardingRegisterScreen> {
  late final TextEditingController _phoneController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmController;

  /// 服务端 role：user1 = 男生，user2 = 女生。
  String _gender = 'user1';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _nicknameController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmController = TextEditingController();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nicknameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final phone = _phoneController.text.trim();
    final nickname = _nicknameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      showAppToast(
        context,
        message: l10n.onboardingRegisterInvalidPhone,
        kind: AppToastKind.error,
      );
      return;
    }
    if (nickname.isEmpty || password.length < 6) {
      showAppToast(
        context,
        message: l10n.onboardingRegisterMissingFields,
        kind: AppToastKind.error,
      );
      return;
    }
    if (password != confirm) {
      showAppToast(
        context,
        message: l10n.onboardingRegisterPasswordMismatch,
        kind: AppToastKind.error,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await widget.authService.register(
        baseUrl: (await widget.authService.loadConfig()).baseUrl,
        phone: phone,
        nickname: nickname,
        password: password,
        role: _gender,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      // 服务端 400 的 message（如「该手机号已注册」）优先展示。
      final serverMessage =
          error is WithuCoupleApiException ? error.serverMessage : null;
      showAppToast(
        context,
        message: serverMessage?.trim().isNotEmpty == true
            ? serverMessage!
            : l10n.withuCoupleRequestFailed,
        kind: AppToastKind.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return HyperosSubpage(
      onBack: () => Navigator.pop(context),
      title: Text(l10n.onboardingRegisterTitle),
      bottomBar: _buildBottomBar(l10n),
      child: _buildForm(l10n),
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    final children = <Widget>[
      const SizedBox(height: 8),
      HyperosSectionDescription(text: l10n.onboardingRegisterSubtitle),
      const SizedBox(height: 18),
      HyperosTextField(
        controller: _phoneController,
        label: l10n.onboardingRegisterPhoneLabel,
        hint: l10n.onboardingRegisterPhoneHint,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      HyperosTextField(
        controller: _nicknameController,
        label: l10n.onboardingRegisterNicknameLabel,
        hint: l10n.onboardingRegisterNicknameHint,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 16),
      Text(
        l10n.onboardingRegisterGenderLabel,
        style: HyperosTypography.listTitle(context),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: HyperosButton(
              label: l10n.onboardingRegisterGenderMale,
              variant: _gender == 'user1'
                  ? HyperosButtonVariant.primary
                  : HyperosButtonVariant.secondary,
              expand: true,
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() => _gender = 'user1'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: HyperosButton(
              label: l10n.onboardingRegisterGenderFemale,
              variant: _gender == 'user2'
                  ? HyperosButtonVariant.primary
                  : HyperosButtonVariant.secondary,
              expand: true,
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() => _gender = 'user2'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      HyperosTextField(
        controller: _passwordController,
        label: l10n.onboardingRegisterPasswordLabel,
        obscureText: true,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      HyperosTextField(
        controller: _confirmController,
        label: l10n.onboardingRegisterConfirmLabel,
        obscureText: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
    ];
    return HyperosListView(
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      pageStorageKey: const PageStorageKey<String>('onboarding-register'),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    return Container(
      color: HyperosColors.scaffoldBackground(context),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: HyperosButton(
                  label: l10n.onboardingRegisterAction,
                  expand: true,
                  loading: _isSubmitting,
                  onPressed: _isSubmitting ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
