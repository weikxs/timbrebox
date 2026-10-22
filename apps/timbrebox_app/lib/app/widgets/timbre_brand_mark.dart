import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/timbre_colors.dart';

/// The TimbreBox mark from the reviewed HTML: a note held in a record, with
/// two source-signal arcs.  It deliberately avoids a generic Material icon.
class TimbreBrandMark extends StatelessWidget {
  const TimbreBrandMark({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'TimbreBox',
    image: true,
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _TimbreBrandMarkPainter()),
      ),
    ),
  );
}

class _TimbreBrandMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final record = Rect.fromCircle(center: center, radius: radius * .72);

    canvas.drawCircle(
      center,
      radius * .96,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .075
        ..color = TimbreColors.gold.withValues(alpha: .58),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 1.09),
      math.pi * .52,
      math.pi * .96,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .06
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xff9ac0c9).withValues(alpha: .34),
    );
    canvas.drawCircle(
      center,
      radius * .72,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color(0xfffff9ec),
            TimbreColors.gold,
            Color(0xff25201b),
            Color(0xff25201b),
          ],
          stops: [.0, .16, .18, 1],
        ).createShader(record),
    );
    canvas.drawCircle(
      center,
      radius * .31,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .14
        ..color = TimbreColors.gold,
    );
    canvas.drawCircle(
      center,
      radius * .09,
      Paint()..color = const Color(0xfffff9ec),
    );

    final note = TextPainter(
      text: TextSpan(
        text: '♪',
        style: TextStyle(
          color: const Color(0xfffff8eb),
          fontFamily: 'Georgia',
          fontSize: radius * 1.13,
          height: 1,
          shadows: const [Shadow(color: Color(0x66000000), blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    note.paint(
      canvas,
      center -
          Offset(note.width / 2 - radius * .06, note.height / 2 + radius * .02),
    );
  }

  @override
  bool shouldRepaint(covariant _TimbreBrandMarkPainter oldDelegate) => false;
}
