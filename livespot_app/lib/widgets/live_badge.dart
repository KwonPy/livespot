import 'package:flutter/material.dart';

/// 최근 2시간 안에 실제 제보가 있었던 관광지에만 표시되는 배지. 평소에는 아무것도
/// 보여주지 않다가(공간 자체가 없음), LIVE 상태가 되는 순간에만 나타난다.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFF1744).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: Color(0xFFFF1744)),
          SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(color: Color(0xFFFF1744), fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
