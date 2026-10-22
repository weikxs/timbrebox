import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../widgets/hero_panel.dart';

class HomeView extends StatelessWidget {
  const HomeView({
    required this.controller,
    required this.onOpenSearch,
    super.key,
  });
  final AppController controller;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: HeroPanel(controller: controller, onOpenSearch: onOpenSearch),
  );
}
