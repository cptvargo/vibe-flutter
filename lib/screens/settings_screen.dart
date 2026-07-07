import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/auth_service.dart';
import '../theme/vibe_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _server;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await AuthService.getProfile();
    await AuthService.ensureServerRegistered();
    final server  = await AuthService.getMyServer();
    if (mounted) setState(() { _profile = profile; _server = server; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: theme.accentBright, strokeWidth: 2));
    }

    final user        = AuthService.user;
    final displayName = _profile?['display_name'] as String? ?? user?.email ?? 'ViBE User';
    final email       = user?.email ?? '';

    return Scaffold(
      backgroundColor: theme.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(child: _HeroBanner(theme: theme, displayName: displayName, email: email)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _Section(
                  theme: theme,
                  title: 'Profile',
                  children: [
                    _EditNameTile(theme: theme, current: displayName, onSaved: (v) async {
                      await AuthService.updateProfile({'display_name': v});
                      await _load();
                    }),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  theme: theme,
                  title: 'Server',
                  children: [
                    _InfoTile(
                      theme: theme,
                      icon: Icons.dns_outlined,
                      label: _server?['server_name'] as String? ?? 'My Server',
                      value: _server?['server_url'] as String? ?? '',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  theme: theme,
                  title: 'Invite Codes',
                  children: [
                    _InviteTile(theme: theme, server: _server),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  theme: theme,
                  title: 'Account',
                  children: [
                    _InfoTile(
                      theme: theme,
                      icon: Icons.mail_outline,
                      label: 'Email',
                      value: email,
                    ),
                    _Divider(theme: theme),
                    _ActionTile(
                      theme: theme,
                      icon: Icons.lock_reset_outlined,
                      label: 'Change Password',
                      onTap: () async {
                        await AuthService.resetPassword(email);
                        if (mounted) _showSnack('Reset link sent to $email');
                      },
                    ),
                    _Divider(theme: theme),
                    _ActionTile(
                      theme: theme,
                      icon: Icons.logout,
                      label: 'Sign Out',
                      destructive: true,
                      onTap: _confirmSignOut,
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E1E30),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _confirmSignOut() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12121E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Sign Out?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('You\'ll need to sign back in to listen.',
              style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                AuthService.signOut();
              },
              child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFFAAAAAA))),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hero / Avatar ────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.theme, required this.displayName, required this.email});
  final VibeTheme theme;
  final String displayName;
  final String email;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        // Gradient hero
        Container(
          height: 220 + topPad,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.accent.withAlpha(0xCC),
                theme.background,
              ],
            ),
          ),
        ),
        // Bottom fade
        Positioned(
          left: 0, right: 0, bottom: 0,
          height: 80,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, theme.background],
              ),
            ),
          ),
        ),
        // Avatar + name
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Column(
            children: [
              _Avatar(displayName: displayName, accent: theme.accent),
              const SizedBox(height: 12),
              Text(
                displayName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                email,
                style: const TextStyle(fontSize: 12, color: Color(0xFFAAAAAA)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.displayName, required this.accent});
  final String displayName;
  final Color accent;

  String get _initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return displayName.isNotEmpty ? displayName[0].toUpperCase() : 'V';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [accent, Color.lerp(accent, Colors.black, 0.3)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withAlpha(0x33), width: 2),
        boxShadow: [BoxShadow(color: accent.withAlpha(0x55), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ── Section card ─────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.theme, required this.title, required this.children});
  final VibeTheme theme;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: theme.textFaint,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.surface.withAlpha(0xCC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withAlpha(0x10)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.theme});
  final VibeTheme theme;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 48,
      color: Colors.white.withAlpha(0x0F),
    );
  }
}

// ── Tiles ────────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.theme, required this.icon, required this.label, required this.value});
  final VibeTheme theme;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.accentBright.withAlpha(0xAA)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: theme.textFaint)),
                const SizedBox(height: 2),
                Text(value,
                  style: TextStyle(fontSize: 14, color: theme.textColor, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.theme,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.trailing,
  });
  final VibeTheme theme;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFE53935) : theme.textColor;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: destructive ? const Color(0xFFE53935) : theme.accentBright.withAlpha(0xAA)),
            const SizedBox(width: 12),
            Expanded(child: Text(label,
              style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w500))),
            trailing ?? Icon(Icons.chevron_right, size: 18, color: theme.textFaint),
          ],
        ),
      ),
    );
  }
}

// ── Edit name tile ────────────────────────────────────────────────────────────

class _EditNameTile extends StatelessWidget {
  const _EditNameTile({required this.theme, required this.current, required this.onSaved});
  final VibeTheme theme;
  final String current;
  final Future<void> Function(String) onSaved;

  @override
  Widget build(BuildContext context) {
    return _ActionTile(
      theme: theme,
      icon: Icons.person_outline,
      label: current,
      trailing: Icon(Icons.edit_outlined, size: 16, color: theme.textFaint),
      onTap: () => _showEdit(context),
    );
  }

