import 'package:flutter/material.dart';
import 'typography.dart';

class NumericText extends StatelessWidget {
  const NumericText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final base =
        (style ?? Theme.of(context).textTheme.bodyMedium) ?? const TextStyle();
    return Text(
      data,
      style: base.merge(numericTextStyle),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
