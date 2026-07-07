import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';

// Login screen — three paths:
//   sign_in      → existing users (email + password)
//   join         → friends with an invite code
//   own_server   → public users connecting their own Jellyfin

enum _Mode { signIn, join, ownServer }

// Design constants — intentional branding, not music-content theming
const _kBg          = Color(0xFF080810);
const _kSurface     = Color(0xFF12121E);
const _kBorder      = Color(0x22FFFFFF);
const _kAccent      = Color(0xFF7C3AED);
const _kAccentLight = Color(0xFFAB82F0);
const _kText        = Colors.white;
const _kTextDim     = Color(0xFFAAAAAA);
const _kError       = Color(0xFFFF5252);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  _Mode _mode = _Mode.signIn;

  // Controllers shared across modes — cleared on mode switch
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _codeCtrl     = TextEditingController();
  final _serverCtrl   = TextEditingController();

  bool _loading     = false;
  bool _obscure     = true;
  String? _error;

  // Invite code validation state
  Map<String, dynamic>? _validatedInvite;
  bool _codeChecking = false;
  bool _codeValid    = false;

  late final AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  void _switchMode(_Mode mode) {
    if (_mode == mode) return;
    _fadeCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _error = null;
        _codeValid = false;
        _validatedInvite = null;
        _codeCtrl.clear();
      });
      _fadeCtrl.forward();
    });
  }

  void _setError(String msg) => setState(() { _error = msg; _loading = false; });

  Future<void> _checkCode(String raw) async {
    final code = raw.toUpperCase().trim();
    if (code.length < 4) {
      setState(() { _codeValid = false; _validatedInvite = null; });
      return;
    }
    setState(() => _codeChecking = true);
    try {
      final data = await AuthService.redeemInviteCode(code);
      if (mounted) {
        setState(() {
          _codeChecking  = false;
          _codeValid     = data != null;
          _validatedInvite = data;
          _error = data == null ? 'Invalid or expired invite code.' : null;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _codeChecking = false; _codeValid = false; });
    }
  }

  Future<void> _submit() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final name     = _nameCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _setError('Email and password are required.');
      return;
    }
    if (_mode != _Mode.signIn && name.isEmpty) {
      _setError('Please enter your name.');
      return;
    }
    if (_mode == _Mode.join && !_codeValid) {
      _setError('Please enter a valid invite code first.');
      return;
    }
    if (_mode == _Mode.ownServer && _serverCtrl.text.trim().isEmpty) {
      _setError('Please enter your Jellyfin server URL.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      if (_mode == _Mode.signIn) {
        final res = await AuthService.signIn(email: email, password: password);
        if (res.user == null && mounted) _setError('Sign in failed. Check your credentials.');
      } else if (_mode == _Mode.join) {
        final res = await AuthService.signUpWithInviteCode(
          email:        email,
          password:     password,
          displayName:  name,
          inviteData:   _validatedInvite!,
        );
        if (res.user == null && mounted) _setError('Could not create account. Try again.');
      } else {
        final url = _serverCtrl.text.trim().replaceAll(RegExp(r'/$'), '');
        final res = await AuthService.signUpWithServer(
          email:       email,
          password:    password,
          displayName: name,
          serverUrl:   url,
        );
        if (res.user == null && mounted) _setError('Could not create account. Try again.');
      }
    } on Exception catch (e) {
      if (mounted) _setError(e.toString().replaceAll(RegExp(r'^Exception: '), ''));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Subtle radial purple glow behind the card
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 500,
              height: 500,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x337C3AED), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomInset + 24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 64),
                    _buildLogo(),
                    const SizedBox(height: 48),
                    _buildModePicker(),
                    const SizedBox(height: 32),
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: _buildCard(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFAB82F0), Color(0xFF7C3AED)],
          ).createShader(bounds),
          child: const Text(
            'ViBE',
            style: TextStyle(
              fontSize: 54,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your music. Premium.',
          style: TextStyle(
            fontSize: 14,
            color: _kTextDim,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildModePicker() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _ModeTab(
            label: 'Sign In',
            selected: _mode == _Mode.signIn,
            onTap: () => _switchMode(_Mode.signIn),
          ),
          _ModeTab(
            label: 'Join ViBE',
            selected: _mode == _Mode.join,
            onTap: () => _switchMode(_Mode.join),
          ),
          _ModeTab(
            label: 'Own Server',
            selected: _mode == _Mode.ownServer,
            onTap: () => _switchMode(_Mode.ownServer),
          ),
        ],
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          ..._buildFields(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 24),
          _buildSubmitButton(),
          if (_mode == _Mode.signIn) ...[
            const SizedBox(height: 16),
            _buildForgotPassword(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final titles = {
      _Mode.signIn:    ('Welcome back', 'Sign in to your account'),
      _Mode.join:      ('Join ViBE',    'Enter your invite code to get started'),
      _Mode.ownServer: ('Connect Server', 'Use your own Jellyfin server'),
    };
    final (title, subtitle) = titles[_mode]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,   style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _kText)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 13, color: _kTextDim)),
      ],
    );
  }

  List<Widget> _buildFields() {
    switch (_mode) {
      case _Mode.signIn:
        return [
          _Field(controller: _emailCtrl,    label: 'Email',    keyboard: TextInputType.emailAddress),
          const SizedBox(height: 12),
          _Field(controller: _passwordCtrl, label: 'Password', obscure: _obscure,
            suffix: _ObscureToggle(obscure: _obscure, onTap: () => setState(() => _obscure = !_obscure)),
          ),
        ];

      case _Mode.join:
        return [
          _CodeField(
            controller:   _codeCtrl,
            checking:     _codeChecking,
            valid:        _codeValid,
            onChanged:    _checkCode,
          ),
          if (_codeValid) ...[
            const SizedBox(height: 12),
            _Field(controller: _nameCtrl,     label: 'Your name'),
            const SizedBox(height: 12),
            _Field(controller: _emailCtrl,    label: 'Email',    keyboard: TextInputType.emailAddress),
            const SizedBox(height: 12),
            _Field(controller: _passwordCtrl, label: 'Password', obscure: _obscure,
              suffix: _ObscureToggle(obscure: _obscure, onTap: () => setState(() => _obscure = !_obscure)),
            ),
          ],
        ];

      case _Mode.ownServer:
        return [
          _Field(controller: _serverCtrl,  label: 'Jellyfin URL',
            hint: 'https://jellyfin.example.com', keyboard: TextInputType.url),
          const SizedBox(height: 12),
          _Field(controller: _nameCtrl,     label: 'Your name'),
          const SizedBox(height: 12),
          _Field(controller: _emailCtrl,    label: 'Email',    keyboard: TextInputType.emailAddress),
          const SizedBox(height: 12),
          _Field(controller: _passwordCtrl, label: 'Password', obscure: _obscure,
            suffix: _ObscureToggle(obscure: _obscure, onTap: () => setState(() => _obscure = !_obscure)),
          ),
        ];
    }
  }

  Widget _buildSubmitButton() {
    final labels = {
      _Mode.signIn:    'Sign In',
      _Mode.join:      'Create Account',
      _Mode.ownServer: 'Create Account',
    };

    return GestureDetector(
      onTap: _loading ? null : _submit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF9B59EE), Color(0xFF6D28D9)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _kAccent.withAlpha(0x55),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: _loading
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                labels[_mode]!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
      ),
    );
  }

  Widget _buildForgotPassword() {
    return Center(
      child: GestureDetector(
        onTap: _showForgotPassword,
        child: const Text(
          'Forgot password?',
          style: TextStyle(color: _kAccentLight, fontSize: 13),
        ),
      ),
    );
  }

  void _showForgotPassword() {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        var sending = false;
        var sent    = false;
        return StatefulBuilder(builder: (ctx, setSt) {
          return Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24,
              24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Reset Password',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kText)),
                const SizedBox(height: 8),
                const Text('We\'ll send a reset link to your email.',
                  style: TextStyle(color: _kTextDim, fontSize: 13)),
                const SizedBox(height: 20),
                if (!sent) ...[
                  _Field(controller: emailCtrl, label: 'Email',
                    keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: sending ? null : () async {
                      setSt(() => sending = true);
                      await AuthService.resetPassword(emailCtrl.text.trim());
                      setSt(() { sending = false; sent = true; });
                    },
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF9B59EE), Color(0xFF6D28D9)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: sending
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Send Reset Link',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ] else ...[
                  const Icon(Icons.check_circle_outline, color: Color(0xFF4CAF50), size: 48),
                  const SizedBox(height: 12),
                  const Text('Check your inbox for a reset link.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _kTextDim)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done', style: TextStyle(color: _kAccentLight)),
                  ),
                ],
              ],
            ),
          );
        });
      },
    );
  }
}

