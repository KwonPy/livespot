import 'package:flutter/material.dart';
import '../../models/bookmark_entry.dart';
import '../../models/spot.dart';
import '../../services/api_service.dart';
import '../../utils/formatters.dart';
import '../../utils/image_url.dart';
import '../detail/spot_detail_screen.dart';

/// 기능 12(MyPage) "북마크" — 내가 저장한 관광지를 최신순으로 보여준다.
///
/// "내 제보"·"내 Q&A"와 달리 **항목을 탭하면 관광지 상세페이지로 이동한다.** 두 화면은
/// "내가 남긴 기록"(읽기 전용 이력)이지만 북마크는 "다시 가려고 담아둔 장소"(바로가기)라,
/// 이동이 기능의 본질이다.
///
/// 해제 버튼은 두지 않는다(정책 P-B23) — 목록은 순수 조회 + 이동만 하고, 해제는
/// 상세페이지의 북마크 버튼 재탭으로만 한다. 탭 동작이 하나뿐이라 오조작이 없다.
///
/// 목록은 캐시하지 않고 화면에 들어올 때마다 새로 조회한다. 상세페이지에서 해제하고
/// 돌아왔는데 옛 목록이 남아 있는 상황을 막기 위해서다.
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  late Future<List<BookmarkEntry>> _bookmarksFuture;

  @override
  void initState() {
    super.initState();
    _bookmarksFuture = ApiService().fetchBookmarks();
  }

  Future<void> _refresh() async {
    setState(() => _bookmarksFuture = ApiService().fetchBookmarks());
    await _bookmarksFuture.then<void>((_) {}, onError: (Object _) {});
  }

  // 상세페이지 진입에 좌표는 필요 없다 — 날씨·집중률·브리핑 전부 서버가 content_id로
  // 좌표를 자체 조회한다. HOT SPOTS 진입(live_screen.dart)이 이미 같은 방식이다.
  //
  // 조인 실패로 spot_name이 null인 항목도 이동을 막지 않는다. 상세페이지가 자체적으로
  // 다시 조회하므로 그쪽에서 살아날 수 있다.
  Future<void> _openSpot(BookmarkEntry b) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SpotDetailScreen(
          spot: Spot(
            contentId: b.contentId,
            title: b.spotName ?? '관광지 정보 없음 (ID ${b.contentId})',
            address: b.spotAddress,
            imageUrl: b.spotImageUrl,
          ),
        ),
      ),
    );
    // 상세페이지에서 북마크를 해제했을 수 있으므로 돌아오면 목록을 다시 받는다.
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(title: const Text('북마크')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<BookmarkEntry>>(
          future: _bookmarksFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            }
            // 실패를 빈 상태로 뭉개지 않는다 — "0건"과 "못 불러옴"은 다른 화면이어야 한다.
            if (snapshot.hasError) {
              return _errorState(snapshot.error);
            }
            final bookmarks = snapshot.data ?? [];
            if (bookmarks.isEmpty) {
              return _emptyState();
            }
            // 서버가 이미 최신순(created_at DESC)으로 준다 — 클라이언트에서 다시 정렬하지 않는다.
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              itemCount: bookmarks.length,
              itemBuilder: (context, index) => _buildBookmarkCard(bookmarks[index]),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBookmarkCard(BookmarkEntry b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openSpot(b),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _thumbnail(b.spotImageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.spotName ?? '관광지 정보 없음 (ID ${b.contentId})',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (b.spotAddress != null && b.spotAddress!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          b.spotAddress!,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        Formatters.reportRecency(b.createdAt),
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[300]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbnail(String? url) {
    const double size = 56;
    Widget placeholder() => Container(
          width: size,
          height: size,
          color: Colors.grey[100],
          child: Icon(Icons.landscape, size: 22, color: Colors.grey[300]),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: url == null || url.isEmpty
          ? placeholder()
          : Image.network(
              resolveImageUrl(url)!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder(),
            ),
    );
  }

  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 80),
      children: [
        Icon(Icons.bookmark_border, size: 40, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Center(child: Text('아직 저장한 관광지가 없어요', style: TextStyle(fontSize: 13, color: Colors.grey[500]))),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '관광지 상세페이지의 북마크 버튼으로 담아보세요',
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ),
      ],
    );
  }

  Widget _errorState(Object? error) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      children: [
        Icon(Icons.error_outline, size: 36, color: Colors.red[300]),
        const SizedBox(height: 12),
        Center(child: Text('북마크 목록을 불러오지 못했어요', style: TextStyle(fontSize: 13, color: Colors.red[600], fontWeight: FontWeight.bold))),
        const SizedBox(height: 4),
        Center(
          child: Text(
            error.toString().replaceFirst('Exception: ', ''),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.red[400]),
          ),
        ),
      ],
    );
  }
}
