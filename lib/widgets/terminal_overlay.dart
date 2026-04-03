import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/terminal_log_provider.dart';
import '../providers/ui_state_provider.dart';
import '../screens/terminal_screen.dart';

class TerminalOverlay extends ConsumerStatefulWidget {
  const TerminalOverlay({super.key});

  @override
  ConsumerState<TerminalOverlay> createState() => _TerminalOverlayState();
}

class _TerminalOverlayState extends ConsumerState<TerminalOverlay> {
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(terminalLogControllerProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    return Container(
      height: 250,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        border: const Border(top: BorderSide(color: Colors.greenAccent, width: 2)),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SYSTEM DIAGNOSTICS',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.greenAccent, blurRadius: 4)],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_sweep, color: Colors.greenAccent, size: 18),
                    onPressed: () => ref.read(terminalLogControllerProvider.notifier).clear(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.open_in_full, color: Colors.greenAccent, size: 18),
                    onPressed: () {
                      ref.read(showTerminalOverlayProvider.notifier).toggle();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TerminalScreen()),
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.greenAccent, size: 18),
                    onPressed: () => ref.read(showTerminalOverlayProvider.notifier).toggle(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              )
            ],
          ),
          const Divider(color: Colors.greenAccent),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                final isError = log.contains('[-]');
                final isInfo = log.contains('[*]');
                
                Color textColor = Colors.greenAccent;
                if (isError) textColor = Colors.redAccent;
                if (isInfo) textColor = Colors.cyanAccent;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.0),
                  child: Text(
                    log,
                    style: TextStyle(
                      color: textColor,
                      fontFamily: 'monospace',
                      fontSize: 10,
                      shadows: [Shadow(color: textColor, blurRadius: 2)],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
