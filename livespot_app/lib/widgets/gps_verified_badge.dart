import 'package:flutter/material.dart';
import '../config/theme.dart';

class GpsVerifiedBadge extends StatelessWidget {
  const GpsVerifiedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: LiveSpotTheme.badgePadding,
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        border: Border.all(color: Colors.blue),
        borderRadius: BorderRadius.circular(LiveSpotTheme.badgeRadius),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 12, color: Colors.blue),
          SizedBox(width: 4),
          Text('현장인증', style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
