import 'package:audioplayers/audioplayers.dart';

enum SeSoundIds { send }

class SeSound {
  final Map<SeSoundIds, AudioPlayer> _players = {
    SeSoundIds.send: AudioPlayer(),
  };

  SeSound() {
    for (final p in _players.values) {
      p.setReleaseMode(ReleaseMode.stop);
    }
  }

  void playSe(SeSoundIds id) async {
    final player = _players[id];
    if (player == null) return;
    await player.stop();
    await player.play(AssetSource('se/send.mp3'));
  }

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
  }
}
