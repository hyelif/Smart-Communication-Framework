import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/app_theme.dart';
import '../../widgets/custom_ui.dart';
import 'auth_controller.dart';

/// Login screen shown when the user is not authenticated.
///
/// Also supports account creation via the "Create Account" link.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;
  bool _isRegistering = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final error = await ref.read(authControllerProvider.notifier).login(
          _usernameController.text.trim(),
          _passwordController.text,
        );

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error != null) _error = error;
    });
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    if (_passwordController.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final error = await ref.read(authControllerProvider.notifier).register(
          _usernameController.text.trim(),
          _passwordController.text,
        );

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error != null) _error = error;
    });
  }

  void _toggleMode() {
    setState(() {
      _isRegistering = !_isRegistering;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StitchScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo / branding
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: AppTheme.ctaGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppTheme.cyanGlowShadow,
                  ),
                  child: const Icon(
                    Icons.memory_rounded,
                    color: Colors.black,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'SmartPonic',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isRegistering
                      ? 'Create a new account'
                      : 'Sign in to manage your devices',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: StitchColors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 40),

                // Error banner
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: StitchColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: StitchColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: StitchColors.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: StitchColors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Username
                TextFormField(
                  controller: _usernameController,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter your username';
                    if (v.trim().length < 3) return 'Username must be at least 3 characters';
                    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v.trim())) {
                      return 'Username can only contain letters, numbers, and underscores';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Password
                TextFormField(
                  controller: _passwordController,
                  enabled: !_busy,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  textInputAction:
                      _isRegistering ? TextInputAction.next : TextInputAction.done,
                  onFieldSubmitted: (_) =>
                      _isRegistering ? null : _handleLogin(),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your password' : null,
                ),

                // Confirm password (only for registration)
                if (_isRegistering) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmController,
                    enabled: !_busy,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleRegister(),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Confirm your password';
                      if (v != _passwordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                ],

                const SizedBox(height: 24),

                // Action button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: StitchPrimaryButton(
                    onPressed: _busy
                        ? null
                        : (_isRegistering ? _handleRegister : _handleLogin),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            _isRegistering ? 'CREATE ACCOUNT' : 'SIGN IN',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // Toggle login/register
                TextButton(
                  onPressed: _busy ? null : _toggleMode,
                  child: Text(
                    _isRegistering
                        ? 'Already have an account? Sign in'
                        : "Don't have an account? Create one",
                    style: TextStyle(
                      color: StitchColors.primaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
