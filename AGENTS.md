\# CyShineMusic

Flutter+Riverpod音乐App。本地D:/projects/CyShineMusic。

主题seed #7C3AED，深色，surfaceContainerLow=#1E1E1E。

已做：UI改造、搜索1:1复刻、按源独立无限滚动（酷我/酷狗/QQ/全部各自page/results/hasMore/isLoadingMore，Map<MusicSource,\_SourcePageState>在home\_search\_view.dart）。

未动：包名、应用名、播放逻辑、网络层。

搜索：home\_search\_view.dart + search\_controller.dart（selectSource只改高亮不搜索，setSource自动搜page1给发现页用）。

真机：华为Mate60Pro。

规则：先读文件列改动点→确认→写码→dart analyze lib无报错。