// ── Subwidgets ────────────────────────────────────────────────────────────────

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool   selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color:        selected ? _kAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize:   12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color:      selected ? Colors.white : _kTextDim,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
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
  final String label;
  final String? hint;
  final TextInputType keyboard;
  final bool   obscure;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:          controller,
      obscureText:         obscure,
      keyboardType:        keyboard,
      keyboardAppearance:  Brightness.dark,
      autocorrect:         false,
      enableSuggestions:   !obscure,
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

class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.checking,
    required this.valid,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool checking;
  final bool valid;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:         controller,
      keyboardType:       TextInputType.text,
      keyboardAppearance: Brightness.dark,
      autocorrect:        false,
      textCapitalization: TextCapitalization.characters,
      inputFormatters:    [_CodeFormatter()],
      onChanged:          onChanged,
      style: TextStyle(
        color:       valid ? const Color(0xFF4CAF50) : _kText,
        fontSize:    18,
        fontWeight:  FontWeight.w700,
        letterSpacing: 4,
      ),
      decoration: InputDecoration(
        labelText: 'Invite Code',
        hintText:  'VIBE-XXXXXX',
        hintStyle: const TextStyle(color: Color(0xFF555566), letterSpacing: 2),
        labelStyle: const TextStyle(color: _kTextDim, fontSize: 13),
        filled:    true,
        fillColor: const Color(0xFF0E0E1C),
        suffixIcon: checking
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: _kAccentLight, strokeWidth: 2)),
              )
            : valid
                ? const Icon(Icons.check_circle, color: Color(0xFF4CAF50))
                : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: valid ? const Color(0xFF4CAF50) : _kBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: valid ? const Color(0xFF4CAF50) : _kAccent,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// Auto-inserts the "VIBE-" prefix and formats code as user types
class _CodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue old, TextEditingValue value,
  ) {
    var text = value.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-]'), '');

    // Strip the prefix if present for easier editing
    if (text.startsWith('VIBE-')) {
      text = text.substring(5);
    } else {
      text = text.replaceAll('-', '');
    }

    // Limit suffix to 6 chars
    if (text.length > 6) { text = text.substring(0, 6); }

    final display = 'VIBE-$text';
    return TextEditingValue(
      text:      display,
      selection: TextSelection.collapsed(offset: display.length),
    );
  }
}

class _ObscureToggle extends StatelessWidget {
  const _ObscureToggle({required this.obscure, required this.onTap});
  final bool obscure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: _kTextDim,
        size: 20,
      ),
      onPressed: onTap,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Expanded(child: Text(message,
            style: const TextStyle(color: _kError, fontSize: 13))),
        ],
      ),
    );
  }
}
