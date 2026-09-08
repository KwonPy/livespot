import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'screens/splash_screen.dart';
import 'screens/home/home_screen.dart';

class LiveSpotApp extends StatelessWidget {
  const LiveSpotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiveSpot',
      debugShowCheckedModeBanner: false,
      theme: LiveSpotTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
