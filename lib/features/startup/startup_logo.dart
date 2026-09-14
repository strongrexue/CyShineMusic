import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

class StartupLogo extends StatefulWidget {
  const StartupLogo({super.key, this.size = 112});

  final double size;

  @override
  State<StartupLogo> createState() => _StartupLogoState();
}

class _StartupLogoState extends State<StartupLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    duration: const Duration(milliseconds: 1200),
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _entry.forward();
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _entry,
        curve: AppMotion.emphasizedDecelerate,
      ),
      child: Image.asset(
        'logo_fg.png',
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
      ),
    );
  }
}
