import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/player_notifier.dart';

class TrackSelectionSheet extends ConsumerWidget {
  const TrackSelectionSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);

    // Limit height to 60% of screen to avoid taking over too much space
    final height = MediaQuery.of(context).size.height * 0.6;

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Drag handle or subtle indicator
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subtitles (Left)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, 'Subtitles'),
                      Expanded(
                        child: _buildTrackList(
                          context,
                          tracks: state.subtitleTracks,
                          currentId: state.currentSubtitleTrack,
                          onSelect: notifier.setSubtitleTrack,
                          icon: Icons.subtitles,
                        ),
                      ),
                    ],
                  ),
                ),
                // Vertical Divider
                const VerticalDivider(width: 1, color: Colors.white24),
                // Audio (Right)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, 'Audio'),
                      Expanded(
                        child: _buildTrackList(
                          context,
                          tracks: state.audioTracks,
                          currentId: state.currentAudioTrack,
                          onSelect: notifier.setAudioTrack,
                          icon: Icons.audiotrack,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTrackList(
    BuildContext context, {
    required Map<int, String> tracks,
    required int? currentId,
    required Function(int) onSelect,
    required IconData icon,
  }) {
    if (tracks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text('None available', style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final id = tracks.keys.elementAt(index);
        final name = tracks[id]!;
        final isSelected = id == currentId;

        return ListTile(
          leading: Icon(
            icon,
            color: isSelected ? Colors.blue : Colors.white54,
            size: 20,
          ),
          title: Text(
            name,
            style: TextStyle(
              color: isSelected ? Colors.blue : Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          trailing: isSelected
              ? const Icon(Icons.check, color: Colors.blue, size: 20)
              : null,
          onTap: () {
            onSelect(id);
          },
        );
      },
    );
  }
}
