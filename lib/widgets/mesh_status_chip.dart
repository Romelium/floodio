import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ui_p2p_provider.dart';
import 'sync_bottom_sheet.dart';

class MeshStatusChip extends ConsumerWidget {
  const MeshStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p2pState = ref.watch(uiP2pServiceProvider);
    final isConnected =
        p2pState.hostState?.isActive == true ||
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
      child: Container(
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
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSyncing)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isConnected || p2pState.isAutoSyncing ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              Icon(
                isConnected ? Icons.hub : Icons.hub_outlined,
                size: 16,
                color: isConnected || p2pState.isAutoSyncing ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            const SizedBox(width: 6),
            Text(
              isSyncing
                  ? 'SYNCING'
                  : isConnected
                      ? (p2pState.hostState?.isActive == true ? 'HOST (${p2pState.connectedClients.length})' : 'CONNECTED')
                      : (p2pState.isAutoSyncing ? 'SEARCHING' : 'OFFLINE'),
              style: TextStyle(
                color: isConnected || p2pState.isAutoSyncing ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
