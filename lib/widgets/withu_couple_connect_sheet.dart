import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';

import '../services/withu_couple_config.dart';
import '../ui/hyperos/hyperos.dart';
import 'course_field_picker_sheet.dart';

class WithuCoupleConnectResult {
  const WithuCoupleConnectResult({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  final String baseUrl;
  final String username;
  final String password;
}

class WithuCoupleConnectSheet extends StatefulWidget {
  const WithuCoupleConnectSheet({super.key, required this.config});

  final WithuCoupleConfig config;

  @override
  State<WithuCoupleConnectSheet> createState() =>
      _WithuCoupleConnectSheetState();
}

class _WithuCoupleConnectSheetState extends State<WithuCoupleConnectSheet> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.config.baseUrl);
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _confirmConnect() {
    final baseUrl = _baseUrlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (baseUrl.isEmpty || username.isEmpty || password.isEmpty) {
      return;
    }

    Navigator.of(context).pop(
      WithuCoupleConnectResult(
        baseUrl: baseUrl,
        username: username,
        password: password,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PickerSheetScaffold(
      actions: HyperosButton(
        label: l10n.withuCoupleConfirmConnect,
        onPressed: _confirmConnect,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.withuCoupleLoginSheetTitle,
            style: HyperosTypography.sheetTitle(context),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.withuCoupleLoginSheetSubtitle,
            style: HyperosTypography.sectionDescription(context),
          ),
          const SizedBox(height: 16),
          HyperosTextField(
            controller: _baseUrlController,
            label: l10n.withuCoupleServerLabel,
            hint: l10n.withuCoupleServerHint(widget.config.baseUrl),
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
          ),
        ],
      ),
    );
  }
}
