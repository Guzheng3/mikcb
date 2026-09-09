import 'package:flutter/material.dart';
import 'package:university_timetable/l10n/app_localizations.dart';

import '../models/couple_timetable_history.dart';
import '../ui/hyperos/hyperos.dart';

/// Shows only the signed-in user's cloud-owned timetable history.
Future<CoupleTimetableHistoryEntry?> showCoupleTimetableHistorySheet({
  required BuildContext context,
  required Future<List<CoupleTimetableHistoryEntry>> Function() onLoadEntries,
}) {
  return showHyperosSheet<CoupleTimetableHistoryEntry>(
    context: context,
    builder: (_) => CoupleTimetableHistorySheet(onLoadEntries: onLoadEntries),
  );
}

class CoupleTimetableHistorySheet extends StatefulWidget {
  const CoupleTimetableHistorySheet({super.key, required this.onLoadEntries});

  final Future<List<CoupleTimetableHistoryEntry>> Function() onLoadEntries;

  @override
  State<CoupleTimetableHistorySheet> createState() =>
      _CoupleTimetableHistorySheetState();
}

class _CoupleTimetableHistorySheetState
    extends State<CoupleTimetableHistorySheet> {
  List<CoupleTimetableHistoryEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final entries = await widget.onLoadEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
    });
  }

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
            l10n.coupleHistoryMineLabel,
            style: HyperosTypography.sheetTitle(context),
          ),
          const SizedBox(height: 14),
          Flexible(child: SingleChildScrollView(child: _buildEntryList())),
        ],
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
}
