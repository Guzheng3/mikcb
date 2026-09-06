import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';

import '../models/couple_timetable_history.dart';
import '../providers/withu_couple_session_provider.dart';
import '../ui/hyperos/hyperos.dart';

/// 长按情侣标题弹出：先选「我的 / 她的」，再列出该角色的往期课表
/// （同一学期只保留一条），点选条目即恢复。返回被选中的历史条目，
/// 恢复动作由调用方（课表页）执行。条目读取经 [onLoadEntries] 注入，
/// 本组件不直接依赖 TimetableProvider（守住 provider 的 lib 扇入）。
Future<CoupleTimetableHistoryEntry?> showCoupleTimetableHistorySheet({
  required BuildContext context,
  required WithuCoupleSessionProvider session,
  required Future<List<CoupleTimetableHistoryEntry>> Function(
    CoupleTimetableRole role,
  )
  onLoadEntries,
}) {
  return showHyperosSheet<CoupleTimetableHistoryEntry>(
    context: context,
    builder: (_) => CoupleTimetableHistorySheet(
      session: session,
      onLoadEntries: onLoadEntries,
    ),
  );
}

class CoupleTimetableHistorySheet extends StatefulWidget {
  const CoupleTimetableHistorySheet({
    super.key,
    required this.session,
    required this.onLoadEntries,
  });

  final WithuCoupleSessionProvider session;
  final Future<List<CoupleTimetableHistoryEntry>> Function(
    CoupleTimetableRole role,
  )
  onLoadEntries;

  @override
  State<CoupleTimetableHistorySheet> createState() =>
      _CoupleTimetableHistorySheetState();
}

class _CoupleTimetableHistorySheetState
    extends State<CoupleTimetableHistorySheet> {
  CoupleTimetableRole? _selectedRole;
  List<CoupleTimetableHistoryEntry>? _entries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return HyperosSheetFrame(
      maxHeight: MediaQuery.sizeOf(context).height * 0.68,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _selectedRole == null
                ? l10n.coupleHistorySheetTitle
                : (_selectedRole == CoupleTimetableRole.mine
                      ? l10n.coupleHistoryMineLabel
                      : l10n.coupleHistoryHersLabel),
            style: HyperosTypography.sheetTitle(context),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: _selectedRole == null
                  ? _buildRoleChoices()
                  : _buildEntryList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleChoices() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRoleRow(
          title: widget.session.userNickname,
          subtitle: l10n.coupleHistoryMineLabel,
          onTap: () => _openRole(CoupleTimetableRole.mine),
        ),
        const SizedBox(height: 10),
        _buildRoleRow(
          title: widget.session.partnerNickname,
          subtitle: l10n.coupleHistoryHersLabel,
          onTap: () => _openRole(CoupleTimetableRole.hers),
        ),
      ],
    );
  }

  Widget _buildRoleRow({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HyperosTokens.controlRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: HyperosTypography.listTitle(context)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: HyperosTypography.listDetail(context),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryList() {
    final l10n = AppLocalizations.of(context)!;
    final entries = _entries;
    if (entries == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            l10n.noHistoryRecords,
            style: HyperosTypography.listDetail(context),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries) ...[
          _buildEntryRow(entry),
          if (entry != entries.last) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildEntryRow(CoupleTimetableHistoryEntry entry) {
    final l10n = AppLocalizations.of(context)!;
    final anchor = entry.semesterAnchor;
    final semesterLabel = anchor == null
        ? entry.savedAt.toIso8601String().substring(0, 10)
        : '${anchor.year}-${anchor.month.toString().padLeft(2, '0')}-${anchor.day.toString().padLeft(2, '0')}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(entry),
        borderRadius: BorderRadius.circular(HyperosTokens.controlRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HyperosTypography.listTitle(context),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.coupleHistoryEntryMeta(
                        semesterLabel,
                        entry.courseCount,
                      ),
                      style: HyperosTypography.listDetail(context),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.restore_rounded,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRole(CoupleTimetableRole role) async {
    final entries = await widget.onLoadEntries(role);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedRole = role;
      _entries = entries;
    });
  }
}
