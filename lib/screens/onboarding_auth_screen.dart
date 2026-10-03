import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/l10n/service_message_localizer.dart';

import '../services/app_mode_service.dart';
import '../services/withu_couple_auth_service.dart';
import '../services/withu_couple_config.dart';
import '../ui/hyperos/hyperos.dart';
import '../utils/app_toast.dart';
import 'onboarding_register_screen.dart';
import 'partner_binding_screen.dart';

/// 首启登录页：新用户完成引导后进入的第一站。
///
/// 三个出口：
/// - 登录成功 → 未绑定时接「绑定另一半」引导页（可跳过），之后进主界面；
/// - 注册成功 → 自动登录并同样接绑定引导；
/// - 离线模式 → 数据不上云，直接进主界面。
///
/// 页面处于首启流程中，禁用系统返回（[PopScope] 且不提供返回按钮）：
/// 必须在「登录 / 注册 / 离线」中做出选择才能离开。
class OnboardingAuthScreen extends StatefulWidget {
  const OnboardingAuthScreen({super.key, required this.authService});

  /// 借用宿主（main.dart）的认证服务：登录即全局登录态，凭证只有一份。
  /// 借用方不得 dispose。
  final WithuCoupleAuthService authService;

  @override
  State<OnboardingAuthScreen> createState() => _OnboardingAuthScreenState();
}

class _OnboardingAuthScreenState extends State<OnboardingAuthScreen> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _accountController;
  late final TextEditingController _passwordController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: WithuCoupleConfig.defaultBaseUrl,
    );
    _accountController = TextEditingController();
    _passwordController = TextEditingController();
    _loadSavedBaseUrl();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 服务器地址默认值可被用户改过（自建服务）：仅当输入框仍是默认值时才
  /// 换成已保存的地址，避免覆盖用户正在输入的内容。
  Future<void> _loadSavedBaseUrl() async {
    final config = await widget.authService.loadConfig();
    if (!mounted ||
        _baseUrlController.text.trim() != WithuCoupleConfig.defaultBaseUrl) {
      return;
    }
    if (config.baseUrl.isNotEmpty) {
      _baseUrlController.text = config.baseUrl;
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final baseUrl = _baseUrlController.text.trim();
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    if (baseUrl.isEmpty || account.isEmpty || password.isEmpty) {
      showAppToast(
        context,
        message: l10n.withuCoupleMissingCredentials,
        kind: AppToastKind.error,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await widget.authService.connect(
        baseUrl: baseUrl,
        username: account,
        password: password,
      );
      if (!mounted) {
        return;
      }
      await _finishLogin(result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppToast(
        context,
        message: _errorMessage(l10n, error),
        kind: AppToastKind.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// 登录 / 注册成功后的共同收尾：未绑定 → 绑定引导页（可跳过），
  /// 已绑定直接回主界面。返回 true 告知宿主登录态已建立。
  Future<void> _finishLogin(WithuCoupleLoginResult result) async {
    if (result.partner == null) {
      await Navigator.of(context).push<void>(
        HyperosPageRoute(
          builder: (_) => PartnerBindingScreen(authService: widget.authService),
          fullscreenDialog: true,
        ),
      );
      if (!mounted) {
        return;
      }
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _openRegister() async {
    final result = await Navigator.of(context).push<WithuCoupleLoginResult>(
      HyperosPageRoute(builder: (_) => OnboardingRegisterScreen(authService: widget.authService)),
    );
    if (!mounted || result == null) {
      return;
    }
    await _finishLogin(result);
  }

  Future<void> _enterOfflineMode() async {
    await AppModeService.instance.setOfflineMode(true);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }

  String _errorMessage(AppLocalizations l10n, Object error) {
    if (error is WithuCoupleApiException &&
        error.serverMessage?.trim().isNotEmpty == true) {
      return error.serverMessage!;
    }
    return localizeServiceMessage(
      l10n,
      error is WithuCoupleApiException ? error.code : 'withu_request_failed',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false,
      child: HyperosSubpage(
        title: Text(l10n.onboardingAuthTitle),
        bottomBar: _buildBottomBar(l10n),
        child: _buildForm(l10n),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    final children = <Widget>[
      const SizedBox(height: 8),
      HyperosSectionDescription(text: l10n.onboardingAuthSubtitle),
      const SizedBox(height: 18),
      HyperosTextField(
        controller: _baseUrlController,
        label: l10n.withuCoupleServerLabel,
        hint: WithuCoupleConfig.defaultBaseUrl,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      HyperosTextField(
        controller: _accountController,
        label: l10n.onboardingAuthAccountLabel,
        hint: l10n.onboardingAuthAccountHint,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      HyperosTextField(
        controller: _passwordController,
        label: l10n.onboardingAuthPasswordLabel,
        hint: l10n.onboardingAuthPasswordHint,
        obscureText: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 20),
      HyperosButton(
        label: l10n.onboardingAuthLoginAction,
        expand: true,
        loading: _isSubmitting,
        onPressed: _isSubmitting ? null : _submit,
      ),
      const SizedBox(height: 10),
      HyperosButton(
        label: l10n.onboardingAuthRegisterEntry,
        variant: HyperosButtonVariant.secondary,
        expand: true,
        onPressed: _isSubmitting ? null : _openRegister,
      ),
      const HyperosSectionGap(),
      HyperosHintBanner(
        icon: const Icon(Icons.cloud_off_outlined, size: 18),
        title: Text(l10n.onboardingAuthOfflineHint),
      ),
    ];
    return HyperosListView(
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      pageStorageKey: const PageStorageKey<String>('onboarding-auth'),
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
                  label: l10n.onboardingAuthOfflineAction,
                  variant: HyperosButtonVariant.secondary,
                  expand: true,
                  onPressed: _isSubmitting ? null : _enterOfflineMode,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
