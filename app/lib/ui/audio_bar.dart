import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_strings.dart';
import '../core/format.dart';
import '../state/app_state.dart';
import '../state/audio_controller.dart';
import 'router.dart';

/// A slim, persistent transport shown above the tab bar while something is
/// (or was recently) playing. It exists on every screen so audio never traps
/// the reader in one tab.
class AudioBar extends StatelessWidget {
  const AudioBar({super.key});

  static const double height = 58;

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final story = audio.nowPlaying;

    if (story == null) {
      return const SizedBox.shrink();
    }

    final title = story.headline(app.locale);
    return Material(
      elevation: 6,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _toggle(context, audio),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openStory(context, story.id),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                                height: hasTeluguScript(title) ? 1.4 : 1.2,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _progress(audio),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                _stop(context, audio, app.strings),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggle(BuildContext context, AudioController audio) {
    if (audio.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      icon: Icon(audio.isPlaying
          ? Icons.pause_rounded
          : Icons.play_arrow_rounded),
      iconSize: 30,
      onPressed: audio.isPlaying ? audio.pause : audio.resume,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  Widget _stop(BuildContext context, AudioController audio, AppStrings strings) {
    return IconButton(
      icon: const Icon(Icons.close_rounded),
      iconSize: 20,
      tooltip: strings.pause,
      onPressed: audio.stop,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  String _progress(AudioController audio) {
    final done = _mmss(audio.position);
    if (audio.duration.inSeconds > 0) {
      return '$done / ${_mmss(audio.duration)}';
    }
    return done;
  }

  String _mmss(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  void _openStory(BuildContext context, int storyId) {
    Navigator.pushNamed(context, '/story',
        arguments: StoryDetailArgs(id: storyId));
  }
}
