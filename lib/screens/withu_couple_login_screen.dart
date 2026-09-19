import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/l10n/service_message_localizer.dart';

import '../services/withu_couple_auth_service.dart';
import '../services/withu_couple_config.dart';
import '../services/withu_couple_timetable_service.dart';
import '../ui/hyperos/hyperos.dart';
import '../utils/app_toast.dart';

Future<bool?> showWithuCoupleLoginSheet({
  required BuildContext context,
  required WithuCoupleAuthService authService,
  WithuCoupleConfig? initialConfig,
  required Future<WithuCouplePullResult> Function(
    WithuCoupleTimetableService service,
  )
  onPullPartner,
  bool useRootNavigator = false,
}) {
  return showHyperosSheet<bool>(
    context: context,
    useRootNavigator: useRootNavigator,
    builder: (_) => WithuCoupleLoginSheet(
      authService: authService,
      initialConfig: initialConfig,
      onPullPartner: onPullPartner,
    ),
  );
}

class WithuCoupleLoginSheet extends StatefulWidget {
  const WithuCoupleLoginSheet({
    super.key,
    required this.authService,
    this.initialConfig,
    required this.onPullPartner,
  });

  /// 借用调用方（首页 provider）的认证服务：登录要立刻反映到全局登录态，
  /// 且凭证只有一份。借用方不得 dispose。
  final WithuCoupleAuthService authService;

  final WithuCoupleConfig? initialConfig;
  final Future<WithuCouplePullResult> Function(
    WithuCoupleTimetableService service,
  )
  onPullPartner;

  @override
  State<WithuCoupleLoginSheet> createState() => _WithuCoupleLoginSheetState();
}

class _WithuCoupleLoginSheetState extends State<WithuCoupleLoginSheet> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final WithuCoupleTimetableService _timetableService;
  bool _isSubmitting = false;

  WithuCoupleAuthService get _authService => widget.authService;

  @override
  void initState() {
    super.initState();
    _timetableService = WithuCoupleTimetableService(
      authService: widget.authService,
    );
    final config = widget.initialConfig ?? const WithuCoupleConfig();
    _baseUrlController = TextEditingController(text: config.baseUrl);
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    if (widget.initialConfig == null) {
      _loadSavedConfig();
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    // _authService 由首页 provider 持有，这里不 dispose。
    super.dispose();
  }

  Future<void> _loadSavedConfig() async {
    final config = await _authService.loadConfig();
    if (!mounted ||
        _baseUrlController.text.trim() != WithuCoupleConfig.defaultBaseUrl) {
      return;
    }
    _baseUrlController.text = config.baseUrl.isEmpty
        ? WithuCoupleConfig.defaultBaseUrl
        : config.baseUrl;
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final baseUrl = _baseUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (baseUrl.isEmpty || username.isEmpty || password.isEmpty) {
      showAppToast(
        context,
        message: l10n.withuCoupleMissingCredentials,
        kind: AppToastKind.error,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _authService.connect(
        baseUrl: baseUrl,
        username: username,
        password: password,
      );
      // 密码只用于这一次登录请求，凭证已经落盘，不必再留在输入框里。
      _passwordController.clear();
      final result = await widget.onPullPartner(_timetableService);
      if (!mounted) {
        return;
      }

      final pullMessage = switch (result.status) {
        WithuCouplePullStatus.imported => l10n.withuCouplePullImported,
        WithuCouplePullStatus.updated => l10n.withuCouplePullUpdated,
        WithuCouplePullStatus.unchanged => l10n.withuCouplePullUnchanged,
        WithuCouplePullStatus.failed => localizeServiceMessage(
          l10n,
          result.errorCode ?? 'withu_request_failed',
        ),
      };
      showAppToast(
        context,
        message: pullMessage,
        kind: result.status == WithuCouplePullStatus.failed
            ? AppToastKind.error
            : AppToastKind.success,
      );
      // 首次同步失败（对方课表格式不支持、断网…）不影响登录本身：凭证已经落盘，
      // 这里必须关掉弹窗让调用方刷新登录态。停在登录表单会让用户以为没登录成功，
      // 再点一次也只是重复登录。同步失败的原因已由上面的 toast 说明。
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppToast(
        context,
        message: localizeServiceMessage(l10n, _errorCode(error)),
        kind: AppToastKind.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _errorCode(Object error) {
    if (error is WithuCoupleApiException) {
      return error.code;
    }
    return 'withu_request_failed';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return HyperosSheetFrame(
      maxHeight: MediaQuery.sizeOf(context).height * 0.68,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.withuCoupleLoginMenuTitle,
              style: HyperosTypography.sheetTitle(context),
            ),
            const SizedBox(height: 6),
            HyperosSectionDescription(text: l10n.withuCoupleLoginPageSubtitle),
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
              controller: _usernameController,
              label: l10n.withuCoupleUsernameLabel,
              hint: l10n.withuCoupleUsernameHint,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            HyperosTextField(
              controller: _passwordController,
              label: l10n.withuCouplePasswordLabel,
              hint: l10n.withuCouplePasswordHint,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 18),
            HyperosButton(
              label: _isSubmitting
                  ? '${l10n.withuCoupleLoginAction}...'
                  : l10n.withuCoupleLoginAction,
              loading: _isSubmitting,
              onPressed: _isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
