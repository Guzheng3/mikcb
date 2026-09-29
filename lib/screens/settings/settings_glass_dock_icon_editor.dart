part of '../timetable_settings_screen.dart';

/// 圆钮图标挑选页：遍历可选图标名全集（[kMiuixIconNames]，名字沿用旧 Miuix
/// 小驼峰以便旧持久化数据继续有效），支持按名称过滤。布局自上而下：
/// 1. 搜索框卡片（置顶，与下方网格同一缩进体系，左右边缘对齐）；
/// 2. 图标网格：首格固定为「默认（加号）」（清空自定义、恢复默认加号），
///    其后为过滤结果。
///
/// 网格按「行」惰性构建（[HyperosListView] 的 itemCount/itemBuilder 模式，
/// 见 spec hyperos-blurred-header.md 的 Heavy sub-page lists 一节）：列数由
/// 可用宽度推导，一行内各格 Expanded 均分宽度——行的左右总宽与上方搜索
/// 卡片完全一致，不再出现居中 Wrap 收窄一档的观感。
///
/// 性能：旧实现用 HyperosListView(children:)（SingleChildScrollView+Column）
/// 一次性构建 156 个图标格并常驻，且矢量路径每帧重新解析。现在图标是
/// Material 字形（[IconData]），行级惰性构建后构建/绘制成本都可忽略。
class _GlassDockIconPickerScreen extends StatefulWidget {
  const _GlassDockIconPickerScreen({
    required this.initialName,
    required this.onChanged,
  });

  final String? initialName;
  final ValueChanged<String?> onChanged;

  @override
  State<_GlassDockIconPickerScreen> createState() =>
      _GlassDockIconPickerScreenState();
}

class _GlassDockIconPickerScreenState
    extends State<_GlassDockIconPickerScreen> {
  /// 网格几何：沿用旧 Wrap 视觉参数——格间水平 8、行距 10、最小格宽 76；
  /// 列数按可用宽度推导后夹在 [3, _maxColumns]。
  static const _cellSpacing = 8.0;
  static const _halfCellSpacing = _cellSpacing / 2;
  static const _rowSpacing = 10.0;
  static const _minCellWidth = 76.0;
  static const _maxColumns = 6;

  /// 单元格内部密度：26 图标 + 5 间距 + 名称微字（行高由内容自然撑起）。
  static const _iconSize = 26.0;

  late String? _selected = widget.initialName;

  /// 搜索框滚动出可视区被 ListView 回收后，靠自有 controller 恢复文本
  /// （builder 列表的条目会随滚动销毁重建，裸 TextField 会丢内容）。
  late final TextEditingController _searchController;
  String _filter = '';

  /// 过滤结果缓存：只在搜索词变化时重算，build 内不做字符串处理。
  List<String> _filteredNames = const [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _recomputeFiltered();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _recomputeFiltered() {
    final query = _filter.trim().toLowerCase();
    final names = kMiuixIconNames;
    _filteredNames = query.isEmpty
        ? names
        : names
              .where((n) => n.toLowerCase().contains(query))
              .toList(growable: false);
  }

  void _onSearchChanged(String value) {
    setState(() {
      _filter = value;
      _recomputeFiltered();
    });
  }

  void _select(String? name) {
    setState(() {
      _selected = name;
    });
    widget.onChanged(name);
  }

  int _columnCountFor(double contentWidth) {
    if (contentWidth <= _minCellWidth) {
      return 3;
    }
    final columns =
        ((contentWidth + _cellSpacing) / (_minCellWidth + _cellSpacing))
            .floor();
    return columns.clamp(3, _maxColumns);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return HyperosSubpage(
      onBack: () => Navigator.pop(context),
      title: Text(l10n.glassDockButtonIconTitle),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 内容宽 = 页面宽 - HyperosListView 左右 listPadding（16+16），
          // 与搜索卡片的可视边缘同源，行宽因此与其严格一致。
          final contentWidth =
              constraints.maxWidth - HyperosTokens.listPadding.horizontal;
          final columns = _columnCountFor(contentWidth);
          // 首格为「默认（加号）」，其后是过滤结果。
          final cellCount = _filteredNames.length + 1;
          final rowCount = (cellCount + columns - 1) ~/ columns;
          return HyperosListView(
            itemCount: rowCount + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildSearchCard(l10n);
              }
              return _buildGridRow(l10n, rowIndex: index - 1, columns: columns);
            },
          );
        },
      ),
    );
  }

  Widget _buildSearchCard(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: HyperosCard(
        // 输入组件不裸放在 scaffold 背景上：搜索框填充 #F0F0F0 对页面背景
        // #F2F2F2 无对比；按 showcase 同款惯例垫卡片给表面。
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: HyperosSearchBar(
          controller: _searchController,
          hint: l10n.glassDockButtonIconSearchHint,
          onChanged: _onSearchChanged,
          onClear: () {
            _searchController.clear();
            _onSearchChanged('');
          },
        ),
      ),
    );
  }

  /// 一行 [columns] 格：Expanded 均分内容宽，行左右总宽与上方卡片一致。
  /// 首末格贴边（无外边距），相邻格之间以半间距（4+4=8）分隔；末行不足
  /// 的槽位用空占位保持已渲染格子的宽度与上方各行相同（左对齐收尾）。
  Widget _buildGridRow(
    AppLocalizations l10n, {
    required int rowIndex,
    required int columns,
  }) {
    final cellCount = _filteredNames.length + 1;
    final first = rowIndex * columns;
    final end = first + columns > cellCount ? cellCount : first + columns;
    // 不固定行高：各格内部结构一致，行高由内容自然撑起且逐行相等；
    // 系统大字号下行高随文字放大，避免固定值溢出。
    return Padding(
      padding: const EdgeInsets.only(bottom: _rowSpacing),
      child: Row(
        children: [
          for (var i = first; i < end; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: i % columns == 0 ? 0 : _halfCellSpacing,
                  right: i % columns == columns - 1 ? 0 : _halfCellSpacing,
                ),
                child: _buildCell(l10n, cellIndex: i),
              ),
            ),
          for (var i = end; i < first + columns; i++)
            const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }

  Widget _buildCell(AppLocalizations l10n, {required int cellIndex}) {
    final isDefault = cellIndex == 0;
    final name = isDefault ? null : _filteredNames[cellIndex - 1];
    final selected = isDefault ? _selected == null : _selected == name;
    return _IconCell(
      label: isDefault ? l10n.glassDockButtonIconDefault : name!,
      selected: selected,
      icon: isDefault ? null : miuixIconByName(name!),
      onTap: () {
        _select(name);
        Navigator.pop(context);
      },
    );
  }
}

/// 图标格：Material 图标 + 名称小字；选中态描边主色。宽度由所在行 Expanded
/// 决定（不再写死 76），高度随行高居中。
class _IconCell extends StatelessWidget {
  const _IconCell({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;

  /// 该格对应的图标；null 时回退加号图标（默认格用）。
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final iconColor = selected ? primary : MiuixContentColor.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          color: selected
              ? HyperosBlurredHeader.accentSurfaceTintColor(primary)
              : HyperosColors.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primary : Colors.transparent,
            width: 1.6,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: _GlassDockIconPickerScreenState._iconSize,
              height: _GlassDockIconPickerScreenState._iconSize,
              child: MiuixIcon(
                icon: icon ?? Icons.add_rounded,
                size: 22,
                tint: iconColor,
                      ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: HyperosTypography.listDetail(context).copyWith(
                // 11 为字阶最小档：图标名微字不再新增字号刻度
                fontSize: 11,
                color: selected
                    ? primary
                    : HyperosColors.secondaryText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
