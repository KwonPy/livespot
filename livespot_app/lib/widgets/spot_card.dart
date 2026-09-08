import 'package:flutter/material.dart';
import '../models/spot.dart';

class SpotCard extends StatelessWidget {
  final Spot spot;

  const SpotCard({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.place, size: 40),
        title: Text(spot.title),
        subtitle: Text(spot.address ?? ''),
        onTap: () {
          // Navigate to detail
        },
      ),
    );
  }
}
