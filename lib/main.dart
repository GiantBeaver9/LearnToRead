import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: LearnToReadApp()));
}

/// App shell placeholder. Unit 1 (design system & app shell) replaces this
/// with the real router and themed shell; see PRD.md §8.
class LearnToReadApp extends StatelessWidget {
  const LearnToReadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'LearnToRead',
      home: Scaffold(body: Center(child: Text('LearnToRead'))),
    );
  }
}
