import 'package:flutter/material.dart';

import '../ui/home_page.dart';
import 'project_controller.dart';

class CodebaseMapApp extends StatelessWidget {
  const CodebaseMapApp({super.key, this.controller});

  final ProjectController? controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Codebase Map',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: HomePage(controller: controller),
    );
  }
}
