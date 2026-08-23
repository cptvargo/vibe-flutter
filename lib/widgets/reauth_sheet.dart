import 'package:flutter/material.dart';
import '../config/jellyfin_config.dart';
import '../services/auth_service.dart';

// Shown when a Jellyfin 401 is received — token expired or revoked.
// Returns true if the user successfully re-authenticated, false if dismissed.
class ReauthSheet extends StatefulWidget {
  const ReauthSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context:           context,
      isScrollControlled: true,
      backgroundColor:   const Color(0xFF12121E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ReauthSheet(),
    );
    return result == true;
  }

  @override
  State<ReauthSheet> createState() => _ReauthSheetState();
}

class _ReauthSheetState extends State<ReauthSheet> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool    _loading = false;
  bool    _obscure = true;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _reconnect() async {
    if (_userCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Enter your Jellyfin username and password.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    final creds = await AuthService.authenticateJellyfin(
      serverUrl: JellyfinConfig.serverUrl,
      username:  _userCtrl.text.trim(),
      password:  _passCtrl.text,
    );

    if (!mounted) return;

    if (creds == null) {
      setState(() {
        _loading = false;
        _error   = 'Wrong username or password. Try again.';
      });
      return;
    }

    await AuthService.saveJellyfinCredentials(
      serverUrl: JellyfinConfig.serverUrl,
      token:     creds.token,
      userId:    creds.userId,
    );

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final serverHost = Uri.tryParse(JellyfinConfig.serverUrl)?.host
        ?? JellyfinConfig.serverUrl;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 24, 24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Icon(Icons.link_off_rounded, color: Color(0xFFAB82F0), size: 32),
          const SizedBox(height: 12),

          const Text(
            'Reconnect to Jellyfin',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your session on $serverHost expired.\nRe-enter your Jellyfin credentials to reconnect.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),

          _field(
            controller: _userCtrl,
            label: 'Jellyfin Username',
          ),
          const SizedBox(height: 12),
          _field(
            controller: _passCtrl,
            label: 'Jellyfin Password',
            obscure: _obscure,
            suffix: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: const Color(0xFFAAAAAA),
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x22FF5252),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x66FF5252)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFFF5252), size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          GestureDetector(
            onTap: _loading ? null : _reconnect,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9B59EE), Color(0xFF6D28D9)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withAlpha(0x55),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text(
                      'Reconnect',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel',
              style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller:         controller,
      obscureText:        obscure,
      keyboardAppearance: Brightness.dark,
      autocorrect:        false,
      enableSuggestions:  !obscure,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText:  label,
        labelStyle: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13),
        filled:     true,
        fillColor:  const Color(0xFF0E0E1C),
        suffixIcon: suffix,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   const BorderSide(color: Color(0x22FFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
