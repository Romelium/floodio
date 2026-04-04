import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/terminal_log_provider.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isAtBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        _isAtBottom = _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 50;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(terminalLogControllerProvider);

    // Auto-scroll to bottom when new logs arrive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _isAtBottom) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.greenAccent,
        title: const Text(
          'System Diagnostics',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.greenAccent, blurRadius: 4)],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () =>
                ref.read(terminalLogControllerProvider.notifier).clear(),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.greenAccent.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        margin: const EdgeInsets.all(8.0),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12.0),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            final isError = log.contains('[-]');
            final isInfo = log.contains('[*]');

            Color textColor = Colors.greenAccent;
            if (isError) textColor = Colors.redAccent;
            if (isInfo) textColor = Colors.cyanAccent;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(
                log,
                style: TextStyle(
                  color: textColor,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  shadows: [Shadow(color: textColor, blurRadius: 2)],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
