import 'package:flutter/material.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:voxa/colors/colors.dart';
import 'package:voxa/services/api_client.dart';
import 'package:voxa/screens/homescreen.dart';
import 'package:voxa/screens/loginscreen.dart';
import 'package:voxa/screens/registerscreen.dart';

class AuthFormScreen extends StatefulWidget {
  const AuthFormScreen({super.key, required this.isRegister});

  final bool isRegister;

  @override
  State<AuthFormScreen> createState() => _AuthFormScreenState();
}

class _AuthFormScreenState extends State<AuthFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  String countryCode = '+1';
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _phoneFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool _isValidPhone(String phone) {
    return RegExp(r'^[0-9]{6,15}$').hasMatch(phone);
  }

  bool _isValidPassword(String password) {
    return password.length >= 6;
  }

  bool get _isRegister => widget.isRegister;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppColor.backgroundGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            child: SizedBox(
              height:
                  MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),

                      // Logo
                      Image.asset('assets/voxa.png', height: 90),

                      const SizedBox(height: 30),

                      Text(
                        _isRegister ? 'Create account' : 'Login',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color:  Color(0xFF17251F),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        _isRegister
                            ? 'Create an account with your phone number'
                            : 'Login with your phone number',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF56645C),
                          fontSize: 13,
                        ),
                      ),

                      const SizedBox(height: 30),

                      if (_isRegister) ...[
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            final name = value?.trim() ?? '';
                            if (name.isEmpty) return 'Name is required';
                            if (name.length > 80) return 'Name is too long';
                            return null;
                          },
                          decoration: _inputDecoration(
                            hint: 'Name',
                            icon: Icons.person,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // PHONE FIELD WITH COUNTRY CODE PICKER
                      Row(
                        children: [
                          Container(
                            height: 56,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F4F1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: CountryCodePicker(
                              initialSelection: 'US',
                              favorite: const ['+880', 'BD', '+1', 'US'],
                              onChanged: (code) {
                                countryCode = code.dialCode ?? '+1';
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              focusNode: _phoneFocus,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  _passwordFocus.requestFocus(),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Phone number required';
                                }
                                if (!_isValidPhone(value)) {
                                  return 'Invalid phone number';
                                }
                                return null;
                              },
                              decoration: _inputDecoration(
                                hint: 'Phone number',
                                icon: Icons.phone,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // PASSWORD FIELD
                      TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password is required';
                          }
                          if (!_isValidPassword(value)) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                        decoration: _inputDecoration(
                          hint: 'Password',
                          icon: Icons.lock,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 30),

                      // LOGIN BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF168A62),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isRegister ? 'Create account' : 'Continue',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _isRegister
                                      ? const LoginScreen()
                                      : const RegisterScreen(),
                                ),
                              ),
                        child: Text(
                          _isRegister
                              ? 'Already have an account? Login'
                              : 'New to Voxa? Create an account',
                          style: const TextStyle(
                            color: Color(0xFF168A62),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),

                      const Text(
                        'By continuing you agree to our Terms & Privacy Policy',
                        textAlign: TextAlign.center,
                        style:  TextStyle(
                          color: Color(0xFF5F6D65),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF0F4F1),
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      errorStyle: const TextStyle(
        color: Color(0xFFB42318),
        fontWeight: FontWeight.w500,
        fontSize: 11,
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = '$countryCode${_phoneController.text.trim()}';
    setState(() => _isLoading = true);
    try {
      if (_isRegister) {
        await ApiClient.instance.register(
          name: _nameController.text.trim(),
          phone: phone,
          password: _passwordController.text,
        );
      } else {
        await ApiClient.instance.login(
          phone: phone,
          password: _passwordController.text,
        );
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) {
        _showError('Could not connect to the server. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
