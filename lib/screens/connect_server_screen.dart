import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/jellyfin_config.dart';
import '../providers/connection_notifier.dart';
import '../services/auth_service.dart';

const _kAccent  = Color(0xFF7C3AED);
const _kBorder  = Color(0x22FFFFFF);
const _kText    = Colors.white;
const _kTextDim = Color(0xFFAAAAAA);
const _kError   = Color(0xFFFF5252);

class ConnectServerScreen extends StatefulWidget {
  const ConnectServerScreen({super.key});

  @override
  State<ConnectServerScreen> createState() => _ConnectServerScreenState();
}

class _ConnectServerScreenState extends State<ConnectServerScreen> {
  final _serverCtrl   = TextEditingController();
  final _userCtrl     = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _vibePassCtrl = TextEditingController();

  bool    _obscure     = true;
  bool    _vibeObscure = true;
  bool    _loading     = false;
  String? _error;

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _vibePassCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url   = _serverCtrl.text.trim().replaceAll(RegExp(r'/$'), '');
    final user  = _userCtrl.text.trim();
    final pass  = _passCtrl.text;
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final vPass = _vibePassCtrl.text;

    if (url.isEmpty)   { setState(() => _error = 'Enter your server URL.'); return; }
    if (user.isEmpty)  { setState(() => _error = 'Enter your Jellyfin username.'); return; }
    if (pass.isEmpty)  { setState(() => _error = 'Enter your Jellyfin password.'); return; }
    if (name.isEmpty)  { setState(() => _error = 'Enter your name.'); return; }
    if (email.isEmpty) { setState(() => _error = 'Enter an email for your ViBE account.'); return; }
    if (vPass.isEmpty) { setState(() => _error = 'Enter a password for your ViBE account.'); return; }

    setState(() { _loading = true; _error = null; });

    try {
      // 1. Validate Jellyfin
      final creds = await AuthService.authenticateJellyfin(
        serverUrl: url, username: user, password: pass,
      );
      if (creds == null) {
        if (mounted) setState(() { _loading = false; _error = 'Could not connect. Check your URL and credentials.'; });
        return;
      }
      // 2. Create ViBE account (stores Jellyfin creds in Supabase metadata
      //    so Sign In can restore them without re-entering Jellyfin credentials)
      final res = await AuthService.signUpWithServer(
        email: email, password: vPass, displayName: name,
        serverUrl: url, jellyfinToken: creds.token, jellyfinUserId: creds.userId,
      );
      if (res.user == null) {
        if (mounted) setState(() { _loading = false; _error = 'Could not create ViBE account. Try a different email.'; });
        return;
      }
      // 3. Save credentials to Hive, mark account as set up, and exit demo mode
      await JellyfinConfig.save(
        serverUrl: url, apiKey: creds.token, userId: creds.userId,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('vibe_has_setup', true);
      connectionNotifier.connect();
    } on AuthException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    } on Exception catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e.toString().replaceAll(RegExp(r'^Exception: '), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 24, 20, bottomPad + 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect Your Server',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _kText),
          ),
          const SizedBox(height: 6),
          const Text(
            'Connect to your own Jellyfin server to access your full library.',
            style: TextStyle(fontSize: 13, color: _kTextDim),
          ),
          const SizedBox(height: 28),

          _Field(
            controller: _serverCtrl,
            label: 'Server URL',
            hint: 'https://jellyfin.example.com',
            keyboard: TextInputType.url,
          ),
          const SizedBox(height: 14),
          _Field(controller: _userCtrl, label: 'Jellyfin Username'),
          const SizedBox(height: 14),
          _Field(
            controller: _passCtrl,
            label: 'Jellyfin Password',
            obscure: _obscure,
            suffix: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: _kTextDim, size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: 22),
          _SectionLabel(icon: Icons.person_outline, label: 'Create your ViBE account'),
          const SizedBox(height: 12),
          _Field(controller: _nameCtrl, label: 'Name'),
          const SizedBox(height: 14),
          _Field(
            controller: _emailCtrl,
            label: 'Email',
            keyboard: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          _Field(
            controller: _vibePassCtrl,
            label: 'Password',
            obscure: _vibeObscure,
            suffix: IconButton(
              icon: Icon(
                _vibeObscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: _kTextDim, size: 20,
              ),
              onPressed: () => setState(() => _vibeObscure = !_vibeObscure),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color:        _kError.withAlpha(0x22),
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: _kError.withAlpha(0x66)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: _kError, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: _kError, fontSize: 13))),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          GestureDetector(
            onTap: _loading ? null : _connect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF9B59EE), Color(0xFF6D28D9)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: _kAccent.withAlpha(0x55), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              alignment: Alignment.center,
              child: _loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Create Account', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: connectionNotifier.disconnect,
            child: const Center(
              child: Text(
                'Exit Demo',
                style: TextStyle(color: _kTextDim, fontSize: 13, decoration: TextDecoration.underline, decorationColor: _kTextDim),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});
  final IconData icon;
  final String   label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFAB82F0), size: 14),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Color(0xFFAB82F0), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: const Color(0x22FFFFFF))),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboard = TextInputType.text,
    this.obscure  = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String    label;
  final String?   hint;
  final TextInputType keyboard;
  final bool      obscure;
  final Widget?   suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:         controller,
      obscureText:        obscure,
      keyboardType:       keyboard,
      keyboardAppearance: Brightness.dark,
      autocorrect:        false,
      enableSuggestions:  !obscure,
      style: const TextStyle(color: _kText, fontSize: 15),
      decoration: InputDecoration(
        labelText:     label,
        hintText:      hint,
        hintStyle:     const TextStyle(color: Color(0xFF555566)),
        labelStyle:    const TextStyle(color: _kTextDim, fontSize: 13),
        filled:        true,
        fillColor:     const Color(0xFF0E0E1C),
        suffixIcon:    suffix,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   const BorderSide(color: _kAccent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
