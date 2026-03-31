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
              ? Colors.green.shade700
              : (p2pState.isAutoSyncing
                    ? Colors.orange.shade700
                    : Colors.grey.shade700),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSyncing)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                isConnected ? Icons.hub : Icons.hub_outlined,
                size: 14,
                color: Colors.white,
              ),
            const SizedBox(width: 6),
            Text(
              isConnected
                  ? 'MESH ACTIVE'
                  : (p2pState.isAutoSyncing ? 'SEARCHING' : 'OFFLINE'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
