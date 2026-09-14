import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/music_api.dart';
import '../../core/models/enums.dart';
import '../../core/models/leaderboard_info.dart';
import '../../core/models/music_info.dart';

/// 首页推荐音乐：取酷我源第一个排行榜的前 6 首歌。
/// 加载失败时返回空列表，首页会自动回退到本地下载音乐。
final homeRecommendMusicProvider =
    FutureProvider.autoDispose<List<MusicInfo>>((ref) async {
      final api = ref.watch(musicApiProvider);
      try {
        final boards = await api.getLeaderboards(MusicSource.kw);
        if (boards.isEmpty) return const [];
        final first = boards.first;
        final info = await api.getLeaderboard(
          source: first.source,
          boardId: first.boardId,
          maxTracks: 6,
        );
        return info.tracks.take(6).toList(growable: false);
      } catch (_) {
        return const [];
      }
    });

/// 首页推荐专辑使用的排行榜列表（酷我源），
/// 用于推荐专辑区块在 featuredPlaylists 之外提供更多内容。
final homeRecommendBoardsProvider =
    FutureProvider.autoDispose<List<LeaderboardSummary>>((ref) async {
      final api = ref.watch(musicApiProvider);
      try {
        final boards = await api.getLeaderboards(MusicSource.kw);
        return boards.take(6).toList(growable: false);
      } catch (_) {
        return const [];
      }
    });
