import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/badge_tiers.dart';
import '../../models/credit_ledger_entry.dart';
import '../../models/credit_summary.dart';
import '../../services/api_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/credit_badge.dart';

/// 기능 4(Credit) — "Credit 내역" 화면.
///
/// 원장을 통장처럼 행으로 보여준다. 잔액 숫자만 보여주면 "왜 줄었죠?"에 답할 수
/// 없기 때문에 원장을 만든 것이므로(명세 P1), 이 화면이 그 설계의 실물이다.
class CreditLedgerScreen extends StatefulWidget {
  const CreditLedgerScreen({super.key});

  @override
  State<CreditLedgerScreen> createState() => _CreditLedgerScreenState();
}

class _CreditLedgerScreenState extends State<CreditLedgerScreen> {
  /// 최근 100건. 페이지네이션은 이번 범위 밖 — 서버가 최신순으로 자른 것을 그대로 쓴다.
  static const int _limit = 100;

  // build 안에서 만들면 리빌드마다 재호출된다. initState에서 한 번만 만든다.
  late Future<CreditSummary> _summaryFuture;
  late Future<List<CreditLedgerEntry>> _ledgerFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _summaryFuture = ApiService().fetchMyCredit();
    _ledgerFuture = ApiService().fetchMyLedger(limit: _limit);
  }

  Future<void> _refresh() async {
    setState(_load);
    // 인디케이터가 두 요청을 모두 기다리게 한다. 실패는 각 FutureBuilder가 화면에
    // 에러 배너로 보여주므로, 여기서 잡는 건 인디케이터를 멈추기 위한 것뿐이다.
    await Future.wait([
      _summaryFuture.then<void>((_) {}, onError: (Object _) {}),
      _ledgerFuture.then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(title: const Text('Credit 내역')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            const SizedBox(height: 16),
            _buildSummaryCard(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LiveSpotTheme.screenPadding),
              child: Text('적립 내역',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700])),
            ),
            const SizedBox(height: 8),
            _buildLedgerList(),
            const SizedBox(height: 20),
            _buildBadgeGuide(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 상단 요약(잔액 + 뱃지 + 다음 등급)
  // ---------------------------------------------------------------------------

  Widget _buildSummaryCard() {
    return FutureBuilder<CreditSummary>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _card(const SizedBox(
            height: 92,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          ));
        }
        if (snapshot.hasError) {
          // 조회 실패를 "0p"로 그리지 않는다(P26). 실패는 실패로 보인다.
          return _errorBanner('크레딧을 불러오지 못했어요', snapshot.error);
        }
        final summary = snapshot.data!;
        return _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${summary.balance}',
                    style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold)),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6, left: 2),
                  child: Text('p', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                CreditBadgeChip(badge: summary.badge, onDark: true, large: true),
              ],
            ),
            const SizedBox(height: 6),
            Text('누적 적립 ${summary.totalEarned}p',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            // 남은 점수·다음 등급명은 서버가 계산해 준 값(remaining/next_label)을 그대로 쓴다.
            // 앱에서 next_at - total_earned를 다시 계산하지 않는다(P22).
            Text(
              summary.badge.isMax
                  ? '최고 등급이에요'
                  : '다음 등급 ${summary.badge.nextLabel}까지 ${summary.badge.remaining}p',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ));
      },
    );
  }

  Widget _card(Widget child) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }

  // ---------------------------------------------------------------------------
  // 원장 목록
  // ---------------------------------------------------------------------------

  Widget _buildLedgerList() {
    return FutureBuilder<List<CreditLedgerEntry>>(
      future: _ledgerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError) {
          // "아직 적립 내역이 없어요"와 절대 같은 화면이 되면 안 된다.
          return _errorBanner('내역을 불러오지 못했어요', snapshot.error);
        }
        final entries = snapshot.data ?? [];
        if (entries.isEmpty) {
          return _emptyState();
        }
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            children: entries.asMap().entries.map((e) {
              return Column(children: [
                _buildLedgerRow(e.value),
                if (e.key < entries.length - 1) Divider(height: 1, indent: 62, color: Colors.grey[100]),
              ]);
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildLedgerRow(CreditLedgerEntry entry) {
    // 회수(음수)도 삭제가 아니라 행으로 남는다(P1). 부호를 그대로 반영한다.
    final bool isEarn = entry.amount >= 0;
    final Color amountColor = isEarn ? const Color(0xFF2E7D32) : Colors.red[600]!;

    return ListTile(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: LiveSpotTheme.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          entry.reason == 'ANSWER' ? Icons.question_answer_outlined : Icons.edit_note,
          color: LiveSpotTheme.primaryColor,
          size: 18,
        ),
      ),
      title: Text(CreditLedgerEntry.reasonLabel(entry.reason),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(Formatters.reportRecency(entry.createdAt),
          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      trailing: Text(
        '${isEarn ? '+' : ''}${entry.amount}p',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: amountColor),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 34, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text('아직 적립 내역이 없어요', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text('현장 제보와 Q&A 답변으로 Credit이 쌓여요',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 뱃지 등급 안내 (참고용) — kBadgeTiers는 표시 전용이라 판정에는 쓰지 않는다.
  // 내 현재 등급이 어느 줄인지는 요약 카드(CreditBadgeChip)로 이미 보여줬으므로,
  // 여기서는 서버 응답을 기다리지 않고 고정된 5줄을 그대로 보여준다.
  // ---------------------------------------------------------------------------

  Widget _buildBadgeGuide() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('뱃지 등급 안내', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700])),
          const SizedBox(height: 4),
          Text(
            '누적 적립 기준으로 자동으로 올라가요. 크레딧을 써도 등급은 내려가지 않아요.',
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
          const SizedBox(height: 14),
          for (final tier in kBadgeTiers) _buildBadgeGuideRow(tier),
        ],
      ),
    );
  }

  Widget _buildBadgeGuideRow(BadgeTierInfo tier) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tier.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(tier.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Text('누적 ${tier.minCredit}p 이상', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                  ],
                ),
                const SizedBox(height: 2),
                Text(tier.description, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(String title, Object? error) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: Colors.red[400]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red[700])),
                const SizedBox(height: 4),
                // 원문 메시지를 그대로 보여준다 — 디버깅 시간을 줄이는 건 이 한 줄이다.
                Text(error.toString().replaceFirst('Exception: ', ''),
                    style: TextStyle(fontSize: 11, color: Colors.red[400])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