  void _showEdit(BuildContext context) {
    final ctrl = TextEditingController(text: current);
    var saving = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12121E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24,
            24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Edit Name',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardAppearance: Brightness.dark,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'Display Name',
                  labelStyle: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF0E0E1C),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0x22FFFFFF)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.accent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: saving ? null : () async {
                  final v = ctrl.text.trim();
                  if (v.isEmpty) return;
                  setSt(() => saving = true);
                  await onSaved(v);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: saving
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Invite code tile ──────────────────────────────────────────────────────────

class _InviteTile extends StatefulWidget {
  const _InviteTile({required this.theme, required this.server});
  final VibeTheme theme;
  final Map<String, dynamic>? server;

  @override
  State<_InviteTile> createState() => _InviteTileState();
}

class _InviteTileState extends State<_InviteTile> {
  String? _lastCode;
  bool _generating = false;
  bool _copied     = false;

  Future<void> _generate() async {
    if (widget.server == null) return;
    setState(() => _generating = true);
    final code = await AuthService.generateInviteCode(widget.server!['id'] as String);
    if (mounted) setState(() { _lastCode = code; _generating = false; _copied = false; });
  }

  void _copy() {
    if (_lastCode == null) return;
    Clipboard.setData(ClipboardData(text: _lastCode!));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.server == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.card_giftcard_outlined, size: 18,
              color: widget.theme.accentBright.withAlpha(0x55)),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Register your server first to generate codes.',
                style: TextStyle(fontSize: 13, color: widget.theme.textFaint)),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Generate button
          GestureDetector(
            onTap: _generating ? null : _generate,
            child: Row(
              children: [
                Icon(Icons.card_giftcard_outlined, size: 18,
                  color: widget.theme.accentBright.withAlpha(0xAA)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Generate Invite Code',
                    style: TextStyle(fontSize: 14, color: widget.theme.textColor,
                      fontWeight: FontWeight.w500)),
                ),
                if (_generating)
                  SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                      color: widget.theme.accentBright, strokeWidth: 2))
                else
                  Icon(Icons.add_circle_outline, size: 18, color: widget.theme.accentBright),
              ],
            ),
          ),
          // Show generated code
          if (_lastCode != null) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _copy,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _copied
                      ? const Color(0xFF4CAF50).withAlpha(0x22)
                      : Colors.white.withAlpha(0x0A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _copied
                        ? const Color(0xFF4CAF50).withAlpha(0x66)
                        : Colors.white.withAlpha(0x14),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _lastCode!,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3,
                          color: _copied ? const Color(0xFF4CAF50) : Colors.white,
                        ),
                      ),
                    ),
                    Icon(
                      _copied ? Icons.check : Icons.copy_outlined,
                      size: 16,
                      color: _copied ? const Color(0xFF4CAF50) : widget.theme.textFaint,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _copied ? 'Copied!' : 'Tap to copy • Valid for 10 uses',
              style: TextStyle(
                fontSize: 11,
                color: _copied ? const Color(0xFF4CAF50) : widget.theme.textFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Register server tile ──────────────────────────────────────────────────────

class _RegisterServerTile extends StatefulWidget {
  const _RegisterServerTile({required this.theme, required this.profile, required this.onRegistered});
  final VibeTheme theme;
  final Map<String, dynamic>? profile;
  final VoidCallback onRegistered;

  @override
  State<_RegisterServerTile> createState() => _RegisterServerTileState();
}

class _RegisterServerTileState extends State<_RegisterServerTile> {
  @override
  Widget build(BuildContext context) {
    return _ActionTile(
      theme: widget.theme,
      icon: Icons.dns_outlined,
      label: 'Register My Server',
      onTap: () => _showRegisterSheet(context),
    );
  }

  void _showRegisterSheet(BuildContext context) {
    final urlCtrl  = TextEditingController(
      text: widget.profile?['server_url'] as String? ?? '');
    final nameCtrl = TextEditingController(text: 'My Jellyfin Server');
    var saving = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12121E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24,
            24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Register Server',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 6),
              const Text('Register your Jellyfin server to share it with friends.',
                style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13)),
              const SizedBox(height: 20),
              _sheetField(ctx, nameCtrl, 'Server Name'),
              const SizedBox(height: 12),
              _sheetField(ctx, urlCtrl, 'Server URL',
                hint: 'https://jellyfin.example.com',
                keyboard: TextInputType.url),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.theme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: saving ? null : () async {
                  final url  = urlCtrl.text.trim().replaceAll(RegExp(r'/$'), '');
                  final name = nameCtrl.text.trim();
                  if (url.isEmpty || name.isEmpty) return;
                  setSt(() => saving = true);
                  await AuthService.registerServer(serverUrl: url, serverName: name);
                  if (ctx.mounted) Navigator.pop(ctx);
                  widget.onRegistered();
                },
                child: saving
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Register', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _sheetField(BuildContext ctx, TextEditingController ctrl, String label,
      {String? hint, TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      keyboardAppearance: Brightness.dark,
      autocorrect: false,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF555566)),
        labelStyle: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF0E0E1C),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x22FFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: widget.theme.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
