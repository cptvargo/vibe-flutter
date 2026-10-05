import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../api/jellyfin_api.dart';
import '../theme/vibe_theme.dart';

class CreatePlaylistSheet extends StatefulWidget {
  final VibeTheme theme;
  final VoidCallback? onCreated;

  const CreatePlaylistSheet({super.key, required this.theme, this.onCreated});

  @override
  State<CreatePlaylistSheet> createState() => _CreatePlaylistSheetState();
}

class _CreatePlaylistSheetState extends State<CreatePlaylistSheet> {
  final _nameCtrl = TextEditingController();
  Uint8List? _imageBytes;
  String _imageMimeType = 'image/jpeg';
  bool _creating = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final xFile = await ImagePicker().pickImage(
      source:       ImageSource.gallery,
      maxWidth:     1200,
      maxHeight:    1200,
      imageQuality: 90,
    );
    if (xFile == null || !mounted) return;
    final bytes    = await xFile.readAsBytes();
    final mimeType = xFile.mimeType ??
        (xFile.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
    setState(() {
      _imageBytes    = bytes;
      _imageMimeType = mimeType;
    });
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _creating = true);
    try {
      final result = await JellyfinApi.createPlaylist(name);
      final id = result['Id'] as String? ?? result['id'] as String?;
      if (id != null && _imageBytes != null) {
        await JellyfinApi.uploadPlaylistImage(id, _imageBytes!, _imageMimeType);
      }
      if (mounted) Navigator.pop(context);
      widget.onCreated?.call();
    } catch (_) {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme    = widget.theme;
    final hasImage = _imageBytes != null;

    return Container(
      decoration: const BoxDecoration(
        color:        Color(0xFF12121E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left:   24, right: 24, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color:        const Color(0xFF2E2E48),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 22),
          Text('New Playlist',
              style: TextStyle(
                  color:      theme.textColor,
                  fontSize:   18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 24),

          // Artwork picker
          GestureDetector(
            onTap: _pickImage,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 160, height: 160,
                child: hasImage
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(_imageBytes!, fit: BoxFit.cover),
                          Container(
                            color: Colors.black38,
                            alignment: Alignment.center,
                            child: const Icon(Icons.edit_rounded,
                                color: Colors.white, size: 32),
                          ),
                        ],
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin:  Alignment.topLeft,
                            end:    Alignment.bottomRight,
                            colors: [Color(0xFF4C1D95), Color(0xFF1E1B4B)],
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                color: Colors.white54, size: 40),
                            SizedBox(height: 8),
                            Text('Add artwork',
                                style: TextStyle(
                                    color:    Colors.white38,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Name field
          TextField(
            controller: _nameCtrl,
            autofocus:  true,
            style:      TextStyle(color: theme.textColor),
            cursorColor: theme.accent,
            decoration: InputDecoration(
              hintText:  'Playlist name',
              hintStyle: const TextStyle(color: Color(0xFF5C5C78)),
              enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF2E2E48))),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: theme.accent)),
            ),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 28),

          // Create button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: _creating
                ? Center(child: CircularProgressIndicator(color: theme.accent))
                : ElevatedButton(
                    onPressed: _create,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: Colors.white,
                      elevation:       0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Create',
                        style: TextStyle(
                            fontSize:   16,
                            fontWeight: FontWeight.w700)),
                  ),
          ),
        ],
      ),
    );
  }
}
