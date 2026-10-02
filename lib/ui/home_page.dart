import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Codebase Map')),
      body: const Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Text(
            'Project scaffold ready.\nSource analysis is coming next.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
