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

class _SplashScreenState extends State<SplashScreen> {
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hasSession = await ApiClient.instance.hasStoredSession();
      if (hasSession) await ApiClient.instance.loadCurrentUser();
      if (!mounted) return;
      _open(hasSession ? const HomeScreen() : const LoginScreen());
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        try {
          await ApiClient.instance.signOut();
        } on ApiException catch (signOutError) {
          if (mounted) setState(() => _error = signOutError.message);
          return;
        }
        if (mounted) _open(const LoginScreen());
      } else if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not restore your session. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(Widget screen) {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: AppColor.brandGradient),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: Image.asset('assets/voxa.png', width: 96, height: 96),
              ),
              const SizedBox(height: 20),
              const Text(
                'Voxa',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              if (_error == null)
                const CircularProgressIndicator(color: Colors.white)
              else ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _restoreSession,
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
