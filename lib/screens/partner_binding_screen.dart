import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:university_timetable/l10n/service_message_localizer.dart';

import '../services/withu_couple_auth_service.dart';
import '../ui/hyperos/hyperos.dart';
import '../utils/app_toast.dart';

/// 「绑定另一半」引导页：注册 / 登录后未绑定时进入，也可从情侣中心进入。
///
/// 提供三种绑定方式（数据都来自服务端，互相等效）：
/// - 手机号搜索 → 向对方发送绑定申请；
/// - 我的邀请码 → 发给 TA，TA 凭码绑定我；
/// - 对方邀请码 → 我凭码绑定 TA。
///
/// 页面同时轮转展示「收到的申请」（同意 / 拒绝）与「已发出的申请」。
/// 「暂时跳过」= 单人模式，之后可在情侣中心回来完成绑定。
class PartnerBindingScreen extends StatefulWidget {
  const PartnerBindingScreen({super.key, required this.authService});

  /// 借用调用方的认证服务（首启流程借用 main.dart 的实例），借用方不得 dispose。
  final WithuCoupleAuthService authService;

  @override
  State<PartnerBindingScreen> createState() => _PartnerBindingScreenState();
}

class _PartnerBindingScreenState extends State<PartnerBindingScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  WithuCoupleBindCode? _myCode;
  WithuCoupleBindRequestLists? _requests;
  WithuCoupleUser? _searchResult;
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isSending = false;
  bool _isBindingByCode = false;
  int? _respondingRequestId;
  bool _hasLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final results = await Future.wait<Object?>([
        widget.authService.fetchMyBindCode(),
        widget.authService.pendingBindRequests(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _myCode = results[0] as WithuCoupleBindCode?;
        _requests = results[1] as WithuCoupleBindRequestLists?;
        _hasLoadFailed = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _hasLoadFailed = true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _reloadRequests() async {
    try {
      final requests = await widget.authService.pendingBindRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _requests = requests;
        _hasLoadFailed = false;
      });
    } catch (_) {
      // 申请列表刷新失败不打断主流程：下次进页 / 下一次操作再补。
    }
  }

  Future<void> _search() async {
    if (_isSearching) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isSearching = true;
      _searchResult = null;
    });
    try {
      final user = await widget.authService.searchByPhone(
        _searchController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() => _searchResult = user);
      if (user == null) {
        showAppToast(
          context,
          message: l10n.partnerBindingSearchNotFound,
        );
      }
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
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _sendRequestTo(WithuCoupleUser user) async {
    if (_isSending) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isSending = true);
    try {
      final response = await widget.authService.sendBindRequest(user.id);
      if (!mounted) {
        return;
      }
      if (response.bound) {
        // 对方先前也申请过我：服务端已自动互绑，直接按绑定成功收尾。
        await _finishBound(user.displayName);
        return;
      }
      showAppToast(
        context,
        message: response.message.trim().isNotEmpty
            ? response.message
            : l10n.partnerBindingRequestSent,
        kind: AppToastKind.success,
      );
      _searchController.clear();
      setState(() => _searchResult = null);
      unawaited(_reloadRequests());
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
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _copyMyCode() async {
    final code = _myCode?.code;
    if (code == null || code.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) {
      return;
    }
    showAppToast(
      context,
      message: AppLocalizations.of(context)!.partnerBindingCopied,
      kind: AppToastKind.success,
    );
  }

  Future<void> _bindByCode() async {
    if (_isBindingByCode) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final code = _codeController.text.trim();
    if (!RegExp(r'^[A-Za-z0-9]{8}$').hasMatch(code)) {
      showAppToast(
        context,
        message: l10n.partnerBindingInvalidCode,
        kind: AppToastKind.error,
      );
      return;
    }
    setState(() => _isBindingByCode = true);
    try {
      final partner = await widget.authService.bindByCode(code);
      if (!mounted) {
        return;
      }
      if (partner == null) {
        throw const WithuCoupleApiException('withu_invalid_response');
      }
      _codeController.clear();
      await _finishBound(partner.displayName);
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
        setState(() => _isBindingByCode = false);
      }
    }
  }

  Future<void> _respond(
    WithuCoupleIncomingBindRequest request, {
    required bool accept,
  }) async {
    if (_respondingRequestId != null) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    setState(() => _respondingRequestId = request.id);
    try {
      final partner = await widget.authService.respondBindRequest(
        request.id,
        accept: accept,
      );
      if (!mounted) {
        return;
      }
      if (accept && partner != null) {
        await _finishBound(partner.displayName);
        return;
      }
      unawaited(_reloadRequests());
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
        setState(() => _respondingRequestId = null);
      }
    }
  }

  /// 绑定成功收尾：toast + 携带对方资料返回。
  Future<void> _finishBound(String partnerNickname) async {
    final l10n = AppLocalizations.of(context)!;
    showAppToast(
      context,
      message: l10n.partnerBindingBoundToast(partnerNickname),
      kind: AppToastKind.success,
    );
    Navigator.of(context).pop();
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

    return HyperosSubpage(
      onBack: () => Navigator.pop(context),
      title: Text(l10n.partnerBindingTitle),
      suffixes: [
        FHeaderAction(
          icon: const Icon(Icons.refresh),
          semanticsLabel: l10n.refreshStatusTooltip,
          onPress: _reload,
        ),
      ],
      bottomBar: _buildBottomBar(l10n),
      child: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading && _myCode == null && _requests == null) {
      return const Center(child: HyperosCircularProgress());
    }

    final children = <Widget>[
      const SizedBox(height: 8),
      HyperosHintBanner(
        icon: const Icon(Icons.favorite_outline, size: 18),
        title: Text(l10n.partnerBindingSubtitle),
      ),
      if (_hasLoadFailed && _myCode == null && _requests == null) ...[
        const HyperosSectionGap(),
        HyperosHintBanner(
          icon: const Icon(Icons.error_outline, size: 18),
          title: Text(l10n.partnerBindingLoadFailed),
        ),
      ],
      const HyperosSectionGap(),
      _buildSearchSection(l10n),
      if (_myCode != null) ...[
        const HyperosSectionGap(),
        _buildMyCodeSection(l10n),
      ],
      const HyperosSectionGap(),
      _buildEnterCodeSection(l10n),
      ..._buildRequestSections(l10n),
    ];

    return HyperosListView(
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      pageStorageKey: const PageStorageKey<String>('partner-binding'),
    );
  }

  /// 手机号搜索：找到后展示对方昵称 + 发申请按钮。
  Widget _buildSearchSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HyperosTextField(
          controller: _searchController,
          label: l10n.partnerBindingSearchLabel,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 10),
        HyperosButton(
          label: l10n.partnerBindingSearchAction,
          variant: HyperosButtonVariant.secondary,
          expand: true,
          loading: _isSearching,
          onPressed: _isSearching ? null : _search,
        ),
        if (_searchResult != null) ...[
          const SizedBox(height: 12),
          HyperosControlCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _searchResult!.displayName,
                  style: HyperosTypography.listTitle(context),
                ),
                const SizedBox(height: 12),
                HyperosButton(
                  label: l10n.partnerBindingSendRequestTo(
                    _searchResult!.displayName,
                  ),
                  expand: true,
                  loading: _isSending,
                  onPressed: _isSending ? null : () => _sendRequestTo(_searchResult!),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMyCodeSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HyperosSectionLabel(text: l10n.partnerBindingMyCodeLabel),
        HyperosControlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _myCode!.code,
                style: HyperosTypography.sheetTitle(context),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.partnerBindingMyCodeHint,
                style: HyperosTypography.listDetail(context),
              ),
              const SizedBox(height: 12),
              HyperosButton(
                label: l10n.partnerBindingCopyAction,
                variant: HyperosButtonVariant.secondary,
                expand: true,
                onPressed: _copyMyCode,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnterCodeSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HyperosSectionLabel(text: l10n.partnerBindingEnterCodeLabel),
        HyperosTextField(
          controller: _codeController,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _bindByCode(),
        ),
        const SizedBox(height: 10),
        HyperosButton(
          label: l10n.partnerBindingBindByCodeAction,
          expand: true,
          loading: _isBindingByCode,
          onPressed: _isBindingByCode ? null : _bindByCode,
        ),
      ],
    );
  }

  List<Widget> _buildRequestSections(AppLocalizations l10n) {
    final requests = _requests;
    if (requests == null) {
      return const [];
    }
    final widgets = <Widget>[];
    if (requests.incoming.isNotEmpty) {
      widgets
        ..add(const HyperosSectionGap())
        ..add(HyperosSectionLabel(text: l10n.partnerBindingIncomingSection));
      for (final request in requests.incoming) {
        widgets.add(_buildIncomingCard(l10n, request));
      }
    }
    if (requests.outgoing.isNotEmpty) {
      widgets
        ..add(const HyperosSectionGap())
        ..add(HyperosSectionLabel(text: l10n.partnerBindingOutgoingSection));
      for (final request in requests.outgoing) {
        widgets.add(
          HyperosControlCard(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    request.toNickname,
                    style: HyperosTypography.listTitle(context),
                  ),
                ),
                Text(
                  l10n.partnerBindingWaitingRespond,
                  style: HyperosTypography.listDetail(context),
                ),
              ],
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _buildIncomingCard(
    AppLocalizations l10n,
    WithuCoupleIncomingBindRequest request,
  ) {
    final isResponding = _respondingRequestId == request.id;
    return HyperosControlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.fromUser?.displayName ?? '—',
            style: HyperosTypography.listTitle(context),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: HyperosButton(
                  label: l10n.partnerBindingAcceptAction,
                  expand: true,
                  loading: isResponding,
                  onPressed: isResponding
                      ? null
                      : () => _respond(request, accept: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HyperosButton(
                  label: l10n.partnerBindingRejectAction,
                  variant: HyperosButtonVariant.secondary,
                  expand: true,
                  onPressed: isResponding
                      ? null
                      : () => _respond(request, accept: false),
                ),
              ),
            ],
          ),
        ],
      ),
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
                  label: l10n.partnerBindingSkip,
                  variant: HyperosButtonVariant.secondary,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
