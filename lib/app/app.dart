import 'package:flutter/material.dart';

import '../ui/home_page.dart';

class CodebaseMapApp extends StatelessWidget {
  const CodebaseMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Codebase Map',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const HomePage(),
    );
  }
}
