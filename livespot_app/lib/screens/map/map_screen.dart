import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/theme.dart';
import '../../models/spot.dart';
import '../../models/congestion_info.dart';
import '../../services/api_service.dart';
import '../../widgets/briefing_card.dart';
import '../detail/spot_detail_screen.dart';
import 'spot_search_delegate.dart';

class MapScreen extends StatefulWidget {
  final bool isActive;

  const MapScreen({super.key, this.isActive = true});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  int _selectedCategoryIndex = 0;
  Spot? _selectedSpot;

  final List<Map<String, dynamic>> _categories = [
    {'label': '전체', 'icon': Icons.apps},
    {'label': '관광지', 'icon': Icons.landscape},
    {'label': '문화시설', 'icon': Icons.museum},
    {'label': '축제', 'icon': Icons.celebration},
    {'label': '체험', 'icon': Icons.sports_tennis},
  ];

  final ApiService _apiService = ApiService();

  List<Spot> _spots = [];
  bool _isLoading = true;
  double _userLat = 37.5666; // 서울 시청 (fallback)
  double _userLng = 126.9784;
  bool _gpsObtained = false;
  bool _backendError = false;
  bool _isRefreshingSpots = false;

  final String _viewType = 'spot-map-container';
  bool _mapInitialized = false;
  bool _spotsReady = false;
  html.DivElement? _mapElement;

  /// 직전에 JS로 보낸 마커 payload. 동일하면 JS 호출 자체를 건너뛴다.
  String? _lastSpotsJson;

