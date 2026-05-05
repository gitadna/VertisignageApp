import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../data/announcement_overlay_notifier.dart';

class AnnouncementTickerLayer extends StatelessWidget {
  const AnnouncementTickerLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sl<AnnouncementOverlayNotifier>(),
      builder: (context, _) {
        final n = sl<AnnouncementOverlayNotifier>();
        if (!n.isActive || n.mode != AnnouncementRenderMode.ticker) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.campaign_outlined, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [n.title, n.body].whereType<String>().where((t) => t.trim().isNotEmpty).join(' — '),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
