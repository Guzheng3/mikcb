import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/l10n/service_message_localizer.dart';

import '../services/withu_couple_auth_service.dart';
import '../services/withu_couple_config.dart';
import '../services/withu_couple_timetable_service.dart';
import '../ui/hyperos/hyperos.dart';
import '../utils/app_toast.dart';

class WithuCoupleLoginScreen extends StatefulWidget {
  const WithuCoupleLoginScreen({
    super.key,
    this.initialConfig,
    required this.onPullPartner,
  });

  final WithuCoupleConfig? initialConfig;
  final Future<WithuCouplePullResult> Function(
    WithuCoupleTimetableService service,
  )
  onPullPartner;

  @override
  State<WithuCoupleLoginScreen> createState() => _WithuCoupleLoginScreenState();
}

class _WithuCoupleLoginScreenState extends State<WithuCoupleLoginScreen> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final WithuCoupleAuthService _authService;
  late final WithuCoupleTimetableService _timetableService;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _authService = WithuCoupleAuthService();
    _timetableService = WithuCoupleTimetableService(authService: _authService);
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
    _authService.dispose();
    super.dispose();
  }

  Future<void> _loadSavedConfig() async {
    final config = await _authService.loadConfig();
    if (!mounted || _baseUrlController.text.trim().isNotEmpty) {
      return;
    }
    _baseUrlController.text = config.baseUrl;
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

    return HyperosSubpage(
      onBack: () => Navigator.pop(context),
      title: Text(l10n.withuCoupleLoginPageTitle),
      resizeToAvoidBottomInset: true,
      child: HyperosListView(
        children: [
          HyperosControlCard(
            title: l10n.withuCoupleLoginPageSubtitle,
            child: HyperosControlCardInset(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HyperosTextField(
                    controller: _baseUrlController,
                    label: l10n.withuCoupleServerLabel,
                    hint: 'https://withu.example.com',
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  HyperosTextField(
                    controller: _usernameController,
                    label: l10n.cloudSyncUsernameLabel,
                    hint: l10n.cloudSyncUsernameHint,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  HyperosTextField(
                    controller: _passwordController,
                    label: l10n.cloudSyncPasswordLabel,
                    hint: l10n.cloudSyncPasswordHint,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
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
          ),
        ],
      ),
    );
  }
}
