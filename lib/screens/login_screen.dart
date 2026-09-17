import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/jellyfin_config.dart';
import '../providers/connection_notifier.dart';
import '../services/auth_service.dart';
import '../config/vibe_config.dart';

// Three paths into ViBE:
//   tryVibe       → demo mode, AI music only, no account
//   friendsLibrary → invite code + Jellyfin credentials for a shared server
//   ownServer     → your own Jellyfin server

enum _Mode { tryVibe, friendsLibrary, ownServer, signIn }

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
  _Mode _mode = _Mode.tryVibe;

  final _serverCtrl       = TextEditingController();
  final _jellyfinUserCtrl = TextEditingController();
  final _jellyfinPassCtrl = TextEditingController();
  final _codeCtrl         = TextEditingController();
  final _nameCtrl         = TextEditingController();
  final _emailCtrl        = TextEditingController();
  final _vibePassCtrl     = TextEditingController();

  bool    _loading          = false;
  bool    _jellyfinObscure  = true;
  bool    _vibeObscure      = true;
  bool    _hasSetup         = false;
  String? _error;

  bool _codeChecking = false;
  bool _codeValid    = false;

  late final AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _loadSetupFlag();
  }

  Future<void> _loadSetupFlag() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final has = prefs.getBool('vibe_has_setup') ?? false;
    setState(() {
      _hasSetup = has;
      // If we loaded on the ownServer tab but the user already has an account,
      // silently switch to signIn so the tab and content stay in sync.
      if (has && _mode == _Mode.ownServer) _mode = _Mode.signIn;
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _serverCtrl.dispose();
    _jellyfinUserCtrl.dispose();
    _jellyfinPassCtrl.dispose();
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _vibePassCtrl.dispose();
    super.dispose();
  }

  void _switchMode(_Mode mode) {
    if (_mode == mode) return;
    _fadeCtrl.reverse().then((_) async {
      if (!mounted) return;
      setState(() {
        _mode  = mode;
        _error = null;
        _codeValid = false;
        _codeCtrl.clear();
        _jellyfinUserCtrl.clear();
        _jellyfinPassCtrl.clear();
        _nameCtrl.clear();
        _emailCtrl.clear();
        _vibePassCtrl.clear();
      });
      _fadeCtrl.forward();
      if (mode == _Mode.friendsLibrary) {
        final clip = await Clipboard.getData(Clipboard.kTextPlain);
        final raw  = clip?.text?.toUpperCase().trim() ?? '';
        final stripped = raw.startsWith('VIBE-')
            ? raw.substring(5).replaceAll(RegExp(r'[^A-Z0-9]'), '')
            : raw.replaceAll(RegExp(r'[^A-Z0-9]'), '');
        final isVibeCode = raw.startsWith('VIBE-') || stripped.length == 6;
        if (isVibeCode && stripped.length == 6 && mounted) {
          _codeCtrl.text = stripped;
          _checkCode(stripped);
        }
      }
    });
  }

  void _setError(String msg) => setState(() { _error = msg; _loading = false; });

  Future<void> _checkCode(String raw) async {
    final code = raw.toUpperCase().trim();
    if (code.length < 4) {
      setState(() => _codeValid = false);
      return;
    }
    setState(() => _codeChecking = true);
    try {
      final data = await AuthService.redeemInviteCode(code);
      if (mounted) setState(() {
        _codeChecking = false;
        _codeValid    = data != null;
        _error = data == null ? 'Invalid or expired invite code.' : null;
      });
    } catch (_) {
      if (mounted) setState(() { _codeChecking = false; _codeValid = false; });
    }
  }

  Future<void> _submit() async {
    switch (_mode) {
      case _Mode.tryVibe:
        connectionNotifier.enterDemo();
        return;

      case _Mode.ownServer:
        await _connectOwnServer();

      case _Mode.friendsLibrary:
        await _joinFriendsLibrary();

      case _Mode.signIn:
        await _signIn();
    }
  }

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final vPass = _vibePassCtrl.text;

    if (email.isEmpty) { _setError('Enter your email.'); return; }
    if (vPass.isEmpty) { _setError('Enter your ViBE password.'); return; }

    setState(() { _loading = true; _error = null; });
    try {
      final res = await AuthService.signIn(email: email, password: vPass);
      if (res.user == null) { _setError('Invalid email or password.'); return; }
      // Restore Jellyfin credentials from Supabase user metadata (or Hive cache)
      await JellyfinConfig.load();
      // Always persist resolved credentials to Hive so cold-start doesn't
      // need the Supabase round-trip and the user stays logged in.
      await JellyfinConfig.save(
        serverUrl: JellyfinConfig.serverUrl,
        apiKey:    JellyfinConfig.apiKey,
        userId:    JellyfinConfig.userId,
        vibeLib:   JellyfinConfig.vibeLib,
        aiLib:     JellyfinConfig.aiLib,
      );
      connectionNotifier.connect();
    } on AuthException catch (e) {
      if (mounted) _setError(e.message);
    } on Exception catch (e) {
      if (mounted) _setError(e.toString().replaceAll(RegExp(r'^Exception: '), ''));
    }
  }

  Future<void> _connectOwnServer() async {
    final url   = _serverCtrl.text.trim().replaceAll(RegExp(r'/$'), '');
    final jUser = _jellyfinUserCtrl.text.trim();
    final jPass = _jellyfinPassCtrl.text;
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final vPass = _vibePassCtrl.text;

    if (url.isEmpty)   { _setError('Enter your Jellyfin server URL.'); return; }
    if (jUser.isEmpty) { _setError('Enter your Jellyfin username.'); return; }
    if (jPass.isEmpty) { _setError('Enter your Jellyfin password.'); return; }
    if (name.isEmpty)  { _setError('Enter your name.'); return; }
    if (email.isEmpty) { _setError('Enter an email for your ViBE account.'); return; }
    if (vPass.isEmpty) { _setError('Enter a password for your ViBE account.'); return; }

    setState(() { _loading = true; _error = null; });
    try {
      // 1. Validate Jellyfin credentials first
      final creds = await AuthService.authenticateJellyfin(
        serverUrl: url, username: jUser, password: jPass,
      );
      if (creds == null) {
        _setError('Could not connect. Check your server URL and credentials.');
        return;
      }
      // 2. Create ViBE account (stores Jellyfin creds in Supabase metadata
      //    so Sign In can restore them without re-entering Jellyfin credentials)
      final res = await AuthService.signUpWithServer(
        email: email, password: vPass, displayName: name,
        serverUrl: url, jellyfinToken: creds.token, jellyfinUserId: creds.userId,
      );
      if (res.user == null) {
        _setError('Could not create your ViBE account. Try a different email.');
        return;
      }
      // 3. Save Jellyfin credentials to Hive, mark account as set up, and connect
      await JellyfinConfig.save(serverUrl: url, apiKey: creds.token, userId: creds.userId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('vibe_has_setup', true);
      connectionNotifier.connect();
    } on AuthException catch (e) {
      if (mounted) _setError(e.message);
    } on Exception catch (e) {
      if (mounted) _setError(e.toString().replaceAll(RegExp(r'^Exception: '), ''));
    }
  }

  Future<void> _joinFriendsLibrary() async {
    if (!_codeValid) { _setError('Enter a valid invite code first.'); return; }
    if (_jellyfinUserCtrl.text.trim().isEmpty) { _setError('Enter your Jellyfin username.'); return; }
    if (_jellyfinPassCtrl.text.isEmpty) { _setError('Enter your Jellyfin password.'); return; }

    setState(() { _loading = true; _error = null; });
    try {
      final result = await AuthService.createJellyfinAccountForInvite(
        inviteCode: _codeCtrl.text.trim(),
        username:   _jellyfinUserCtrl.text.trim(),
        password:   _jellyfinPassCtrl.text,
      );
      final serverUrl = result['server_url'] as String;
      final token     = result['jellyfin_token'] as String;
      final userId    = result['jellyfin_user_id'] as String;
      await JellyfinConfig.save(
        serverUrl: serverUrl,
        apiKey:    token,
        userId:    userId,
        vibeLib:   VibeConfig.vibeLibrary,
        aiLib:     VibeConfig.aiLibrary,
      );
      connectionNotifier.connect();
    } on Exception catch (e) {
      if (mounted) _setError(e.toString().replaceAll(RegExp(r'^Exception: '), ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: _kBg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned(
            top: -120, left: -80,
            child: Container(
              width: 500, height: 500,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0x337C3AED), Colors.transparent]),
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
            style: TextStyle(fontSize: 54, fontWeight: FontWeight.w800, letterSpacing: 8, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your music. Premium.',
          style: TextStyle(fontSize: 14, color: _kTextDim, letterSpacing: 1.5),
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
          _ModeTab(label: 'Try ViBE',        selected: _mode == _Mode.tryVibe,        onTap: () => _switchMode(_Mode.tryVibe)),
          _ModeTab(label: 'Friends Library', selected: _mode == _Mode.friendsLibrary, onTap: () => _switchMode(_Mode.friendsLibrary)),
          _ModeTab(
            label:    _hasSetup ? 'Sign In'   : 'Own Server',
            selected: _hasSetup ? _mode == _Mode.signIn : _mode == _Mode.ownServer,
            onTap:    () => _switchMode(_hasSetup ? _Mode.signIn : _Mode.ownServer),
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
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final titles = <_Mode, (String, String)>{
      _Mode.tryVibe:        ('Try ViBE',            'Explore AI-curated music — no account needed.'),
      _Mode.friendsLibrary: ("Friend's Library",    'Got an invite code? Access their shared music library.'),
      _Mode.ownServer:      ('Connect Your Server', 'Use your own Jellyfin server with your full library.'),
      _Mode.signIn:         ('Welcome Back',        'Sign in to your ViBE account.'),
    };
    final (title, subtitle) = titles[_mode]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _kText)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 13, color: _kTextDim)),
      ],
    );
  }

  List<Widget> _buildFields() {
    switch (_mode) {
      case _Mode.tryVibe:
        return [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kAccent.withAlpha(0x18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kAccent.withAlpha(0x33)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Row(children: [
                  Icon(Icons.auto_awesome_rounded, color: _kAccentLight, size: 16),
                  SizedBox(width: 8),
                  Text('AI-Generated Music', style: TextStyle(color: _kAccentLight, fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
                SizedBox(height: 8),
                Text(
                  'Listen to a curated library of original AI music — free to explore anytime.',
                  style: TextStyle(color: _kTextDim, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ];

      case _Mode.friendsLibrary:
        return [
          _CodeField(
            controller: _codeCtrl,
            checking:   _codeChecking,
            valid:      _codeValid,
            onChanged:  _checkCode,
          ),
          if (_codeValid) ...[
            const SizedBox(height: 20),
            _SectionLabel(icon: Icons.person_outline, label: 'Your account on their server'),
            const SizedBox(height: 12),
            _Field(
              controller: _jellyfinUserCtrl,
              label: 'Jellyfin Username',
              hint: 'What you\'ll be called on the server',
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _jellyfinPassCtrl,
              label: 'Jellyfin Password',
              obscure: _jellyfinObscure,
              suffix: _ObscureToggle(
                obscure: _jellyfinObscure,
                onTap: () => setState(() => _jellyfinObscure = !_jellyfinObscure),
              ),
            ),
          ],
        ];

      case _Mode.signIn:
        return [
          _Field(
            controller: _emailCtrl,
            label: 'Email',
            keyboard: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _vibePassCtrl,
            label: 'Password',
            obscure: _vibeObscure,
            suffix: _ObscureToggle(
              obscure: _vibeObscure,
              onTap: () => setState(() => _vibeObscure = !_vibeObscure),
            ),
          ),
        ];

      case _Mode.ownServer:
        return [
          _SectionLabel(icon: Icons.dns_outlined, label: 'Your Jellyfin server'),
          const SizedBox(height: 12),
          _Field(
            controller: _serverCtrl,
            label: 'Server URL',
            hint: 'https://jellyfin.example.com',
            keyboard: TextInputType.url,
          ),
          const SizedBox(height: 12),
          _Field(controller: _jellyfinUserCtrl, label: 'Jellyfin Username'),
          const SizedBox(height: 12),
          _Field(
            controller: _jellyfinPassCtrl,
            label: 'Jellyfin Password',
            obscure: _jellyfinObscure,
            suffix: _ObscureToggle(
              obscure: _jellyfinObscure,
              onTap: () => setState(() => _jellyfinObscure = !_jellyfinObscure),
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(icon: Icons.person_outline, label: 'Create your ViBE account'),
          const SizedBox(height: 12),
          _Field(controller: _nameCtrl, label: 'Name'),
          const SizedBox(height: 12),
          _Field(
            controller: _emailCtrl,
            label: 'Email',
            keyboard: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _vibePassCtrl,
            label: 'Password',
            obscure: _vibeObscure,
            suffix: _ObscureToggle(
              obscure: _vibeObscure,
              onTap: () => setState(() => _vibeObscure = !_vibeObscure),
            ),
          ),
        ];
    }
  }

  Widget _buildSubmitButton() {
    final String label;
    switch (_mode) {
      case _Mode.tryVibe:        label = 'Try ViBE';
      case _Mode.friendsLibrary: label = _loading ? 'Joining...'           : 'Join Library';
      case _Mode.ownServer:      label = _loading ? 'Creating Account...'  : 'Create Account';
      case _Mode.signIn:         label = _loading ? 'Signing In...'        : 'Sign In';
    }

    return GestureDetector(
      onTap: _loading ? null : _submit,
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
            : Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
      ),
    );
  }
}

// ── Subwidgets ────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});
  final IconData icon;
  final String   label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _kAccentLight, size: 14),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: _kAccentLight, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: const Color(0x22FFFFFF))),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.label, required this.selected, required this.onTap});
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
        color:         valid ? const Color(0xFF4CAF50) : _kText,
        fontSize:      18,
        fontWeight:    FontWeight.w700,
        letterSpacing: 4,
      ),
      decoration: InputDecoration(
        labelText: 'Invite Code',
        hintText:  'XXXXXX',
        hintStyle: const TextStyle(color: Color(0xFF555566), letterSpacing: 2),
        labelStyle: const TextStyle(color: _kTextDim, fontSize: 13),
        filled:    true,
        fillColor: const Color(0xFF0E0E1C),
        suffixIcon: checking
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: _kAccentLight, strokeWidth: 2)))
            : valid
                ? const Icon(Icons.check_circle, color: Color(0xFF4CAF50))
                : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: valid ? const Color(0xFF4CAF50) : _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: valid ? const Color(0xFF4CAF50) : _kAccent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _CodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) {
    var text = value.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (text.length > 6) text = text.substring(0, 6);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class _ObscureToggle extends StatelessWidget {
  const _ObscureToggle({required this.obscure, required this.onTap});
  final bool obscure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: _kTextDim, size: 20),
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
          Expanded(child: Text(message, style: const TextStyle(color: _kError, fontSize: 13))),
        ],
      ),
    );
  }
}
