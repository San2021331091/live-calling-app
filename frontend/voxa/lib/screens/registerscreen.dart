import 'package:flutter/material.dart';
import 'package:voxa/screens/authformscreen.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const AuthFormScreen(isRegister: true);
}
