import 'package:flutter/material.dart';

import '../../ui/external_link.dart';
import '../legacy_yanhekt.dart';
import 'study_live_player.dart';

class LegacyLiveScreen extends StatelessWidget {
  const LegacyLiveScreen({super.key, required this.item, this.courseAction});
  final LegacyLive item;
  final Widget? courseAction;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(item.title), actions: [?courseAction]),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(item.location),
                const SizedBox(height: 16),
                StudyLivePlayer(
                  initialStatus: item.status,
                  load: (cancel) =>
                      LegacyYanhektRepository().streams(item.id, cancel),
                  endedAction: TextButton(
                    onPressed: () => openExternalLink(
                      context,
                      Uri.https('www.yanhekt.cn'),
                      failureTitle: '无法打开延河课堂',
                    ),
                    child: const Text('打开延河课堂'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
