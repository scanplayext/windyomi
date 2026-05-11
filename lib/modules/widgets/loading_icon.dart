import 'package:flutter/material.dart';

class LoadingIcon extends StatelessWidget {
  const LoadingIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B13),
      body: Center(
        child: Image.asset(
          "assets/app_icons/icon.png",
          fit: BoxFit.cover,
          height: 100,
        ),
      ),
    );
  }
}
