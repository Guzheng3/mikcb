import 'dart:convert';
import 'package:university_timetable/ui/hyperos/hyperos.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:university_timetable/l10n/app_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/warehouse_repository_models.dart';
import '../providers/timetable_provider.dart';
import 'changelog_screen.dart';
import 'open_source_licenses_screen.dart';
import '../services/bundled_assets.dart';
import '../widgets/about_info_sheet.dart';
import '../widgets/third_party_disclaimer_card.dart';
import '../widgets/bundled_asset_image.dart';
import '../utils/app_toast.dart';
import '../services/warehouse_repository_service.dart';
import 'feedback_screen.dart';
import 'log_viewer_entry.dart';

const String kAppRepositoryUrl = 'https://github.com/Mutx163/mikcb';

final RegExp _releaseNotesVersionHeadingPattern = RegExp(
  r'^#\s+v[\d.\-a-zA-Z]+$',
  caseSensitive: false,
);
final RegExp _releaseNotesHeadingPattern = RegExp(r'^#{1,6}\s+');
final RegExp _releaseNotesTopLevelBulletPattern = RegExp(
  r'^(?:[-+*]|\d+[.)])\s+',
);

/// Splits a release announcement into lazily-renderable Markdown blocks.
///
/// [MarkdownBody] parses its complete input and creates the complete widget
/// tree in one build. That is appropriate for a short paragraph, but a long
/// release announcement can contain hundreds of list rows. Keeping headings
/// and top-level list items as separate blocks lets [ListView.builder] mount
/// only the blocks near the viewport.
@visibleForTesting
List<String> splitReleaseNotesIntoBlocks(String data) {
  final normalizedData = data.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalizedData.trim().isEmpty) {
    return const [];
  }

  final lines = normalizedData.split('\n');
  var firstContentLine = 0;
  while (firstContentLine < lines.length &&
      lines[firstContentLine].trim().isEmpty) {
    firstContentLine++;
  }
  if (firstContentLine < lines.length &&
      _releaseNotesVersionHeadingPattern.hasMatch(
        lines[firstContentLine].trim(),
      )) {
    firstContentLine++;
  }

  final blocks = <String>[];
  final currentLines = <String>[];
  var insideCodeFence = false;

  void flushCurrentBlock() {
    final block = currentLines.join('\n').trim();
    if (block.isNotEmpty) {
      blocks.add(block);
    }
    currentLines.clear();
  }

  for (var index = firstContentLine; index < lines.length; index++) {
    final line = lines[index];
    final trimmedLine = line.trim();
    final isCodeFenceMarker =
        trimmedLine.startsWith('```') || trimmedLine.startsWith('~~~');
    final startsHeading =
        !insideCodeFence && _releaseNotesHeadingPattern.hasMatch(line);
    final startsTopLevelBullet =
        !insideCodeFence && _releaseNotesTopLevelBulletPattern.hasMatch(line);

    if (startsHeading || startsTopLevelBullet) {
      // A heading or a new top-level item starts an independently paintable
      // block. Nested / indented list items remain with their parent item.
      flushCurrentBlock();
      currentLines.add(line);
    } else if (trimmedLine.isEmpty && !insideCodeFence) {
      // Blank lines delimit paragraphs and list items. Do not retain them in
      // the block because MarkdownBody adds the relevant block spacing itself.
      flushCurrentBlock();
    } else {
      currentLines.add(line);
    }

    if (isCodeFenceMarker) {
      insideCodeFence = !insideCodeFence;
    }
  }
  flushCurrentBlock();
  return blocks;
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) {
      return;
    }
    setState(() {
      _packageInfo = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final versionText = _packageInfo == null
        ? l10n.loadingText
        : l10n.versionLabel(
            '${_packageInfo!.version} (${_packageInfo!.buildNumber})',
          );

    return HyperosSubpage(
      onBack: () => Navigator.pop(context),
      title: Text(l10n.aboutTitle),
      child: HyperosListView(
        children: [
          Material(
            color: HyperosColors.card(context),
            shape: HyperosTheme.cardShape(),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BundledAssetImage(
                        assetPath: BundledAssets.launcherIcon,
                        fit: BoxFit.cover,
                        cacheWidth: 168,
                        cacheHeight: 168,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.timetableAppName,
                    style: HyperosTypography.summaryTitle(context),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    versionText,
                    style: HyperosTypography.listDetail(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.aboutHeroSubtitle,
                    textAlign: TextAlign.center,
                    style: HyperosTypography.sectionDescription(context),
                  ),
                  const SizedBox(height: 16),
                  _buildHeroMetaStrip(
                    context,
                    platformValue: 'Android',
                    focusValue: 'HyperOS',
                    updateValue: l10n.stableOnly,
                  ),
                  const SizedBox(height: 16),
                  ThirdPartyDisclaimerContent(
                    text: l10n.thirdPartyDisclaimer,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const HyperosSectionGap(),
          // 支持与更新：反馈、版本、日志
          HyperosSectionLabel(text: l10n.aboutSupportUpdatesSectionTitle),
          HyperosListGroup(
            children: [
              _AboutEntryTile(
                icon: Icons.chat_bubble_outline_rounded,
                iconAccent: HyperosIconColors.green,
                title: l10n.feedbackEntryTitle,
                subtitle: l10n.feedbackEntrySubtitle,
                onTap: () {
                  HyperosNavigation.push(
                    context,
                    settings: const RouteSettings(name: '/feedback'),
                    builder: (_) => const FeedbackScreen(),
                  );
                },
              ),
              _AboutEntryTile(
                icon: Icons.history_rounded,
                iconAccent: HyperosIconColors.blue,
                title: l10n.aboutChangelogTitle,
                subtitle: l10n.aboutChangelogSubtitle,
                onTap: () {
                  Navigator.push(
                    context,
                    HyperosPageRoute(builder: (_) => const ChangelogScreen()),
                  );
                },
              ),
              // 日志入口保留在此，但排障工具的正门是「设置 → 关于 → 诊断与日志」。
              _AboutEntryTile(
                icon: Icons.article_outlined,
                iconAccent: HyperosIconColors.cyan,
                title: l10n.aboutAppLogsTitle,
                subtitle: l10n.aboutAppLogsSubtitle,
                onTap: _openAppLogsPage,
              ),
            ],
          ),
          const HyperosSectionGap(),
          // 产品说明：定位、导入迁移
          HyperosSectionLabel(text: l10n.aboutProductSectionTitle),
          HyperosListGroup(
            children: [
              _AboutEntryTile(
                icon: Icons.flag_outlined,
                iconAccent: HyperosIconColors.purple,
                title: l10n.aboutPositioningTitle,
                subtitle: l10n.aboutPositioningSubtitle,
                onTap: () {
                  _showInfoSheet(
                    context,
                    title: l10n.aboutPositioningTitle,
                    subtitle: l10n.aboutPositioningSubtitle,
                    items: [
                      l10n.aboutPositioningBullet1,
                      l10n.aboutPositioningBullet2,
                      l10n.aboutPositioningBullet3,
                      l10n.aboutPositioningBullet4,
                    ],
                  );
                },
              ),
              _AboutEntryTile(
                icon: Icons.import_export_rounded,
                iconAccent: HyperosIconColors.teal,
                title: l10n.aboutImportMigrationTitle,
                subtitle: l10n.aboutImportMigrationSubtitle,
                onTap: () {
                  _showInfoSheet(
                    context,
                    title: l10n.aboutImportMigrationTitle,
                    subtitle: l10n.aboutImportMigrationSubtitle,
                    items: [
                      l10n.aboutImportMigrationBullet1,
                      l10n.aboutImportMigrationBullet2,
                      l10n.aboutImportMigrationBullet3,
                      l10n.aboutImportMigrationBullet4,
                    ],
                  );
                },
              ),
            ],
          ),
          const HyperosSectionGap(),
          // 社区与开源
          HyperosSectionLabel(text: l10n.aboutCommunitySectionTitle),
          HyperosListGroup(
            children: [
              _AboutEntryTile(
                icon: Icons.group_outlined,
                iconAccent: HyperosIconColors.green,
                title: l10n.aboutContributorsTitle,
                subtitle: l10n.aboutContributorsSubtitle,
                onTap: () {
                  Navigator.push(
                    context,
                    HyperosPageRoute(
                      settings: const RouteSettings(
                        name: '/about/contributors',
                      ),
                      builder: (_) => const ContributorsScreen(),
                    ),
                  );
                },
              ),
              _AboutEntryTile(
                icon: Icons.code_rounded,
                iconAccent: HyperosIconColors.indigo,
                title: l10n.aboutRepositoryTitle,
                subtitle: l10n.aboutRepositorySubtitle,
                onTap: () => _showRepositorySheet(context),
              ),
              _AboutEntryTile(
                icon: Icons.gavel_outlined,
                iconAccent: HyperosIconColors.indigo,
                title: l10n.aboutOpenSourceLicensesTitle,
                subtitle: l10n.aboutOpenSourceLicensesSubtitle,
                onTap: () {
                  Navigator.push(
                    context,
                    HyperosPageRoute(
                      settings: const RouteSettings(
                        name: '/about/oss-licenses',
                      ),
                      builder: (_) => const OpenSourceLicensesScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showInfoSheet(
    BuildContext context, {
    required String title,
    String? subtitle,
    required List<String> items,
  }) {
    showHyperosSheet<void>(
      context: context,
      builder: (sheetContext) =>
          AboutInfoSheetBody(title: title, subtitle: subtitle, items: items),
    );
  }

  void _showRepositorySheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showHyperosSheet<void>(
      context: context,
      builder: (sheetContext) => HyperosSheet(
        title: l10n.aboutRepositorySheetTitle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              kAppRepositoryUrl,
              style: HyperosTypography.listDetail(sheetContext),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.aboutRepositorySheetHint,
              style: HyperosTypography.listDetail(sheetContext),
            ),
            const SizedBox(height: 16),
            // Buttons sit on the frosted sheet surface — do not wrap in
            // HyperosCard (solid white) or the action block looks opaque.
            HyperosButton(
              label: l10n.aboutOpenGitHubAction,
              expand: true,
              onPressed: _openRepository,
            ),
            const SizedBox(height: 10),
            HyperosButton(
              label: l10n.aboutOpenWarehouseRepoAction,
              variant: HyperosButtonVariant.secondary,
              expand: true,
              onPressed: _openWarehouseRepository,
            ),
            const SizedBox(height: 10),
            HyperosButton(
              label: l10n.copyAddress,
              variant: HyperosButtonVariant.secondary,
              expand: true,
              onPressed: _copyRepositoryUrl,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAppLogsPage() =>
      openLogViewer(context, AppLogSource.merged);

  Widget _buildHeroMetaStrip(
    BuildContext context, {
    required String platformValue,
    required String focusValue,
    required String updateValue,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final insetColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainerLowest;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: insetColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _AboutHeroMetaCell(
                label: l10n.platformLabel,
                value: platformValue,
              ),
            ),
            const _AboutHeroMetaDivider(),
            Expanded(
              child: _AboutHeroMetaCell(
                label: l10n.focusLabel,
                value: focusValue,
              ),
            ),
            const _AboutHeroMetaDivider(),
            Expanded(
              child: _AboutHeroMetaCell(
                label: l10n.updateLabel,
                value: updateValue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRepository() async {
    final uri = Uri.tryParse(kAppRepositoryUrl);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyRepositoryUrl() async {
    await Clipboard.setData(const ClipboardData(text: kAppRepositoryUrl));
    if (!mounted) {
      return;
    }
    showAppToast(
      context,
      message: AppLocalizations.of(context)!.copiedRepositoryAddress,
      kind: AppToastKind.success,
    );
  }

  Future<void> _openWarehouseRepository() async {
    final uri = Uri.tryParse('https://github.com/Mutx163/qingyu_warehouse');
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class ReleaseNotesMarkdown extends StatelessWidget {
  final String data;
  final ValueChanged<String?>? onTapLink;
  final bool plainTypography;
  final bool usePrimaryTextColor;

  static final RegExp _versionHeadingPattern = RegExp(
    r'^#\s+v[\d.\-a-zA-Z]+',
    caseSensitive: false,
  );

  const ReleaseNotesMarkdown({
    super.key,
    required this.data,
    this.onTapLink,
    this.plainTypography = false,
    this.usePrimaryTextColor = false,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = plainTypography ? _stripVersionHeading(data) : data;
    final styleSheet = _buildReleaseNotesStyleSheet(
      context,
      plainTypography: plainTypography,
      usePrimaryTextColor: usePrimaryTextColor,
    );
    final bulletStyle = styleSheet.listBullet;
    return MarkdownBody(
      data: normalized,
      selectable: false,
      styleSheet: styleSheet,
      listItemCrossAxisAlignment: plainTypography
          ? MarkdownListItemCrossAxisAlignment.start
          : MarkdownListItemCrossAxisAlignment.baseline,
      bulletBuilder: plainTypography
          ? (_) => Text('·', style: bulletStyle?.copyWith(height: 1.35))
          : null,
      onTapLink: (text, href, title) => onTapLink?.call(href),
    );
  }

  static String _stripVersionHeading(String data) {
    final lines = data.split('\n');
    var start = 0;
    if (lines.isNotEmpty &&
        _versionHeadingPattern.hasMatch(lines.first.trim())) {
      start = 1;
      while (start < lines.length && lines[start].trim().isEmpty) {
        start++;
      }
    }
    return lines.sublist(start).join('\n').trim();
  }

  static MarkdownStyleSheet _buildReleaseNotesStyleSheet(
    BuildContext context, {
    required bool plainTypography,
    required bool usePrimaryTextColor,
  }) {
    final theme = Theme.of(context);
    if (!plainTypography) {
      return MarkdownStyleSheet.fromTheme(theme);
    }
    final onSurface = theme.colorScheme.onSurface;
    final body = usePrimaryTextColor
        ? HyperosTypography.sectionDescription(
            context,
          ).copyWith(color: onSurface)
        : HyperosTypography.sectionDescription(context);
    final sectionHeader = body.copyWith(fontWeight: FontWeight.w600);
    final linkColor = usePrimaryTextColor
        ? onSurface
        : theme.colorScheme.primary;
    return MarkdownStyleSheet(
      p: body,
      pPadding: EdgeInsets.zero,
      listBullet: body,
      listIndent: 12,
      listBulletPadding: const EdgeInsets.only(right: 4),
      blockSpacing: 6,
      h1: sectionHeader,
      h1Padding: EdgeInsets.zero,
      h2: sectionHeader,
      h2Padding: const EdgeInsets.only(top: 8, bottom: 2),
      h3: sectionHeader,
      h3Padding: EdgeInsets.zero,
      h4: body,
      h5: body,
      h6: body,
      strong: body.copyWith(fontWeight: FontWeight.w500),
      em: body.copyWith(fontStyle: FontStyle.italic),
      a: body.copyWith(color: linkColor, decoration: TextDecoration.underline),
      blockquote: body,
      blockquotePadding: const EdgeInsets.only(left: 12),
      code: body.copyWith(
        fontFamily: 'monospace',
        fontSize: (body.fontSize ?? 14) - 1,
      ),
    );
  }
}

class ContributorsScreen extends StatefulWidget {
  const ContributorsScreen({super.key});

  @override
  State<ContributorsScreen> createState() => _ContributorsScreenState();
}

class _ContributorsScreenState extends State<ContributorsScreen> {
  static final WarehouseRepositorySource _warehouseSource =
      WarehouseRepositorySource.fromGitHubUrl(
        'https://github.com/Mutx163/qingyu_warehouse',
      );
  static const String _maintainersCacheKey = 'warehouse_maintainers_cache_v1';

  final WarehouseRepositoryService _repositoryService =
      WarehouseRepositoryService();
  List<_WarehouseMaintainerGroup> _maintainers = const [];
  bool _isLoadingMaintainers = true;
  String? _maintainersError;

  @override
  void initState() {
    super.initState();
    _loadMaintainers();
  }

  Future<List<_WarehouseMaintainerGroup>>
  _fetchMaintainersFromWarehouse() async {
    final settings = context.read<TimetableProvider>().settings;
    final options = WarehouseFetchOptions.fromSettings(settings);
    final rootIndex = await _repositoryService.fetchRootIndex(
      _warehouseSource,
      options: options,
    );
    final groups = <String, List<String>>{};

    final futures = rootIndex.schools
        .map((school) async {
          try {
            final adapters = await _repositoryService.fetchAdaptersIndex(
              _warehouseSource,
              school,
              options: options,
            );
            return adapters.adapters
                .where((adapter) => adapter.maintainer.trim().isNotEmpty)
                .map(
                  (adapter) => (
                    adapter.maintainer.trim(),
                    '${school.name} · ${adapter.adapterName}',
                  ),
                )
                .toList(growable: false);
          } catch (_) {
            return const <(String, String)>[];
          }
        })
        .toList(growable: false);

    final results = await Future.wait(futures);
    for (final entries in results) {
      for (final (maintainer, label) in entries) {
        groups.putIfAbsent(maintainer, () => <String>[]);
        groups[maintainer]!.add(label);
      }
    }

    final result =
        groups.entries
            .map(
              (entry) => _WarehouseMaintainerGroup(
                name: entry.key,
                adapterLabels: [...entry.value]..sort(),
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => left.name.compareTo(right.name));
    return result;
  }

  Future<void> _loadMaintainers() async {
    final cached = await _readMaintainersCache();
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() {
        _maintainers = cached;
        _isLoadingMaintainers = true;
        _maintainersError = null;
      });
    }
    try {
      final fresh = await _fetchMaintainersFromWarehouse();
      if (!mounted) return;
      setState(() {
        _maintainers = fresh;
        _isLoadingMaintainers = false;
        _maintainersError = null;
      });
      await _writeMaintainersCache(fresh);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingMaintainers = false;
        _maintainersError = '$error';
      });
    }
  }

  Future<List<_WarehouseMaintainerGroup>> _readMaintainersCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_maintainersCacheKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .whereType<Map>()
          .map(
            (item) => _WarehouseMaintainerGroup(
              name: item['name'] as String? ?? '',
              adapterLabels:
                  (item['adapterLabels'] as List<dynamic>? ?? const [])
                      .whereType<String>()
                      .toList(),
            ),
          )
          .where((item) => item.name.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeMaintainersCache(
    List<_WarehouseMaintainerGroup> groups,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _maintainersCacheKey,
      jsonEncode(
        groups
            .map(
              (group) => {
                'name': group.name,
                'adapterLabels': group.adapterLabels,
              },
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return HyperosSubpage(
      onBack: () => Navigator.pop(context),
      title: Text(l10n.aboutContributorsScreenTitle),
      child: HyperosListView(
        children: [
          HyperosControlCard(
            title: l10n.aboutDevelopersTitle,
            child: HyperosControlCardInset(
              child: _ContributorRow(
                name: 'Mutx163',
                subtitle: l10n.aboutDeveloperMaintainerSubtitle,
              ),
            ),
          ),
          const HyperosSectionGap(),
          HyperosControlCard(
            title: l10n.aboutWarehouseMaintainersTitle,
            subtitle: l10n.aboutWarehouseMaintainersIntro,
            child: HyperosControlCardInset(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isLoadingMaintainers)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Center(child: HyperosCircularProgress()),
                    ),
                  if (_maintainersError != null && _maintainers.isEmpty)
                    Text(
                      l10n.aboutWarehouseMaintainersLoadFailed(
                        _maintainersError!,
                      ),
                      style: HyperosTypography.listTitle(
                        context,
                      ).copyWith(color: HyperosColors.error(context)),
                    )
                  else if (_maintainers.isEmpty && !_isLoadingMaintainers)
                    Text(
                      l10n.aboutWarehouseMaintainersEmpty,
                      style: HyperosTypography.listDetail(context),
                    )
                  else
                    ..._maintainers.asMap().entries.expand((entry) {
                      final index = entry.key;
                      final group = entry.value;
                      return [
                        if (index > 0) const Divider(height: 24),
                        _ContributorRow(
                          name: group.name,
                          subtitle: l10n.aboutWarehouseMaintainerCount(
                            group.adapterLabels.length,
                          ),
                          details: group.adapterLabels,
                        ),
                      ];
                    }),
                ],
              ),
            ),
          ),
          const HyperosSectionGap(),
          HyperosControlCard(
            title: l10n.aboutParticipateWarehouseTitle,
            subtitle: l10n.aboutParticipateWarehouseSubtitle,
            child: HyperosControlCardInset(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  HyperosButton(
                    label: l10n.aboutOpenWarehouseRepoAction,
                    onPressed: _openWarehouseRepository,
                  ),
                  HyperosButton(
                    label: l10n.copyAddress,
                    variant: HyperosButtonVariant.secondary,
                    onPressed: _copyWarehouseRepositoryUrl,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openWarehouseRepository() async {
    final uri = Uri.tryParse(_warehouseSource.repositoryUrl);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyWarehouseRepositoryUrl() async {
    await Clipboard.setData(
      ClipboardData(text: _warehouseSource.repositoryUrl),
    );
    if (!mounted) {
      return;
    }
    showAppToast(
      context,
      message: AppLocalizations.of(context)!.copiedWarehouseRepositoryAddress,
      kind: AppToastKind.success,
    );
  }
}

EdgeInsets _aboutRowPadding(BuildContext context) {
  final scope = HyperosListTileScope.maybeOf(context);
  return HyperosTokens.rowPadding(
    isFirst: scope?.isFirst ?? true,
    isLast: scope?.isLast ?? true,
  );
}

class _AboutHeroMetaCell extends StatelessWidget {
  const _AboutHeroMetaCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: HyperosTypography.listDetail(context),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: HyperosTypography.listDetail(context).copyWith(
              color: Color.lerp(
                HyperosColors.secondaryText(context),
                HyperosColors.primaryText(context),
                0.25,
              ),
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutHeroMetaDivider extends StatelessWidget {
  const _AboutHeroMetaDivider();

  @override
  Widget build(BuildContext context) {
    return VerticalDivider(
      width: 1,
      thickness: 1,
      color: HyperosColors.dividerLine(context),
    );
  }
}

class _AboutEntryTile extends StatelessWidget {
  const _AboutEntryTile({
    required this.icon,
    required this.iconAccent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconAccent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardColor = HyperosColors.card(context);
    final highlightColor = HyperosColors.rowHighlight(context);

    final row = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: HyperosTokens.listRowMinHeight,
      ),
      child: Padding(
        padding: _aboutRowPadding(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            HyperosIconBadge(icon: icon, accent: iconAccent),
            const SizedBox(width: HyperosTokens.rowContentGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: HyperosTypography.listTitle(context)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: HyperosTypography.listDetail(context),
                    softWrap: true,
                  ),
                ],
              ),
            ),
            SizedBox(width: HyperosTokens.titleChevronGap),
            const HyperosChevron(),
          ],
        ),
      ),
    );

    return HyperosPressableRow(
      onTap: onTap,
      backgroundColor: cardColor,
      highlightColor: highlightColor,
      child: row,
    );
  }
}

class _WarehouseMaintainerGroup {
  final String name;
  final List<String> adapterLabels;

  const _WarehouseMaintainerGroup({
    required this.name,
    required this.adapterLabels,
  });
}

class _ContributorRow extends StatelessWidget {
  final String name;
  final String subtitle;
  final List<String> details;

  const _ContributorRow({
    required this.name,
    required this.subtitle,
    this.details = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: HyperosTypography.listTitle(context)),
        const SizedBox(height: 4),
        Text(subtitle, style: HyperosTypography.listDetail(context)),
        if (details.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...details.map(
            (detail) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $detail',
                style: HyperosTypography.listDetail(context),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
