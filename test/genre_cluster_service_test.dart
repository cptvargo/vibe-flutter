import 'package:flutter_test/flutter_test.dart';
import 'package:vibe/services/genre_cluster_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> album(List<String> genres, {String artist = 'A'}) => {
  'Genres': genres,
  'AlbumArtist': artist,
  'AlbumArtists': [{'Id': artist, 'Name': artist}],
  'Id': '${artist}_album',
};

void main() {
  setUp(() => GenreClusterService.invalidate());
  tearDown(() => GenreClusterService.invalidate());

  // ── Basic clustering ───────────────────────────────────────────────────────

  group('empty library', () {
    test('produces no clusters', () {
      GenreClusterService.buildFromAlbums([]);
      expect(GenreClusterService.clusterFor({'lofi'}), isNull);
    });

    test('nothing is generic', () {
      GenreClusterService.buildFromAlbums([]);
      expect(GenreClusterService.isGeneric('music'), isFalse);
    });
  });

  group('single album, single genre', () {
    test('creates one cluster containing that genre', () {
      GenreClusterService.buildFromAlbums([album(['lofi'])]);
      final c = GenreClusterService.clusterFor({'lofi'});
      expect(c, isNotNull);
      expect(c!.containsGenre('lofi'), isTrue);
    });
  });

  group('co-occurring genres form one cluster', () {
    test('christian rap + christian hip-hop on same album → one cluster', () {
      GenreClusterService.buildFromAlbums([
        album(['christian rap', 'christian hip-hop']),
        album(['christian rap']),
      ]);
      final c1 = GenreClusterService.clusterFor({'christian rap'});
      final c2 = GenreClusterService.clusterFor({'christian hip-hop'});
      expect(c1, isNotNull);
      expect(c2, isNotNull);
      // Same cluster object won't be identical, but both genres are in the same group.
      expect(c1!.containsGenre('christian hip-hop'), isTrue);
      expect(c2!.containsGenre('christian rap'), isTrue);
    });

    test('three genres co-occurring → all in one cluster', () {
      GenreClusterService.buildFromAlbums([
        album(['lofi', 'chillhop', 'instrumental hip-hop']),
      ]);
      final c = GenreClusterService.clusterFor({'lofi'});
      expect(c, isNotNull);
      expect(c!.containsGenre('chillhop'), isTrue);
      expect(c.containsGenre('instrumental hip-hop'), isTrue);
    });
  });

  group('non-co-occurring genres form separate clusters', () {
    test('rap albums and worship albums → two distinct clusters', () {
      GenreClusterService.buildFromAlbums([
        album(['christian rap'], artist: 'RapArtist'),
        album(['christian rap'], artist: 'RapArtist2'),
        album(['contemporary christian'], artist: 'WorshipArtist'),
        album(['worship'], artist: 'WorshipArtist2'),
      ]);

      final rapCluster     = GenreClusterService.clusterFor({'christian rap'});
      final worshipCluster = GenreClusterService.clusterFor({'contemporary christian'});

      expect(rapCluster, isNotNull);
      expect(worshipCluster, isNotNull);

      // The rap cluster must NOT contain worship genres.
      expect(rapCluster!.containsGenre('contemporary christian'), isFalse);
      expect(rapCluster.containsGenre('worship'), isFalse);

      // The worship cluster must NOT contain rap genres.
      expect(worshipCluster!.containsGenre('christian rap'), isFalse);
    });

    test('lofi cluster is separate from synthwave cluster', () {
      GenreClusterService.buildFromAlbums([
        album(['lofi', 'chillhop']),
        album(['synthwave', 'retrowave']),
      ]);

      final lofi  = GenreClusterService.clusterFor({'lofi'});
      final synth = GenreClusterService.clusterFor({'synthwave'});

      expect(lofi,  isNotNull);
      expect(synth, isNotNull);
      expect(lofi!.containsGenre('synthwave'),  isFalse);
      expect(synth!.containsGenre('lofi'),      isFalse);
    });

    test('drum and bass cluster stays separate from worship', () {
      GenreClusterService.buildFromAlbums([
        album(['drum and bass', 'dnb']),
        album(['christian drum and bass', 'drum and bass']),
        album(['contemporary christian', 'worship']),
      ]);

      final dnb     = GenreClusterService.clusterFor({'drum and bass'});
      final worship = GenreClusterService.clusterFor({'contemporary christian'});

      expect(dnb!.containsGenre('dnb'), isTrue);
      expect(dnb.containsGenre('contemporary christian'), isFalse);
      expect(worship!.containsGenre('drum and bass'), isFalse);
    });
  });

  // ── Generic genre detection ────────────────────────────────────────────────

  group('generic genre detection', () {
    test('genre on every album is marked generic', () {
      GenreClusterService.buildFromAlbums([
        album(['music', 'lofi']),
        album(['music', 'synthwave']),
        album(['music', 'christian rap']),
      ]);
      expect(GenreClusterService.isGeneric('music'), isTrue);
    });

    test('genre on < 40 % of albums is NOT generic', () {
      // lofi on 1 of 5 albums = 20 %
      GenreClusterService.buildFromAlbums([
        album(['lofi']),
        album(['synthwave']),
        album(['drum and bass']),
        album(['christian rap']),
        album(['worship']),
      ]);
      expect(GenreClusterService.isGeneric('lofi'), isFalse);
    });

    test('generic genres are excluded from clusters', () {
      // 'music' appears on all 3 albums — it's generic.
      // 'lofi' appears on 1 album — it forms its own cluster.
      GenreClusterService.buildFromAlbums([
        album(['music', 'lofi']),
        album(['music', 'synthwave']),
        album(['music', 'worship']),
      ]);
      expect(GenreClusterService.isGeneric('music'), isTrue);
      // lofi cluster should NOT contain 'music'
      final c = GenreClusterService.clusterFor({'lofi'});
      expect(c, isNotNull);
      expect(c!.containsGenre('music'), isFalse);
    });

    test('track whose only genre is generic passes through filter', () {
      GenreClusterService.buildFromAlbums([
        album(['music', 'lofi']),
        album(['music', 'synthwave']),
        album(['music']),
      ]);
      // A track tagged only 'music' should be isGeneric → true
      expect(GenreClusterService.isGeneric('music'), isTrue);
    });
  });

  // ── Case & whitespace normalisation ───────────────────────────────────────

  group('normalisation', () {
    test('genre matching is case-insensitive', () {
      GenreClusterService.buildFromAlbums([album(['Christian Rap'])]);
      expect(GenreClusterService.clusterFor({'christian rap'}), isNotNull);
      expect(GenreClusterService.clusterFor({'CHRISTIAN RAP'}), isNotNull);
    });

    test('genre matching trims whitespace', () {
      GenreClusterService.buildFromAlbums([album(['  lofi  '])]);
      expect(GenreClusterService.clusterFor({'lofi'}), isNotNull);
    });

    test('isGeneric is case-insensitive', () {
      GenreClusterService.buildFromAlbums([
        album(['Music', 'lofi']),
        album(['music', 'synthwave']),
        album(['MUSIC', 'worship']),
      ]);
      expect(GenreClusterService.isGeneric('MUSIC'), isTrue);
      expect(GenreClusterService.isGeneric('music'), isTrue);
    });
  });

  // ── clusterFor edge cases ──────────────────────────────────────────────────

  group('clusterFor', () {
    test('returns null for empty genre set', () {
      GenreClusterService.buildFromAlbums([album(['lofi'])]);
      expect(GenreClusterService.clusterFor({}), isNull);
    });

    test('returns null when no cluster matches', () {
      GenreClusterService.buildFromAlbums([album(['lofi'])]);
      expect(GenreClusterService.clusterFor({'jazz'}), isNull);
    });

    test('returns null before any build call', () {
      // invalidate() was called in setUp — cache is empty
      expect(GenreClusterService.clusterFor({'lofi'}), isNull);
    });

    test('matchesAny works with a mix of known and unknown genres', () {
      GenreClusterService.buildFromAlbums([album(['lofi', 'chillhop'])]);
      final c = GenreClusterService.clusterFor({'lofi', 'unknown-genre'});
      expect(c, isNotNull);
    });
  });

  // ── Cache behaviour ────────────────────────────────────────────────────────

  group('cache', () {
    test('invalidate clears clusters', () {
      GenreClusterService.buildFromAlbums([album(['lofi'])]);
      expect(GenreClusterService.clusterFor({'lofi'}), isNotNull);

      GenreClusterService.invalidate();
      expect(GenreClusterService.clusterFor({'lofi'}), isNull);
    });

    test('buildFromAlbums no-ops when cache already warm', () {
      GenreClusterService.buildFromAlbums([album(['lofi'])]);
      // Second call with different data should be ignored.
      GenreClusterService.buildFromAlbums([album(['synthwave'])]);
      // Lofi cluster still present, synthwave cluster was not added.
      expect(GenreClusterService.clusterFor({'lofi'}), isNotNull);
    });

    test('invalidate then rebuild picks up new data', () {
      GenreClusterService.buildFromAlbums([album(['lofi'])]);
      GenreClusterService.invalidate();
      GenreClusterService.buildFromAlbums([album(['synthwave'])]);
      expect(GenreClusterService.clusterFor({'synthwave'}), isNotNull);
      expect(GenreClusterService.clusterFor({'lofi'}), isNull);
    });
  });

  // ── Real-world genre scenarios ─────────────────────────────────────────────

  group('real-world library scenarios', () {
    test('mixed Christian library → rap and worship stay separate', () {
      GenreClusterService.buildFromAlbums([
        album(['christian', 'christian rap', 'hip-hop'], artist: 'Godfearin'),
        album(['christian', 'christian rap'], artist: 'KB'),
        album(['christian', 'contemporary christian', 'worship'], artist: 'BryanKatie'),
        album(['christian', 'ccm'], artist: 'Elevation'),
      ]);

      expect(GenreClusterService.isGeneric('christian'), isTrue);

      final rap     = GenreClusterService.clusterFor({'christian rap'});
      final worship = GenreClusterService.clusterFor({'contemporary christian'});

      expect(rap,     isNotNull);
      expect(worship, isNotNull);
      expect(rap!.containsGenre('contemporary christian'), isFalse);
      expect(worship!.containsGenre('christian rap'), isFalse);
    });

    test('lofi + synthwave + dnb all form independent clusters', () {
      GenreClusterService.buildFromAlbums([
        album(['lofi', 'chillhop']),
        album(['lofi']),
        album(['synthwave', 'outrun']),
        album(['drum and bass', 'dnb']),
        album(['christian drum and bass', 'drum and bass']),
      ]);

      final lofi  = GenreClusterService.clusterFor({'lofi'});
      final synth = GenreClusterService.clusterFor({'synthwave'});
      final dnb   = GenreClusterService.clusterFor({'drum and bass'});

      expect(lofi,  isNotNull);
      expect(synth, isNotNull);
      expect(dnb,   isNotNull);

      expect(lofi!.containsGenre('synthwave'), isFalse);
      expect(synth!.containsGenre('drum and bass'), isFalse);
      expect(dnb!.containsGenre('lofi'), isFalse);

      // Christian DnB should be in the DnB cluster (co-occurs on same album)
      expect(dnb.containsGenre('christian drum and bass'), isTrue);
    });

    test('jazz library clusters smooth jazz and bebop together', () {
      GenreClusterService.buildFromAlbums([
        album(['jazz', 'smooth jazz']),
        album(['jazz', 'bebop']),
        album(['jazz', 'fusion']),
      ]);

      // 'jazz' on all 3 of 3 albums = 100 % → generic
      expect(GenreClusterService.isGeneric('jazz'), isTrue);

      // Sub-genres don't co-occur together so they each form separate clusters
      // (smooth jazz only on album 1, bebop only on album 2, fusion only on 3).
      final smooth = GenreClusterService.clusterFor({'smooth jazz'});
      final bebop  = GenreClusterService.clusterFor({'bebop'});
      expect(smooth, isNotNull);
      expect(bebop,  isNotNull);
      expect(smooth!.containsGenre('bebop'), isFalse);
    });
  });
}
