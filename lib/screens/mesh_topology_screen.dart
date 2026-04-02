import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/local_user_provider.dart';
import '../providers/ui_p2p_provider.dart';

enum NodeType { me, host, connectedClient, discovered }

class MeshNode {
  final String id;
  final String label;
  final NodeType type;
  Offset position;

  MeshNode({
    required this.id,
    required this.label,
    required this.type,
    this.position = Offset.zero,
  });
}

class MeshEdge {
  final MeshNode source;
  final MeshNode target;
  final bool isConnected;

  MeshEdge(this.source, this.target, this.isConnected);
}

class MeshTopologyScreen extends ConsumerStatefulWidget {
  const MeshTopologyScreen({super.key});

  @override
  ConsumerState<MeshTopologyScreen> createState() => _MeshTopologyScreenState();
}

class _MeshTopologyScreenState extends ConsumerState<MeshTopologyScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p2pState = ref.watch(uiP2pServiceProvider);
    final localUser = ref.watch(localUserControllerProvider).value;
    final myName = localUser?.name ?? 'Me';

    List<MeshNode> nodes = [];
    List<MeshEdge> edges = [];

    final meNode = MeshNode(
      id: 'me',
      label: '$myName (You)',
      type: NodeType.me,
    );
    nodes.add(meNode);

    MeshNode centerNode = meNode;
    List<MeshNode> orbit1 = [];
    List<MeshNode> orbit2 = [];

    if (p2pState.isHosting) {
      for (var client in p2pState.connectedClients) {
        final n = MeshNode(
          id: client.id,
          label: client.username,
          type: NodeType.connectedClient,
        );
        nodes.add(n);
        orbit1.add(n);
        edges.add(MeshEdge(meNode, n, true));
      }
    } else if (p2pState.clientState?.isActive == true) {
      final hostNode = MeshNode(
        id: 'host',
        label: p2pState.clientState!.hostSsid ?? 'Host',
        type: NodeType.host,
      );
      nodes.add(hostNode);
      centerNode = hostNode;
      orbit1.add(meNode);
      edges.add(MeshEdge(meNode, hostNode, true));

      for (var client in p2pState.connectedClients) {
        if (client.id != 'me') {
          final n = MeshNode(
            id: client.id,
            label: client.username,
            type: NodeType.connectedClient,
          );
          nodes.add(n);
          orbit1.add(n);
          edges.add(MeshEdge(hostNode, n, true));
        }
      }
    }

    for (var device in p2pState.discoveredDevices) {
      final n = MeshNode(
        id: device.deviceAddress,
        label: device.deviceName,
        type: NodeType.discovered,
      );
      nodes.add(n);
      orbit2.add(n);
      edges.add(MeshEdge(meNode, n, false));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        title: const Text(
          'Mesh Topology',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0B0F19),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                _layoutNodes(size, centerNode, orbit1, orbit2);

                return InteractiveViewer(
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  minScale: 0.1,
                  maxScale: 4.0,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: TopologyPainter(
                            nodes: nodes,
                            edges: edges,
                            pulseValue: _pulseController.value,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          _buildLegend(),
        ],
      ),
    );
  }

  void _layoutNodes(
    Size size,
    MeshNode centerNode,
    List<MeshNode> orbit1,
    List<MeshNode> orbit2,
  ) {
    final center = Offset(size.width / 2, size.height / 2);
    centerNode.position = center;

    final orbit1Radius = 130.0;
    for (int i = 0; i < orbit1.length; i++) {
      if (orbit1[i] == centerNode) continue;
      final angle = (2 * pi / orbit1.length) * i;
      orbit1[i].position = center +
          Offset(cos(angle) * orbit1Radius, sin(angle) * orbit1Radius);
    }

    final orbit2Radius = 240.0;
    for (int i = 0; i < orbit2.length; i++) {
      final angle = (2 * pi / orbit2.length) * i;
      orbit2[i].position = center +
          Offset(cos(angle) * orbit2Radius, sin(angle) * orbit2Radius);
    }
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151A28),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _legendItem(Colors.blue, 'You'),
            _legendItem(Colors.green, 'Host'),
            _legendItem(Colors.teal, 'Connected Peer'),
            _legendItem(Colors.orange, 'Discovered (BLE)'),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class TopologyPainter extends CustomPainter {
  final List<MeshNode> nodes;
  final List<MeshEdge> edges;
  final double pulseValue;

  TopologyPainter({
    required this.nodes,
    required this.edges,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final edgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final dashedEdgePaint = Paint()
      ..color = Colors.orange.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw edges
    for (var edge in edges) {
      if (edge.isConnected) {
        canvas.drawLine(edge.source.position, edge.target.position, edgePaint);
      } else {
        _drawDashedLine(
          canvas,
          edge.source.position,
          edge.target.position,
          dashedEdgePaint,
        );
      }
    }

    // Draw nodes
    for (var node in nodes) {
      Color nodeColor;
      IconData iconData;

      switch (node.type) {
        case NodeType.me:
          nodeColor = Colors.blue;
          iconData = Icons.person;
          break;
        case NodeType.host:
          nodeColor = Colors.green;
          iconData = Icons.router;
          break;
        case NodeType.connectedClient:
          nodeColor = Colors.teal;
          iconData = Icons.smartphone;
          break;
        case NodeType.discovered:
          nodeColor = Colors.orange;
          iconData = Icons.bluetooth;
          break;
      }

      // Draw pulse for active nodes
      if (node.type == NodeType.me || node.type == NodeType.host) {
        final pulsePaint = Paint()
          ..color = nodeColor.withValues(alpha: 0.3 * (1 - pulseValue))
          ..style = PaintingStyle.fill;
        canvas.drawCircle(node.position, 24 + (15 * pulseValue), pulsePaint);
      }

      // Draw node circle
      final nodePaint = Paint()
        ..color = nodeColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(node.position, 20, nodePaint);

      // Draw border
      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(node.position, 20, borderPaint);

      // Draw Icon
      TextPainter iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(iconData.codePoint),
          style: TextStyle(
            fontSize: 20,
            fontFamily: iconData.fontFamily,
            package: iconData.fontPackage,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      iconPainter.layout();
      iconPainter.paint(
        canvas,
        node.position -
            Offset(iconPainter.width / 2, iconPainter.height / 2),
      );

      // Draw Label
      TextPainter labelPainter = TextPainter(
        text: TextSpan(
          text: node.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      labelPainter.layout(maxWidth: 100);
      labelPainter.paint(
        canvas,
        node.position + Offset(-labelPainter.width / 2, 26),
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const int dashWidth = 6;
    const int dashSpace = 6;
    double distance = (p2 - p1).distance;
    if (distance == 0) return;
    double dx = (p2.dx - p1.dx) / distance;
    double dy = (p2.dy - p1.dy) / distance;
    double startX = p1.dx;
    double startY = p1.dy;

    while (distance >= 0) {
      canvas.drawLine(
        Offset(startX, startY),
        Offset(startX + dx * dashWidth, startY + dy * dashWidth),
        paint,
      );
      startX += dx * (dashWidth + dashSpace);
      startY += dy * (dashWidth + dashSpace);
      distance -= (dashWidth + dashSpace);
    }
  }

  @override
  bool shouldRepaint(covariant TopologyPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
        oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges;
  }
}
