import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ui_p2p_provider.dart';
import 'sync_bottom_sheet.dart';

class MeshStatusChip extends ConsumerStatefulWidget {
  const MeshStatusChip({super.key});

  @override
  ConsumerState<MeshStatusChip> createState() => _MeshStatusChipState();
}

class _MeshStatusChipState extends ConsumerState<MeshStatusChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.2,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p2pState = ref.watch(uiP2pServiceProvider);
    final isConnected =
        (p2pState.isHosting && p2pState.hostState?.isActive == true) ||
        p2pState.clientState?.isActive == true;
    final isSyncing = p2pState.isSyncing || p2pState.isConnecting;

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const SyncBottomSheet(),
        );
      },
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final glowColor = isConnected ? Colors.green : Colors.orange;
          
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isConnected
                  ? Colors.green.shade600
                  : (p2pState.isAutoSyncing
                        ? Colors.orange.shade600
                        : Theme.of(context).colorScheme.surfaceContainerHighest),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isConnected || p2pState.isAutoSyncing
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
              ),
              boxShadow: isSyncing
                  ? [
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.6 * _animation.value),
                        blurRadius: 12 * _animation.value,
                        spreadRadius: 2 * _animation.value,
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSyncing)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      value: p2pState.syncProgress,
                      strokeWidth: 2,
                      color: isConnected || p2pState.isAutoSyncing
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Icon(
                    isConnected ? Icons.hub : Icons.hub_outlined,
                    size: 16,
                    color: isConnected || p2pState.isAutoSyncing
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isSyncing
                        ? (p2pState.syncProgress != null
                              ? 'SYNCING (${(p2pState.syncProgress! * 100).toInt()}%${p2pState.syncEstimatedSeconds != null ? ' - ${p2pState.syncEstimatedSeconds}s' : ''})'
                              : 'SYNCING')
                        : isConnected
                        ? (p2pState.hostState?.isActive == true
                              ? (p2pState.connectedClients.isEmpty &&
                                        p2pState.isAutoSyncing
                                    ? 'BROADCASTING'
                                    : 'HOST (${p2pState.connectedClients.length})')
                              : 'CONNECTED')
                        : (p2pState.isAutoSyncing
                              ? (p2pState.isScanning ? 'SCANNING' : 'STARTING...')
                              : 'OFFLINE'),
                    style: TextStyle(
                      color: isConnected || p2pState.isAutoSyncing
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
