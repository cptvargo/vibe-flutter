import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _pwCtrl  = TextEditingController();
  final _pw2Ctrl = TextEditingController();
  bool _loading  = false;
  bool _obscure  = true;
  String? _error;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _pw2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pw  = _pwCtrl.text.trim();
    final pw2 = _pw2Ctrl.text.trim();

    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != pw2) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: pw),
      );
      if (!mounted) return;
      authNotifier.clearPasswordRecovery();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              const Text(
                'Set new\npassword',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a password you\'ll remember.',
                style: TextStyle(color: Colors.white.withAlpha(0x99), fontSize: 15),
              ),
              const SizedBox(height: 40),

              _Field(
                controller: _pwCtrl,
                label: 'New password',
                obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              const SizedBox(height: 16),
              _Field(
                controller: _pw2Ctrl,
                label: 'Confirm password',
                obscure: _obscure,
                onSubmitted: (_) => _save(),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13)),
              ],

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _loading ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save password',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  const _Field({
    required this.controller,
    required this.label,
    required this.obscure,
    this.suffix,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:    controller,
      obscureText:   obscure,
      onSubmitted:   onSubmitted,
      style:         const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText:     label,
        labelStyle:    TextStyle(color: Colors.white.withAlpha(0x99)),
        suffixIcon:    suffix,
        filled:        true,
        fillColor:     Colors.white.withAlpha(0x0F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
        ),
      ),
    );
  }
}
