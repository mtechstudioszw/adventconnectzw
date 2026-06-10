import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'messaging_service.dart';

/// A voice note to play — identified by its message id, with the private
/// storage path the bytes live at.
class VoiceNote {
  const VoiceNote({
    required this.messageId,
    required this.storagePath,
    this.durationSeconds,
    this.conversationId,
  });

  final String messageId;
  final String storagePath;
  final int? durationSeconds;
  // The chat this note belongs to — lets the global mini-bar hide itself
  // while the user is actually viewing that chat (the bubble is enough).
  final String? conversationId;
}

/// Given the currently-finished note's id, return the next one to play
/// (or null to stop). The chat screen wires this so playback rolls on to
/// the next voice note like WhatsApp.
typedef VoiceQueueResolver = VoiceNote? Function(String currentMessageId);

/// App-wide single voice-note player.
///
/// Why a singleton instead of a player per bubble:
///   * Only ONE note plays at a time (starting another stops the first).
///   * Playback survives leaving the chat screen ("play audio outside the
///     chat") — the player isn't disposed with the widget.
///   * The 30-second cut-out bug: bubbles streamed the note over a signed
///     URL (`UrlSource`), which audioplayers truncates on Android. We now
///     DOWNLOAD the file once to a permanent cache and play it from disk
///     (`DeviceFileSource`) — reliable full-length playback, and it never
///     re-downloads on replay (WhatsApp parity).
class VoicePlayerService {
  VoicePlayerService._() {
    _wire();
  }
  static final VoicePlayerService instance = VoicePlayerService._();

  final AudioPlayer _player = AudioPlayer();

  /// messageId -> absolute local file path of the downloaded clip.
  final Map<String, String> _localCache = {};

  // Observable state — widgets listen to just what they need.
  final ValueNotifier<String?> activeId = ValueNotifier(null);
  final ValueNotifier<String?> loadingId = ValueNotifier(null);
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);
  final ValueNotifier<double> speed = ValueNotifier(1.0);
  // The conversation the active note belongs to, and which chat (if any)
  // is currently on screen. The global mini-bar shows only when these
  // differ — i.e. a note is playing while you're NOT in its chat.
  final ValueNotifier<String?> activeConversationId = ValueNotifier(null);
  static final ValueNotifier<String?> openChatId = ValueNotifier(null);

  /// Set by the chat screen to enable continuous play; cleared on leave.
  VoiceQueueResolver? nextResolver;

  void _wire() {
    _player.onPositionChanged.listen((p) => position.value = p);
    _player.onDurationChanged.listen((d) {
      if (d > Duration.zero) duration.value = d;
    });
    _player.onPlayerStateChanged.listen((s) {
      playing.value = s == PlayerState.playing;
    });
    _player.onPlayerComplete.listen((_) async {
      position.value = Duration.zero;
      playing.value = false;
      final current = activeId.value;
      final resolver = nextResolver;
      if (current != null && resolver != null) {
        final next = resolver(current);
        if (next != null) {
          await play(next);
          return;
        }
      }
      // No next note: DON'T dismiss — keep the bar/bubble visible, paused
      // at the start, so the user can replay or scrub. Only the X button
      // (stop()) tears it down. WhatsApp parity.
    });
  }

  bool isActive(String messageId) => activeId.value == messageId;

  /// Play/pause/resume toggle for [note].
  Future<void> toggle(VoiceNote note) async {
    if (activeId.value == note.messageId) {
      if (playing.value) {
        await _player.pause();
      } else {
        await _player.resume();
      }
      return;
    }
    await play(note);
  }

  Future<void> play(VoiceNote note) async {
    await _player.stop();
    activeId.value = note.messageId;
    activeConversationId.value = note.conversationId;
    position.value = Duration.zero;
    duration.value = Duration(seconds: note.durationSeconds ?? 0);
    try {
      loadingId.value = note.messageId;
      final path = await _ensureLocal(note);
      loadingId.value = null;
      await _player.setPlaybackRate(speed.value);
      await _player.play(DeviceFileSource(path));
    } catch (e) {
      loadingId.value = null;
      activeId.value = null;
      rethrow;
    }
  }

  /// Download-once cache. Keeps the clip in the app documents dir keyed
  /// by message id, so replays (and replays after an app restart) never
  /// hit the network again.
  Future<String> _ensureLocal(VoiceNote note) async {
    final cached = _localCache[note.messageId];
    if (cached != null && File(cached).existsSync()) return cached;

    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/voice_cache');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
    final safe = note.messageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${cacheDir.path}/$safe.m4a');

    if (file.existsSync() && file.lengthSync() > 0) {
      _localCache[note.messageId] = file.path;
      return file.path;
    }

    final bytes = await MessagingService.downloadVoiceBytes(note.storagePath);
    await file.writeAsBytes(bytes, flush: true);
    _localCache[note.messageId] = file.path;
    return file.path;
  }

  Future<void> seekFraction(double fraction) async {
    final total = duration.value;
    if (total <= Duration.zero) return;
    final ms = (total.inMilliseconds * fraction.clamp(0.0, 1.0)).round();
    await _player.seek(Duration(milliseconds: ms));
  }

  /// Cycle 1x -> 1.5x -> 2x -> 1x, applied live.
  Future<void> cycleSpeed() async {
    const steps = [1.0, 1.5, 2.0];
    final idx = steps.indexOf(speed.value);
    final next = steps[(idx + 1) % steps.length];
    speed.value = next;
    await _player.setPlaybackRate(next);
  }

  Future<void> pause() => _player.pause();

  Future<void> resume() => _player.resume();

  /// Fully stop playback and dismiss the mini-bar.
  Future<void> stop() async {
    await _player.stop();
    playing.value = false;
    position.value = Duration.zero;
    activeId.value = null;
    activeConversationId.value = null;
  }

  /// Called when the conversation is left. Stops continuous-play hand-off
  /// but deliberately does NOT stop playback — a note in progress keeps
  /// playing outside the chat.
  void detachResolver(VoiceQueueResolver resolver) {
    if (nextResolver == resolver) nextResolver = null;
  }
}
