import 'package:flutter/material.dart';
import 'package:voxa/colors/colors.dart';

class GradientAppBarBackground extends StatelessWidget {
  const GradientAppBarBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: AppColor.brandGradient),
      ),
    );
  }
}