  @override
  void initState() {
    super.initState();

    // Web View Factory 등록 (HTML 요소를 Flutter 위젯 트리에 삽입)
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        _mapElement ??= html.DivElement()
          ..style.width = '100%'
          ..style.height = '100%';
        return _mapElement!;
      },
    );

    // JS에서 Flutter로 클릭 이벤트를 전달받기 위한 콜백 등록
    js.context['onSpotMarkerClick'] = (String contentId) {
      if (!mounted) return;
      final index = _spots.indexWhere((s) => s.contentId == contentId);
      if (index == -1) return;
      setState(() {
        _selectedSpot = _spots[index];
      });
    };

    _getUserLocationAndFetch();
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      // 지도 탭이 지금 막 화면에 보이게 됨
      if (!_mapInitialized) {
        if (_spotsReady) _tryInitMap();
      } else {
        // 이미 초기화된 지도가 숨겨진 동안 크기가 0이었을 수 있으므로 재계산
        js.context.callMethod('relayoutSpotMap', [_userLat, _userLng]);
      }
    }
  }

  @override
  void dispose() {
    // 지도 인스턴스/마커/이벤트 정리
    js.context.callMethod('disposeSpotMap');
    js.context.deleteProperty('onSpotMarkerClick');
    _mapInitialized = false;
    super.dispose();
  }

  Future<void> _getUserLocationAndFetch() async {
    setState(() {
      _isLoading = true;
      _backendError = false;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _userLat = position.latitude;
      _userLng = position.longitude;
      _gpsObtained = true;
    } catch (e) {
      _userLat = 37.5666;
      _userLng = 126.9784;
      _gpsObtained = false;
      print('GPS 획득 실패, 서울 시청 좌표 사용: $e');
    }

    // 서버에서 주변 관광지 로드
    try {
      final spots = await _apiService.fetchNearbySpots(_userLat, _userLng);
      if (mounted) {
        setState(() {
          _spots = spots;
          _isLoading = false;
          _backendError = false;
        });
      }
    } catch (e) {
      print('백엔드 연결 실패: $e');
      if (mounted) {
        setState(() {
          _spots = [];
          _isLoading = false;
          _backendError = true;
        });
      }
    }

    _spotsReady = true;
    if (widget.isActive) {
      _tryInitMap();
    }
  }

  /// "내 위치" 버튼 핸들러. GPS/네트워크 응답을 기다리지 않고
  /// 캐시된 위치로 먼저 지도를 이동시킨 뒤, 백그라운드에서 정확한
  /// 위치와 주변 관광지를 갱신합니다. 전체 화면 로딩은 띄우지 않습니다.
  Future<void> _onMyLocationTap() async {
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && _mapInitialized) {
        js.context.callMethod('panToSpotMap', [lastKnown.latitude, lastKnown.longitude]);
      }
    } catch (_) {
      // 캐시된 위치가 없거나 지원되지 않음 - 무시하고 계속 진행
    }

    if (_isRefreshingSpots) return;
    setState(() => _isRefreshingSpots = true);

    double newLat = _userLat;
    double newLng = _userLng;
    bool gpsOk = _gpsObtained;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      newLat = position.latitude;
      newLng = position.longitude;
      gpsOk = true;
    } catch (e) {
      print('내 위치 갱신 실패, 기존 위치 유지: $e');
    }

    if (mounted) {
      setState(() {
        _userLat = newLat;
        _userLng = newLng;
        _gpsObtained = gpsOk;
      });
    }

    if (_mapInitialized) {
      js.context.callMethod('panToSpotMap', [newLat, newLng]);
    }

    try {
      final spots = await _apiService.fetchNearbySpots(newLat, newLng);
      if (mounted) {
        setState(() {
          _spots = spots;
          _backendError = false;
        });
        _updateSpotMap();
      }
    } catch (e) {
      print('백엔드 연결 실패(갱신): $e');
      // 갱신 실패 시 기존에 떠 있던 마커/스팟은 그대로 유지한다.
      if (mounted) {
        setState(() => _backendError = true);
      }
    }

    if (mounted) {
      setState(() => _isRefreshingSpots = false);
    }
  }

  /// 지도 마커 색상이 무엇을 뜻하는지 보여주는 범례 버튼 (기능 9).
  /// 마커 색상은 실시간 현장 상황이 아니라 "방문 집중률 예측"이라는 걸 명시적으로 알려준다.
  Widget _buildLegendButton() {
    return GestureDetector(
      onTap: _showCongestionLegend,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)],
        ),
        child: Icon(Icons.info_outline, size: 20, color: Colors.grey[600]),
      ),
    );
  }

  void _showCongestionLegend() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('지도 마커 색상 안내', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                '한국관광공사 방문 집중률 "예측" 기준입니다. 과거 방문 패턴으로 예측한 값이라\n'
                '실시간 현장 상황과 다를 수 있어요. 실제 현장 제보는 관광지 상세페이지에서 확인하세요.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4),
              ),
              const SizedBox(height: 16),
              _legendRow(const Color(0xFF4CAF50), '여유 (집중률 0~39%)'),
              _legendRow(const Color(0xFFFF9800), '보통 (집중률 40~69%)'),
              _legendRow(const Color(0xFFF44336), '높음 (집중률 70~100%)'),
              _legendRow(null, '예측 대상 아님 (테두리 없음)'),
              const SizedBox(height: 10),
              Text(
                '집중률 예측은 주요 관광지를 대상으로 제공돼요. 축제·상점·조형물 등은\n'
                '예측 대상이 아니라서, 값을 지어내지 않고 테두리 없이 표시합니다.',
                style: TextStyle(fontSize: 11, color: Colors.grey[500], height: 1.4),
              ),
            ],
          ),
        );
      },
    );
  }

  /// color가 null이면 테두리 없는 마커(예측 대상 아님)를 나타내는 빈 원으로 그린다.
  Widget _legendRow(Color? color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color ?? Colors.white,
              shape: BoxShape.circle,
              border: color == null ? Border.all(color: Colors.grey[300]!) : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  /// 관광지 검색. 지도를 이동시키지 않고, 선택된 관광지의 상세페이지로 바로 진입한다.
  Future<void> _openSearch() async {
    final spot = await showSearch<Spot?>(context: context, delegate: SpotSearchDelegate());
    if (spot != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)));
    }
  }

  /// 플랫폼 뷰(div)가 실제로 DOM에 붙은 뒤에 지도를 초기화합니다.
  void _tryInitMap() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive) return;
      _updateSpotMap();
    });
  }

  Future<void> _updateSpotMap() async {
    try {
      if (!_mapInitialized) {
        if (_mapElement != null) {
          js.context.callMethod('initSpotMap', [_mapElement, _userLat, _userLng]);
          _mapInitialized = true;
        } else {
          print('MapTiler Error: _mapElement is null');
          return;
        }
      } else {
        js.context.callMethod('panToSpotMap', [_userLat, _userLng]);
      }

      // 마커 색상은 방문 집중률 "예측"(기능 9, 한국관광공사 TatsCnctrRateService)을 쓴다.
      // 실제 제보(현장 실측)와는 성격이 다른 지표라 절대 섞지 않는다 — 실측 상태는
      // 상세페이지에서만 별도로 보여준다. LIVE 점(펄스)도 지도에서는 표시하지 않는다:
      // "최근 제보 여부"는 마커를 눌러 여는 카드(BriefingCard)에서만 보여준다.
      // 보이는 관광지들을 한 번에 보내고 서버가 시군구 단위로 묶어 조회한다 — 마커가
      // 20개여도 실제 외부 API 호출은 보통 1~3회다.
      final spots = _spots;
      Map<String, CongestionInfo> congestionByContentId = {};
      try {
        congestionByContentId = await _apiService.fetchCongestionBatch(spots);
      } catch (_) {
        // 실패해도 지도는 그대로 뜬다 — 아래에서 전부 '정보없음' 마커로 대체된다.
      }
      if (!mounted) return;

      // Dart 객체를 JSON 스트링으로 변환하여 JS로 전달
      final spotsJson = jsonEncode(List.generate(spots.length, (i) {
        final s = spots[i];
        final level = congestionByContentId[s.contentId]?.level ?? 'unknown';
        return {
          'id': s.contentId,
          'title': s.title,
          'lat': s.latitude,
          'lng': s.longitude,
          'congestionLevel': level,
          // 현장 인원(presence, 기능 6)은 아직 없으므로 항상 0으로 두어 배지를 숨긴다.
          'onsiteCount': 0,
        };
      }));

      // 내용이 그대로면 JS 호출 자체를 생략 (JS 쪽에서도 id 기준 diffing 수행)
      if (spotsJson == _lastSpotsJson) return;
      _lastSpotsJson = spotsJson;

      js.context.callMethod('updateSpotMarkers', [spotsJson]);
    } catch (e) {
      print('Error updating MapTiler map: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // MapTiler Web View 영역
          Positioned.fill(
            child: HtmlElementView(viewType: _viewType),
          ),

          // 로딩 오버레이
          if (_isLoading)
            Container(
              color: Colors.white.withOpacity(0.8),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('주변 관광지를 검색 중...', style: TextStyle(color: Colors.black54, fontFamily: 'Pretendard')),
                  ],
                ),
              ),
            ),

          // 백엔드 연결 실패 배너
          if (_backendError)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.red[400], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '서버에 연결할 수 없습니다. 백엔드가 실행 중인지 확인해주세요.',
                        style: TextStyle(color: Colors.red[700], fontSize: 12),
                      ),
                    ),
                    GestureDetector(
                      onTap: _getUserLocationAndFetch,
                      child: Text('재시도', style: TextStyle(color: Colors.red[700], fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),

          // 상단 검색바
          Positioned(
            top: MediaQuery.of(context).padding.top + (_backendError ? 60 : 16),
            left: 16,
            right: 16,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              elevation: 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openSearch,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      const Icon(Icons.search, color: Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _gpsObtained
                              ? '내 위치 주변 관광지 (${_spots.length}개)'
                              : '서울 시청 주변 관광지 (${_spots.length}개)',
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                      ),
                      Container(width: 1, height: 20, color: Colors.grey[200]),
                      const SizedBox(width: 10),
                      Icon(Icons.tune, color: Colors.grey[500], size: 20),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // 카테고리 칩
          Positioned(
            top: MediaQuery.of(context).padding.top + (_backendError ? 120 : 76),
            left: 0,
            right: 0,
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  _buildLegendButton(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _selectedCategoryIndex == index;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategoryIndex = index),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isSelected ? LiveSpotTheme.primaryColor : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(cat['icon'] as IconData, size: 16, color: isSelected ? Colors.white : Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            cat['label'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              color: isSelected ? Colors.white : Colors.grey[700],
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 내 위치 버튼
          Positioned(
            bottom: _selectedSpot != null ? 280 : 30,
            right: 16,
            child: GestureDetector(
              onTap: _onMyLocationTap,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: LiveSpotTheme.primaryColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: LiveSpotTheme.primaryColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: _isRefreshingSpots
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                      )
                    : const Icon(Icons.my_location, color: Colors.white, size: 24),
              ),
            ),
          ),

          // 하단 브리핑 카드
          if (_selectedSpot != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (details.delta.dy > 10) {
                    setState(() => _selectedSpot = null);
                  }
                },
                child: BriefingCard(spot: _selectedSpot!),
              ),
            ),
        ],
      ),
    );
  }
}
