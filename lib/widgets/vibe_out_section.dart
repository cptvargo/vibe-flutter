import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api/jellyfin_models.dart';
import '../providers.dart';
import '../services/download_service.dart';
import '../services/vibe_out_service.dart';
import '../theme/vibe_theme.dart';

const _kPageCount = 7;
const _kPerPage   = 4;

class VibeOutSection extends ConsumerStatefulWidget {
  final VibeTheme theme;
  const VibeOutSection({super.key, required this.theme});

  @override
  ConsumerState<VibeOutSection> createState() => _VibeOutSectionState();
}

class _VibeOutSectionState extends ConsumerState<VibeOutSection> {
  List<VibeTrack>           _tracks  = [];
  StreamSubscription<void>? _sub;
  final _pageCtrl = PageController();
  int   _page     = 0;

  @override
  void initState() {
    super.initState();
    _tracks = VibeOutService.tracks;
    _sub = VibeOutService.updated.listen((_) {
      if (mounted) setState(() => _tracks = VibeOutService.tracks);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _playAll() async {
    if (_tracks.isEmpty || !mounted) return;
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    await ref.read(audioHandlerProvider).playTracks(
      List.of(_tracks),
      playbackContext: 'vibe_out',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_tracks.isEmpty) return const SizedBox.shrink();

    final theme = widget.theme;
    final pages = List.generate(
      _kPageCount,
      (p) => _tracks.skip(p * _kPerPage).take(_kPerPage).toList(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ───────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'ViBE Out',
                  style: TextStyle(
                    color:       theme.textColor,
                    fontSize:    18,
                    fontWeight:  FontWeight.w700,
                    letterSpacing: 0.4,
                    shadows: [
                      Shadow(color: theme.accent.withAlpha(0xCC), blurRadius: 10),
                      Shadow(color: theme.accentBright.withAlpha(0x66), blurRadius: 24),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: _playAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color:        theme.accent.withAlpha(0x22),
                    borderRadius: BorderRadius.circular(20),
                    border:       Border.all(color: theme.accent.withAlpha(0x55)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded,
                          color: theme.accentBright, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Play All',
                        style: TextStyle(
                          color:      theme.accentBright,
                          fontSize:   13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Paginated track list ──────────────────────────────────────────────
        SizedBox(
          height: _kPerPage * 64.0 + (_kPerPage - 1) * 2.0,
          child: PageView.builder(
            controller:  _pageCtrl,
            itemCount:   _kPageCount,
            onPageChanged: (p) => setState(() => _page = p),
            itemBuilder: (_, p) => _TrackPage(
              tracks: pages[p],
              theme:  theme,
              ref:    ref,
              onRemove: (t) async {
                await VibeOutService.replaceTrack(t.id);
              },
            ),
          ),
        ),

        // ── Dot indicators ────────────────────────────────────────────────────
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_kPageCount, (i) {
            final active = i == _page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin:  const EdgeInsets.symmetric(horizontal: 3),
              width:   active ? 16 : 6,
              height:  6,
              decoration: BoxDecoration(
                color:        active
                    ? theme.accentBright
                    : theme.textFaint.withAlpha(0x55),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ── One page (4 tracks) ───────────────────────────────────────────────────────

class _TrackPage extends StatelessWidget {
  final List<VibeTrack>       tracks;
  final VibeTheme             theme;
  final WidgetRef             ref;
  final Future<void> Function(VibeTrack) onRemove;

  const _TrackPage({
    required this.tracks,
    required this.theme,
    required this.ref,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < tracks.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          _TrackCard(
            track:    tracks[i],
            theme:    theme,
            ref:      ref,
            onRemove: () => onRemove(tracks[i]),
          ),
        ],
      ],
    );
  }
}

// ── Track card ────────────────────────────────────────────────────────────────

class _TrackCard extends StatelessWidget {
  final VibeTrack             track;
  final VibeTheme             theme;
  final WidgetRef             ref;
  final VoidCallback          onRemove;

  const _TrackCard({
    required this.track,
    required this.theme,
    required this.ref,
    required this.onRemove,
  });

  Future<void> _play(BuildContext context) async {
    ref.read(playerOpenProvider.notifier).state = true;
    context.push('/player');
    await ref.read(audioHandlerProvider).playTracks(
      [track],
      playbackContext: 'vibe_out',
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context:          context,
      backgroundColor:  const Color(0xFF12121E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TrackMenu(
        track:    track,
        theme:    theme,
        ref:      ref,
        onRemove: onRemove,
        context:  context,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDownloaded = DownloadService.isDownloaded(track.id);

    return SizedBox(
      height: 64,
      child: Row(
        children: [
          // ── Tappable zone: art + text only ──────────────────────────────
          Expanded(
            child: GestureDetector(
              onTap: () => _play(context),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: track.artworkUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl:    track.artworkUrl,
                              width:       48,
                              height:      48,
                              fit:         BoxFit.cover,
                              errorWidget: (_, _, _) => _artFallback(),
                            )
                          : _artFallback(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  track.title,
                                  style: TextStyle(
                                    color:      theme.textColor,
                                    fontSize:   14,
                                    fontWeight: FontWeight.w600,
                                    height:     1.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isDownloaded)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Icons.download_done_rounded,
                                      size: 13,
                                      color: theme.accentBright.withAlpha(0x99)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            style: TextStyle(
                              color:    theme.textFaint,
                              fontSize: 12,
                              height:   1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── 3-dot: isolated from the play tap zone ───────────────────────
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: theme.textFaint, size: 20),
            onPressed: () => _showMenu(context),
            padding:      const EdgeInsets.only(right: 8),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _artFallback() => Container(
    width: 48, height: 48,
    decoration: BoxDecoration(
      color:        theme.surface,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Icon(Icons.music_note_rounded, color: theme.textFaint, size: 20),
  );
}

// ── 3-dot menu ────────────────────────────────────────────────────────────────

class _TrackMenu extends StatefulWidget {
  final VibeTrack    track;
  final VibeTheme    theme;
  final WidgetRef    ref;
  final VoidCallback onRemove;
  final BuildContext context; // outer scaffold context for navigation

  const _TrackMenu({
    required this.track,
    required this.theme,
    required this.ref,
    required this.onRemove,
    required this.context,
  });

  @override
  State<_TrackMenu> createState() => _TrackMenuState();
}

class _TrackMenuState extends State<_TrackMenu> {
  bool _downloading = false;
  bool _sharing     = false;

  VibeTrack  get _t   => widget.track;
  VibeTheme  get _th  => widget.theme;
  WidgetRef  get _ref => widget.ref;

  Future<void> _playNext() async {
    Navigator.pop(context);
    await _ref.read(audioHandlerProvider).playNext(_t);
  }

  Future<void> _addToQueue() async {
    Navigator.pop(context);
    await _ref.read(audioHandlerProvider).addToQueue(_t);
  }

  void _goToAlbum() {
    Navigator.pop(context);
    if (_t.albumId == null || _t.albumId!.isEmpty) return;
    widget.context.push(
      '/album/${_t.albumId}'
      '?name=${Uri.encodeComponent(_t.album)}'
      '&artist=${Uri.encodeComponent(_t.artist)}',
    );
  }

  void _goToArtist() {
    Navigator.pop(context);
    if (_t.artistId == null || _t.artistId!.isEmpty) return;
    widget.context.push(
      '/artist/${_t.artistId}'
      '?name=${Uri.encodeComponent(_t.artist)}',
    );
  }

  Future<void> _download() async {
    if (DownloadService.isDownloaded(_t.id) ||
        DownloadService.isDownloading(_t.id)) {
      Navigator.pop(context);
      return;
    }
    setState(() => _downloading = true);
    DownloadService.downloadTrack(_t);
    Navigator.pop(context);
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final path = await _buildShareCard(_t, _th.accent);
      if (path == null) { setState(() => _sharing = false); return; }

      final deepLink =
          'com.playvibemusic.vibe://song/${_t.id}'
          '?title=${Uri.encodeComponent(_t.title)}'
          '&artist=${Uri.encodeComponent(_t.artist)}';

      await SharePlus.instance.share(ShareParams(
        files:   [XFile(path, mimeType: 'image/png')],
        subject: '${_t.title} — ViBE',
        text:    '"${_t.title}" by ${_t.artist}\nViBE out to this track 🎵\n$deepLink',
      ));
    } catch (_) {}
    if (mounted) setState(() => _sharing = false);
  }

  void _removeFromVibeOut() {
    Navigator.pop(context);
    widget.onRemove();
  }

  @override
  Widget build(BuildContext context) {
    final downloaded = DownloadService.isDownloaded(_t.id);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color:        Colors.white.withAlpha(0x33),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Track info header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: _t.artworkUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl:    _t.artworkUrl,
                            width:       40,
                            height:      40,
                            fit:         BoxFit.cover,
                            errorWidget: (_, _, _) => const SizedBox(width: 40, height: 40),
                          )
                        : const SizedBox(width: 40, height: 40),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_t.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(_t.artist,
                          style: const TextStyle(
                              color: Color(0xFFAAAAAA), fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0x15FFFFFF)),
            const SizedBox(height: 4),
            _MenuItem(
              icon:  Icons.skip_next_rounded,
              label: 'Play Next',
              onTap: _playNext,
            ),
            _MenuItem(
              icon:  Icons.queue_music_rounded,
              label: 'Add to Queue',
              onTap: _addToQueue,
            ),
            _MenuItem(
              icon:  Icons.album_rounded,
              label: 'Go to Album',
              onTap: _t.albumId?.isNotEmpty == true ? _goToAlbum : null,
            ),
            _MenuItem(
              icon:  Icons.person_outline_rounded,
              label: 'Go to Artist',
              onTap: _t.artistId?.isNotEmpty == true ? _goToArtist : null,
            ),
            _MenuItem(
              icon:  downloaded
                  ? Icons.download_done_rounded
                  : (_downloading ? Icons.hourglass_top_rounded : Icons.download_outlined),
              label: downloaded ? 'Downloaded' : (_downloading ? 'Downloading…' : 'Download'),
              onTap: downloaded || _downloading ? null : _download,
            ),
            _MenuItem(
              icon:  Icons.ios_share_rounded,
              label: _sharing ? 'Preparing…' : 'Share',
              trailing: _sharing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Color(0xFFAAAAAA), strokeWidth: 2))
                  : null,
              onTap: _sharing ? null : _share,
            ),
            _MenuItem(
              icon:  Icons.remove_circle_outline_rounded,
              label: 'Remove from ViBE Out',
              color: const Color(0xFFFF5252),
              onTap: _removeFromVibeOut,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback? onTap;
  final Color?       color;
  final Widget?      trailing;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    final dim = onTap == null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: dim ? 0.4 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: c, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Text(label,
                  style: TextStyle(
                    color:      c,
                    fontSize:   15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

// ── Share card ────────────────────────────────────────────────────────────────
// Draws a 600×300 branded card using Canvas + PictureRecorder.
// No widget mounting required — works from any async context.

Future<String?> _buildShareCard(VibeTrack track, Color accent) async {
  const w = 600.0, h = 300.0;
  const artSize = h;
  const textLeft = artSize + 24.0;
  const textWidth = w - textLeft - 24.0;

  // Download album art
  ui.Image? artImage;
  try {
    final res = await http.get(Uri.parse(track.artworkUrl))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final codec = await ui.instantiateImageCodec(
          res.bodyBytes, targetWidth: artSize.toInt(), targetHeight: artSize.toInt());
      final frame = await codec.getNextFrame();
      artImage = frame.image;
    }
  } catch (_) {}

  final recorder = ui.PictureRecorder();
  final canvas   = Canvas(recorder);
  final paint    = Paint()..isAntiAlias = true;

  // Background
  paint.color = const Color(0xFF080810);
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);

  // Album art
  if (artImage != null) {
    canvas.drawImageRect(
      artImage,
      Rect.fromLTWH(0, 0, artImage.width.toDouble(), artImage.height.toDouble()),
      Rect.fromLTWH(0, 0, artSize, artSize),
      paint,
    );
    // Fade edge so art blends into background
    paint.shader = const LinearGradient(
      colors: [Colors.transparent, Color(0xFF080810)],
      begin:  Alignment.centerLeft,
      end:    Alignment.centerRight,
    ).createShader(Rect.fromLTWH(artSize * 0.55, 0, artSize * 0.45, h));
    canvas.drawRect(Rect.fromLTWH(artSize * 0.55, 0, artSize * 0.45, h), paint);
    paint.shader = null;
  }

  // Accent bar at top
  paint.color = accent;
  canvas.drawRect(Rect.fromLTWH(0, 0, w, 3), paint);

  // Helper: draw a text paragraph
  void drawText(
    String text,
    double x,
    double y, {
    double fontSize = 14,
    ui.FontWeight fontWeight = ui.FontWeight.normal,
    Color color = Colors.white,
    double maxWidth = textWidth,
    int maxLines = 2,
  }) {
    final pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign:       TextAlign.left,
        fontSize:        fontSize,
        fontWeight:      fontWeight,
        maxLines:        maxLines,
        ellipsis:        '…',
      ),
    )
      ..pushStyle(ui.TextStyle(
        color:      color,
        fontSize:   fontSize,
        fontWeight: fontWeight,
      ))
      ..addText(text);
    final para = pb.build()..layout(ui.ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(para, Offset(x, y));
  }

  // "ViBE" brand label (small, dim)
  drawText('ViBE', textLeft, 22,
    fontSize: 12,
    fontWeight: ui.FontWeight.w700,
    color: const Color(0xFF7C3AED),
    maxLines: 1,
  );

  // Track title
  drawText(track.title, textLeft, 50,
    fontSize: 22,
    fontWeight: ui.FontWeight.w700,
    color: Colors.white,
    maxLines: 2,
  );

  // Artist
  drawText(track.artist, textLeft, 108,
    fontSize: 15,
    color: const Color(0xFFAAAAAA),
    maxLines: 1,
  );

  // Tagline
  drawText('ViBE out to this track', textLeft, 175,
    fontSize: 13,
    fontWeight: ui.FontWeight.w600,
    color: Color.lerp(accent, Colors.white, 0.5)!,
    maxLines: 1,
  );

  // Footer
  drawText('playvibemusic.com', textLeft, h - 34,
    fontSize: 11,
    color: const Color(0xFF555566),
    maxLines: 1,
  );

  final picture = recorder.endRecording();
  final image   = await picture.toImage(w.toInt(), h.toInt());
  final bytes   = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) return null;

  final tmp  = await getTemporaryDirectory();
  final file = File('${tmp.path}/vibe_share_${track.id}.png');
  await file.writeAsBytes(bytes.buffer.asUint8List());
  return file.path;
}
