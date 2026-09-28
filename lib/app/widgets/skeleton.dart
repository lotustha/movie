import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Loading placeholders that sweep with one shared shimmer. Wrap a whole
/// skeleton layout in [Skeleton] (so every bone shines in step) and build it
/// from [Bone]s sized exactly like the content they stand in for.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  // A lift of the page surface, not a grey block: reads as "coming" on the
  // near-black theme without flashing.
  static const Color base = Color(0xFF1B1B23);
  static const Color highlight = Color(0xFF2C2C38);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: Shimmer.fromColors(
          enabled: enabled,
          baseColor: base,
          highlightColor: highlight,
          period: const Duration(milliseconds: 1400),
          child: child,
        ),
      ),
    );
  }
}

/// One placeholder shape. Inside a [Skeleton] its color is replaced by the
/// shimmer; outside one it shows as the flat base color.
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height, this.radius = 6, this.circle = false}) : _padding = 0;

  /// A line of text: [fontSize] tall bone with the text's line box around it.
  const Bone.text({super.key, this.width, double fontSize = 14, double lineHeight = 1.3})
      : height = fontSize,
        radius = 4,
        circle = false,
        _padding = (fontSize * lineHeight - fontSize) / 2;

  const Bone.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = 0,
        circle = true,
        _padding = 0;

  final double? width;
  final double? height;
  final double radius;
  final bool circle;
  final double _padding;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Skeleton.base,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
    return _padding > 0 ? Padding(padding: EdgeInsets.symmetric(vertical: _padding), child: box) : box;
  }
}
