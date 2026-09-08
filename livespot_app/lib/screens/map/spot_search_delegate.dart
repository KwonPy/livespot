import 'dart:async';

import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/spot.dart';
import '../../services/api_service.dart';

enum _SearchStatus { idle, loading, loaded, error }

class _SearchState {
  final _SearchStatus status;
  final List<Spot> results;

  const _SearchState(this.status, this.results);

  static const idle = _SearchState(_SearchStatus.idle, []);
  static const loading = _SearchState(_SearchStatus.loading, []);
  static const error = _SearchState(_SearchStatus.error, []);
  factory _SearchState.loaded(List<Spot> spots) => _SearchState(_SearchStatus.loaded, spots);
}

const Map<String, (String, IconData)> _typeMeta = {
  '12': ('관광지', Icons.landscape),
  '14': ('문화시설', Icons.museum),
  '15': ('축제/행사', Icons.celebration),
  '28': ('레포츠', Icons.sports_tennis),
  '38': ('쇼핑', Icons.shopping_bag),
};

/// 지도 탭 관광지 검색. 결과를 탭하면 검색 화면을 닫으며 선택된 Spot을 반환한다
/// (호출부는 `showSearch<Spot?>`의 반환값을 받아 상세페이지로 이동한다).
class SpotSearchDelegate extends SearchDelegate<Spot?> {
  SpotSearchDelegate() : super(searchFieldLabel: '여행지, 지역, 키워드로 검색');

  final ApiService _apiService = ApiService();
  final ValueNotifier<_SearchState> _state = ValueNotifier(_SearchState.idle);
  Timer? _debounce;
  String _lastSearchedQuery = '';

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    _scheduleSearch(query);
    return _SearchBody(state: _state, onSelect: (spot) => close(context, spot));
  }

  @override
  Widget buildResults(BuildContext context) {
    _scheduleSearch(query, immediate: true);
    return _SearchBody(state: _state, onSelect: (spot) => close(context, spot));
  }

  void _scheduleSearch(String rawQuery, {bool immediate = false}) {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) {
      _debounce?.cancel();
      _lastSearchedQuery = '';
      _state.value = _SearchState.idle;
      return;
    }
    if (trimmed == _lastSearchedQuery) return; // 이미 이 검색어로 조회했거나 조회 중

    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: immediate ? 0 : 400), () async {
      _lastSearchedQuery = trimmed;
      _state.value = _SearchState.loading;
      try {
        final results = await _apiService.searchSpots(trimmed);
        if (_lastSearchedQuery == trimmed) {
          _state.value = _SearchState.loaded(results);
        }
      } catch (_) {
        if (_lastSearchedQuery == trimmed) {
          _state.value = _SearchState.error;
        }
      }
    });
  }

  @override
  void close(BuildContext context, Spot? result) {
    _debounce?.cancel();
    super.close(context, result);
  }
}

class _SearchBody extends StatelessWidget {
  final ValueNotifier<_SearchState> state;
  final ValueChanged<Spot> onSelect;

  const _SearchBody({required this.state, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_SearchState>(
      valueListenable: state,
      builder: (context, s, _) {
        switch (s.status) {
          case _SearchStatus.idle:
            return const _CenterMessage(icon: Icons.search, text: '관광지 이름이나 지역으로 검색해보세요');
          case _SearchStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case _SearchStatus.error:
            return const _CenterMessage(icon: Icons.wifi_off, text: '검색 중 오류가 발생했습니다. 다시 시도해주세요.');
          case _SearchStatus.loaded:
            if (s.results.isEmpty) {
              return const _CenterMessage(icon: Icons.sentiment_dissatisfied, text: '검색 결과가 없습니다');
            }
            return ListView.separated(
              itemCount: s.results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final spot = s.results[index];
                final meta = _typeMeta[spot.category];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: LiveSpotTheme.primaryColor.withOpacity(0.1),
                    child: Icon(meta?.$2 ?? Icons.place, color: LiveSpotTheme.primaryColor, size: 20),
                  ),
                  title: Text(spot.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    [if (meta != null) meta.$1, if (spot.address != null) spot.address!].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onSelect(spot),
                );
              },
            );
        }
      },
    );
  }
}

class _CenterMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CenterMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }
}
