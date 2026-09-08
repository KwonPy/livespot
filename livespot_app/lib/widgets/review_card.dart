import 'package:flutter/material.dart';
import '../models/review.dart';
import 'gps_verified_badge.dart';

class ReviewCard extends StatelessWidget {
  final Review review;

  const ReviewCard({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person)),
                const SizedBox(width: 8),
                Text(review.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (review.isGpsVerified) const GpsVerifiedBadge(),
              ],
            ),
            const SizedBox(height: 8),
            Text(review.content),
          ],
        ),
      ),
    );
  }
}
