import 'package:flutter/material.dart';

/// Redesigned brand mark: a gradient "play" tile + a gradient "NoonFlix"
/// wordmark. Scales with [size] (the height of the tile). Reused on the
/// splash and the home top bar.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40, this.showWordmark = true});

  final double size;
  final bool showWordmark;

  static const _gradient = LinearGradient(
    colors: [Color(0xFFB026FF), Color(0xFFE50914)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: _gradient,
            borderRadius: BorderRadius.circular(size * 0.28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB026FF).withValues(alpha: 0.45),
                blurRadius: size * 0.4,
                offset: Offset(0, size * 0.12),
              ),
            ],
          ),
          child: Icon(Icons.play_arrow_rounded,
              color: Colors.white, size: size * 0.68),
        ),
        if (showWordmark) ...[
          SizedBox(width: size * 0.3),
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              colors: [Colors.white, Color(0xFFE6D5FF)],
            ).createShader(rect),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Noon'),
                  TextSpan(
                    text: 'Flix',
                    style: TextStyle(
                      foreground: Paint()
                        ..shader = _gradient.createShader(
                            Rect.fromLTWH(0, 0, size * 3, size)),
                    ),
                  ),
                ],
                style: TextStyle(
                  fontSize: size * 0.62,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
