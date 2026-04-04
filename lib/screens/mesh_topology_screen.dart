import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/battery_provider.dart';
import '../providers/local_user_provider.dart';
import '../providers/ui_p2p_provider.dart';

bool isMeshTopologyOpen = false;

enum NodeType { me, host, connectedClient, discovered }

class MeshNode {
  final String id;
  String label;
  NodeType type;
  Offset position;
  Offset targetPosition;

  MeshNode({
    required this.id,
    required this.label,
    required this.type,
    this.position = Offset.zero,
    this.targetPosition = Offset.zero,
  });
}

class MeshEdge {
  final MeshNode source;
  final MeshNode target;
  final bool isConnected;
  final bool isSyncing;
  final bool flowForward;
  final bool flowBackward;

  MeshEdge(
    this.source,
    this.target,
    this.isConnected, {
    this.isSyncing = false,
    this.flowForward = false,
    this.flowBackward = false,
  });
}

class MeshTopologyScreen extends ConsumerStatefulWidget {
  const MeshTopologyScreen({super.key});

  @override
  ConsumerState<MeshTopologyScreen> createState() => _MeshTopologyScreenState();
}

class _MeshTopologyScreenState extends ConsumerState<MeshTopologyScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _flowController;

  List<MeshNode> _nodes = [];
  List<MeshEdge> _edges = [];

  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    isMeshTopologyOpen = true;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    isMeshTopologyOpen = false;
    _pulseController.dispose();
    _flowController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _buildGraph(Size size) {
    final p2pState = ref.watch(uiP2pServiceProvider);
    final localUser = ref.watch(localUserControllerProvider).value;
    final myName = localUser?.name ?? 'Me';

    bool isSyncing = p2pState.isSyncing || p2pState.isConnecting;
    bool flowToMe = false;
    bool flowFromMe = false;

    if (isSyncing) {
      final msg = p2pState.syncMessage?.toLowerCase() ?? '';
      if (msg.contains('downloading') ||
          msg.contains('receiving') ||
          msg.contains('unpacking')) {
        flowToMe = true;
      } else if (msg.contains('sending') ||
          msg.contains('broadcasting') ||
          msg.contains('forwarding') ||
          msg.contains('packing')) {
        flowFromMe = true;
      } else {
        flowToMe = true;
        flowFromMe = true;
      }
    }

    List<MeshNode> newNodes = [];
    List<MeshEdge> newEdges = [];

    final meNode = MeshNode(
      id: 'me',
      label: '$myName (You)',
      type: p2pState.isHosting ? NodeType.host : NodeType.me,
    );
    newNodes.add(meNode);

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
        newNodes.add(n);
        orbit1.add(n);
        newEdges.add(
          MeshEdge(
            meNode,
            n,
            true,
            isSyncing: isSyncing,
            flowForward: flowFromMe,
            flowBackward: flowToMe,
          ),
        );
      }
      for (var device in p2pState.discoveredDevices) {
        final n = MeshNode(
          id: device.deviceAddress,
          label: device.deviceName,
          type: NodeType.discovered,
        );
        newNodes.add(n);
        orbit2.add(n);
        newEdges.add(MeshEdge(meNode, n, false));
      }
    } else if (p2pState.clientState?.isActive == true) {
      final hostNode = MeshNode(
        id: 'host',
        label: p2pState.clientState!.hostSsid ?? 'Host',
        type: NodeType.host,
      );
      newNodes.add(hostNode);
      centerNode = hostNode;

      meNode.type = NodeType.connectedClient; // I am a client
      meNode.label = '$myName (You)';
      orbit1.add(meNode);
      newEdges.add(
        MeshEdge(
          hostNode,
          meNode,
          true,
          isSyncing: isSyncing,
          flowForward: flowToMe,
          flowBackward: flowFromMe,
        ),
      );

      for (var client in p2pState.connectedClients) {
        if (client.id != 'me' && !client.isHost) {
          final n = MeshNode(
            id: client.id,
            label: client.username,
            type: NodeType.connectedClient,
          );
          newNodes.add(n);
          orbit1.add(n);
          newEdges.add(
            MeshEdge(
              hostNode,
              n,
              true,
              isSyncing: isSyncing,
              flowForward: flowToMe,
              flowBackward: flowFromMe,
            ),
          );
        }
      }
      for (var device in p2pState.discoveredDevices) {
        final n = MeshNode(
          id: device.deviceAddress,
          label: device.deviceName,
          type: NodeType.discovered,
        );
        newNodes.add(n);
        orbit2.add(n);
        newEdges.add(MeshEdge(meNode, n, false));
      }
    } else {
      for (var device in p2pState.discoveredDevices) {
        final n = MeshNode(
          id: device.deviceAddress,
          label: device.deviceName,
          type: NodeType.discovered,
        );
        newNodes.add(n);
        orbit1.add(n);
        newEdges.add(MeshEdge(meNode, n, false));
      }
    }

    // Layout
    final center = Offset(size.width / 2, size.height / 2);
    centerNode.targetPosition = center;

    final orbit1Radius = 140.0;
    for (int i = 0; i < orbit1.length; i++) {
      if (orbit1[i] == centerNode) continue;
      final angle = (2 * pi / orbit1.length) * i - pi / 2;
      orbit1[i].targetPosition =
          center + Offset(cos(angle) * orbit1Radius, sin(angle) * orbit1Radius);
    }

    final orbit2Radius = 260.0;
    for (int i = 0; i < orbit2.length; i++) {
      final angle = (2 * pi / orbit2.length) * i - pi / 4;
      orbit2[i].targetPosition =
          center + Offset(cos(angle) * orbit2Radius, sin(angle) * orbit2Radius);
    }

    // Interpolate positions for smooth movement
    for (var node in newNodes) {
      final oldNode = _nodes.where((n) => n.id == node.id).firstOrNull;
      if (oldNode != null) {
        node.position = oldNode.position;
      } else {
        node.position = center; // Spawn from center
      }
    }

    _nodes = newNodes;
    _edges = newEdges;
  }

  void _handleNodeTap(Offset tapPosition) {
    // Convert tap position to scene coordinates
    final scenePoint = _transformationController.toScene(tapPosition);

    for (var node in _nodes) {
      if ((node.targetPosition - scenePoint).distance < 30) {
        HapticFeedback.selectionClick();
        _showNodeDetails(node);
        break;
      }
    }
  }

  void _showNodeDetails(MeshNode node) {
    final p2pState = ref.read(uiP2pServiceProvider);
    final summary = p2pState.lastSyncSummary;
    final msg = p2pState.syncMessage;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151A28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        IconData icon;
        Color color;
        String role;

        switch (node.type) {
          case NodeType.me:
            icon = Icons.person;
            color = Colors.blue;
            role = 'This Device (Local Node)';
            break;
          case NodeType.host:
            icon = Icons.router;
            color = Colors.green;
            role = 'Group Owner (Host)';
            break;
          case NodeType.connectedClient:
            icon = Icons.smartphone;
            color = Colors.teal;
            role = 'Connected Peer';
            break;
          case NodeType.discovered:
            icon = Icons.bluetooth;
            color = Colors.orange;
            role = 'Discovered Device (BLE)';
            break;
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: color.withValues(alpha: 0.2),
                  child: Icon(icon, size: 32, color: color),
                ),
                const SizedBox(height: 16),
                Text(
                  node.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  role,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                if (node.type == NodeType.connectedClient ||
                    node.type == NodeType.host)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.sync, color: color, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Connection Status',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          p2pState.isSyncing
                              ? 'Active Transfer: $msg'
                              : 'Connected (Idle)',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        if (summary != null) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(color: Colors.white12, height: 1),
                          ),
                          Row(
                            children: [
                              Icon(Icons.history, color: color, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Last Exchange',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            summary,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                if (node.type == NodeType.discovered)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      // Connect logic
                      final p2pState = ref.read(uiP2pServiceProvider);
                      final device = p2pState.discoveredDevices.firstWhere(
                        (d) => d.deviceAddress == node.id,
                      );
                      ref
                          .read(uiP2pServiceProvider.notifier)
                          .connectToDevice(device);
                    },
                    icon: const Icon(Icons.link),
                    label: const Text('Connect'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSyncing = ref.watch(
      uiP2pServiceProvider.select((s) => s.isSyncing || s.isConnecting),
    );
    final battery = ref.watch(batteryControllerProvider);
    final isPowerSave = battery.isPowerSaveMode;

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
                _buildGraph(size);

                return GestureDetector(
                  onTapUp: (details) => _handleNodeTap(details.localPosition),
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: 0.1,
                    maxScale: 4.0,
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([
                          _pulseController,
                          _flowController,
                        ]),
                        builder: (context, child) {
                          // Simple lerp for positions
                          for (var node in _nodes) {
                            node.position =
                                Offset.lerp(
                                  node.position,
                                  node.targetPosition,
                                  0.1,
                                ) ??
                                node.targetPosition;
                          }

                          return CustomPaint(
                            painter: TopologyPainter(
                              nodes: _nodes,
                              edges: _edges,
                              pulseValue: isPowerSave
                                  ? 0.0
                                  : _pulseController.value,
                              flowValue: isPowerSave
                                  ? 0.0
                                  : _flowController.value,
                              isSyncing: isSyncing && !isPowerSave,
                            ),
                          );
                        },
                      ),
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
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ],
          ),
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
  final double flowValue;
  final bool isSyncing;

  TopologyPainter({
    required this.nodes,
    required this.edges,
    required this.pulseValue,
    required this.flowValue,
    required this.isSyncing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background grid
    _drawGrid(canvas, size);

    // Draw edges
    for (var edge in edges) {
      if (edge.isConnected) {
        _drawConnectedEdge(canvas, edge);
      } else {
        _drawDashedEdge(canvas, edge.source.position, edge.target.position);
      }
    }

    // Draw nodes
    for (var node in nodes) {
      _drawNode(canvas, node);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1;

    const double step = 40;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawConnectedEdge(Canvas canvas, MeshEdge edge) {
    final p1 = edge.source.position;
    final p2 = edge.target.position;

    final glowPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: edge.isSyncing ? 0.8 : 0.3)
      ..strokeWidth = edge.isSyncing ? 6 : 2
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: edge.isSyncing ? 0.9 : 0.5)
      ..strokeWidth = edge.isSyncing ? 2 : 1
      ..style = PaintingStyle.stroke;

    // Draw curved line
    final path = Path();
    path.moveTo(p1.dx, p1.dy);

    // Add a slight curve
    final midPoint = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
    final normal = Offset(-(p2.dy - p1.dy), p2.dx - p1.dx);
    final distance = (p2 - p1).distance;
    final normalizedNormal = normal / distance;
    final controlPoint = midPoint + normalizedNormal * (distance * 0.15);

    path.quadraticBezierTo(controlPoint.dx, controlPoint.dy, p2.dx, p2.dy);
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, corePaint);

    // Draw flowing particles if syncing
    if (edge.isSyncing) {
      if (edge.flowForward) _drawParticles(canvas, path, true);
      if (edge.flowBackward) _drawParticles(canvas, path, false);
    }
  }

  void _drawParticles(Canvas canvas, Path path, bool forward) {
    final metrics = path.computeMetrics().first;
    final particleGlowPaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final particleCorePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    const int numParticles = 3;
    for (int i = 0; i < numParticles; i++) {
      double offset = (flowValue + (i / numParticles)) % 1.0;
      if (!forward) offset = 1.0 - offset; // Reverse direction

      final tangent = metrics.getTangentForOffset(metrics.length * offset);
      if (tangent != null) {
        canvas.drawCircle(tangent.position, 6, particleGlowPaint);
        canvas.drawCircle(tangent.position, 2, particleCorePaint);
      }
    }
  }

  void _drawDashedEdge(Canvas canvas, Offset p1, Offset p2) {
    final paint = Paint()
      ..color = Colors.orange.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const int dashWidth = 8;
    const int dashSpace = 8;
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

  void _drawNode(Canvas canvas, MeshNode node) {
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
    if (node.type != NodeType.discovered) {
      final pulsePaint = Paint()
        ..color = nodeColor.withValues(alpha: 0.2 * (1 - pulseValue))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(node.position, 28 + (20 * pulseValue), pulsePaint);

      final pulsePaint2 = Paint()
        ..color = nodeColor.withValues(alpha: 0.1 * (1 - pulseValue))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(node.position, 28 + (40 * pulseValue), pulsePaint2);
    }

    // Outer glow
    final glowPaint = Paint()
      ..color = nodeColor.withValues(alpha: 0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawCircle(node.position, 24, glowPaint);

    // Draw node circle (dark center)
    final nodePaint = Paint()
      ..color = const Color(0xFF1A2235)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(node.position, 22, nodePaint);

    // Draw border
    final borderPaint = Paint()
      ..color = nodeColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(node.position, 22, borderPaint);

    // Draw Icon
    TextPainter iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: 22,
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
      node.position - Offset(iconPainter.width / 2, iconPainter.height / 2),
    );

    // Draw Label Background
    TextPainter labelPainter = TextPainter(
      text: TextSpan(
        text: node.label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    labelPainter.layout(maxWidth: 120);

    final labelRect = Rect.fromCenter(
      center: node.position + const Offset(0, 36),
      width: labelPainter.width + 12,
      height: labelPainter.height + 6,
    );

    final labelBgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(12)),
      labelBgPaint,
    );

    // Draw Label
    labelPainter.paint(
      canvas,
      node.position +
          Offset(-labelPainter.width / 2, 36 - labelPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant TopologyPainter oldDelegate) {
    return true; // Always repaint for smooth animation
  }
}
