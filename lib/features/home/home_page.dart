import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'widgets/home_search_view.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _searchMode = false;

  void _enterSearch() {
    setState(() => _searchMode = true);
  }

  void _exitSearch() {
    setState(() => _searchMode = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_searchMode) {
      return HomeSearchView(onExit: _exitSearch);
    }
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _HomeSearchEntry(onTap: _enterSearch),
            ),
            const Expanded(child: _HomeBrowseSections()),
          ],
        ),
      ),
    );
  }
}

/// 首页默认态的搜索入口：只读，点击进入完整搜索视图。
class _HomeSearchEntry extends StatelessWidget {
  const _HomeSearchEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: scheme.appInputFill,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(
              Icons.search_rounded,
              color: scheme.onSurfaceVariant,
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '搜索歌曲/歌手/专辑',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

class _HomeBrowseSections extends StatelessWidget {
  const _HomeBrowseSections();

  static const _recent = [
    _HomePlaceholder('夜曲', '周杰伦'),
    _HomePlaceholder('晴天', '周杰伦'),
    _HomePlaceholder('七里香', '周杰伦'),
    _HomePlaceholder('稻香', '周杰伦'),
    _HomePlaceholder('起风了', '买辣椒也用券'),
  ];

  static const _favorites = [
    _HomePlaceholder('平凡之路', '朴树'),
    _HomePlaceholder('海阔天空', 'Beyond'),
    _HomePlaceholder('孤勇者', '陈奕迅'),
    _HomePlaceholder('后来', '刘若英'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 140),
      children: const [
        _HomeSection(title: '最近播放', items: _recent),
        SizedBox(height: 28),
        _HomeSection(title: '我的收藏', items: _favorites),
      ],
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({required this.title, required this.items});

  final String title;
  final List<_HomePlaceholder> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _HomeTile(item: items[index]),
          ),
        ),
      ],
    );
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({required this.item});

  final _HomePlaceholder item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 120,
              height: 120,
              color: scheme.primaryContainer,
              alignment: Alignment.center,
              child: Icon(
                Icons.music_note_rounded,
                color: scheme.onPrimaryContainer,
                size: 38,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomePlaceholder {
  const _HomePlaceholder(this.title, this.subtitle);

  final String title;
  final String subtitle;
}
