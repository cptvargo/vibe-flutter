import 'dart:math';

/// Shuffles [items] so the same artist never appears within [minGap] positions
/// of themselves. Falls back to a plain shuffle when the queue is too small or
/// there are too few unique artists to enforce spacing.
///
/// [artistOf] extracts the artist string from each item (may return '').
List<T> smartShuffle<T>(List<T> items, String Function(T) artistOf) {
  if (items.length < 4) {
    return List<T>.from(items)..shuffle();
  }

  final result = List<T>.from(items)..shuffle();

  final uniqueArtists = result.map(artistOf).where((a) => a.isNotEmpty).toSet().length;
  final gap = min(uniqueArtists - 1, 5).clamp(1, 5);

  if (uniqueArtists < 2) return result;

  // Spacing pass: scan forward and swap same-artist tracks that are too close.
  for (int i = 1; i < result.length; i++) {
    final artist = artistOf(result[i]);
    if (artist.isEmpty) continue;

    // Check if this artist appeared within the last [gap] positions.
    bool tooClose = false;
    for (int k = max(0, i - gap); k < i; k++) {
      if (artistOf(result[k]) == artist) { tooClose = true; break; }
    }
    if (!tooClose) continue;

    // Find the nearest later track with a different artist and swap.
    for (int j = i + 1; j < result.length; j++) {
      if (artistOf(result[j]) != artist) {
        final tmp  = result[i];
        result[i]  = result[j];
        result[j]  = tmp;
        break;
      }
    }
  }

  return result;
}
