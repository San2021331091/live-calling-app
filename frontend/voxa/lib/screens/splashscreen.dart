import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:voxa/colors/colors.dart';
import 'package:voxa/screens/homescreen.dart';
import 'package:voxa/screens/loginscreen.dart';
import 'package:voxa/services/api_client.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  String? _error;
  bool _loading = false;
  bool _navigating = false;

  late final AnimationController _entranceController;
  late final AnimationController _pulseController;
  late final AnimationController _particleController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<Offset> _logoSlide;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleSlide;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _logoScale = Tween<double>(
      begin: 0.45,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.elasticOut,
      ),
    );

    _logoOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.55, curve: Curves.easeIn),
    );

    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _titleOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.35, 0.8, curve: Curves.easeIn),
    );

    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _entranceController.forward();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    if (_loading || _navigating) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    // Keep the splash visible for at least 3 seconds.
    final minimumDuration = Future<void>.delayed(
      const Duration(seconds: 3),
    );

    try {
      final hasSession =
          await ApiClient.instance.hasStoredSession();

      if (hasSession) {
        await ApiClient.instance.loadCurrentUser();
      }

      await minimumDuration;

      if (!mounted) return;

      _open(
        hasSession ? const HomeScreen() : const LoginScreen(),
      );
    } on ApiException catch (error) {
      await minimumDuration;

      if (!mounted) return;

      if (error.statusCode == 401) {
        try {
          await ApiClient.instance.signOut();
          if (mounted) _open(const LoginScreen());
        } on ApiException catch (signOutError) {
          if (mounted) {
            setState(() => _error = signOutError.message);
          }
        }
      } else {
        setState(() => _error = error.message);
      }
    } catch (_) {
      await minimumDuration;

      if (mounted) {
        setState(
          () => _error =
              'Could not restore your session. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _open(Widget screen) {
    if (!mounted || _navigating) return;

    _navigating = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, secondaryAnimation) => screen,
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (
          context,
          animation,
          secondaryAnimation,
          child,
        ) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppColor.brandGradient,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Soft ambient glow.
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final glow = 0.12 +
                    (_pulseController.value * 0.12);

                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.15),
                      radius: 0.85 +
                          (_pulseController.value * 0.15),
                      colors: [
                        Colors.white.withValues(alpha: glow),
                        Colors.transparent,
                      ],
                    ),
                  ),
                );
              },
            ),

            // Floating decorative particles.
            AnimatedBuilder(
              animation: _particleController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _ParticlePainter(
                    progress: _particleController.value,
                  ),
                );
              },
            ),

            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated logo with pulsing glow.
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _entranceController,
                        _pulseController,
                      ]),
                      builder: (context, child) {
                        final glowSize =
                            18 + (_pulseController.value * 18);

                        return FadeTransition(
                          opacity: _logoOpacity,
                          child: SlideTransition(
                            position: _logoSlide,
                            child: Transform.scale(
                              scale: _logoScale.value,
                              child: Container(
                                width: 124,
                                height: 124,
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(
                                      alpha: 0.35,
                                    ),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withValues(
                                        alpha: 0.14 +
                                            (_pulseController.value *
                                                0.12),
                                      ),
                                      blurRadius: glowSize,
                                      spreadRadius:
                                          _pulseController.value * 3,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/voxa.png',
                                    width: 114,
                                    height: 114,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 28),

                    // Animated brand name.
                    FadeTransition(
                      opacity: _titleOpacity,
                      child: SlideTransition(
                        position: _titleSlide,
                        child: const Text(
                          'Voxa',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                            shadows: [
                              Shadow(
                                color: Color(0x55000000),
                                blurRadius: 18,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    FadeTransition(
                      opacity: _titleOpacity,
                      child: Text(
                        'CONNECT. SHARE. LIVE.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                        ),
                      ),
                    ),

                    const SizedBox(height: 38),

                    if (_error == null) ...[
                      SizedBox(
                        width: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: const LinearProgressIndicator(
                            minHeight: 3,
                            backgroundColor: Color(0x33FFFFFF),
                            valueColor:
                                AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Getting things ready...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ] else ...[
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed:
                            _loading ? null : _restoreSession,
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.black87,
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Small footer.
            Positioned(
              left: 0,
              right: 0,
              bottom: 36,
              child: FadeTransition(
                opacity: _titleOpacity,
                child: Text(
                  'MADE FOR YOUR MOMENTS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 9,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 30; i++) {
      final x = ((i * 73.7) % size.width);
      final initialY = ((i * 97.3) % size.height);
      final y = (initialY -
              progress * (size.height * 0.35) +
              size.height) %
          size.height;

      final radius = 1.0 + ((i % 3) * 0.7);
      final opacity = 0.12 + ((i % 4) * 0.045);

      paint.color = Colors.white.withValues(alpha: opacity);

      canvas.drawCircle(
        Offset(
          x + math.sin(progress * 2 * math.pi + i) * 8,
          y,
        ),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
