import 'package:flutter/material.dart';

import '../shell/widgets/shell_header.dart';
import 'discovery_content.dart';

class DiscoveryPage extends StatelessWidget {
  const DiscoveryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const ShellSectionHeader(title: '发现', compact: true, fontSize: 22),
          const Expanded(child: DiscoveryContent()),
        ],
      ),
    );
  }
}
