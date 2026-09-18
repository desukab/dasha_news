/// The desk's queue.
///
/// Four tabs: what needs a person, everything, what the desk wrote by hand,
/// and what the automated newsroom gave up on. The counts in the pipeline tab
/// come from the health endpoint, so the badge reflects the server's state
/// rather than a local guess.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dasha_editor/models/story.dart';
import 'package:dasha_editor/state/session_state.dart';
import 'package:dasha_editor/state/workqueue_state.dart';
import 'package:dasha_editor/ui/pipeline_page.dart';
import 'package:dasha_editor/ui/story_detail_page.dart';
import 'package:dasha_editor/ui/story_edit_page.dart';
import 'package:dasha_editor/ui/theme.dart';
import 'package:dasha_editor/ui/widgets.dart';

class WorkQueuePage extends StatefulWidget {
  const WorkQueuePage({super.key});

  @override
  State<WorkQueuePage> createState() => _WorkQueuePageState();
}

class _WorkQueuePageState extends State<WorkQueuePage> with TickerProviderStateMixin {
  late final TabController _tabs;
  PipelineHealth? _health;

  static const _queueTabs = [
    WorkQueueTab.attention,
    WorkQueueTab.all,
    WorkQueueTab.manual,
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging || _tabs.index >= _queueTabs.length) return;
      context.read<WorkQueueState>().selectTab(_queueTabs[_tabs.index]);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WorkQueueState>().refresh();
      _refreshHealth();
    });
  }

  void _refreshHealth() {
    context.read<SessionState>().client.pipelineHealth().then((health) {
      if (mounted) setState(() => _health = health);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Newsroom queue'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            const Tab(text: 'Needs attention'),
            const Tab(text: 'All stories'),
            const Tab(text: 'Written by hand'),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Pipeline'),
                if (_health?.needsAttention ?? false) ...[
                  const SizedBox(width: 6),
                  const Badge(label: Text('!')),
                ]
              ]),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () => context.read<SessionState>().logout(),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _queue(emptyText: 'Nothing is waiting on a person.'),
          _queue(emptyText: 'The queue is empty.'),
          _queue(emptyText: 'No story has been written by hand yet.'),
          PipelinePage(onRetried: _refreshHealth),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final queue = context.read<WorkQueueState>();
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StoryEditPage()),
          );
          if (mounted) queue.refresh();
        },
        icon: const Icon(Icons.edit),
        label: const Text('Write a story'),
      ),
    );
  }

  Widget _queue({required String emptyText}) {
    return Consumer<WorkQueueState>(
      builder: (context, queue, _) {
        if (queue.loading) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (queue.error != null && queue.items.isEmpty) {
          return QueueMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not reach the newsroom',
            detail: queue.error!,
            action: TextButton(onPressed: queue.refresh, child: const Text('Retry')),
          );
        }
        if (queue.items.isEmpty) {
          return QueueMessage(icon: Icons.check_circle_outline, title: emptyText);
        }
        return RefreshIndicator(
          onRefresh: queue.refresh,
          child: ListView.builder(
            itemCount: queue.items.length + (queue.canLoadMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= queue.items.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: TextButton(
                      onPressed: queue.loadMore,
                      child: const Text('Load more'),
                    ),
                  ),
                );
              }
              return _StoryQueueRow(story: queue.items[index]);
            },
          ),
        );
      },
    );
  }
}

class _StoryQueueRow extends StatelessWidget {
  const _StoryQueueRow({required this.story});

  final StoryDetail story;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => StoryDetailPage(storyId: story.id)),
          );
          if (context.mounted) context.read<WorkQueueState>().refresh();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.headlineIn('te'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatusChip(story.status, color: statusColor(story.status)),
                        if (story.editorLocked) const StatusChip('editor hold', color: Color(0xFF8A6D1F)),
                        if (story.needsReview) const StatusChip('needs review', color: Color(0xFFB3261E)),
                        if (story.isBreaking) const StatusChip('breaking', color: Color(0xFFB3261E)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${story.numSources} source(s) · evidence ${story.evidenceScore.toStringAsFixed(2)}'
                      '${story.district != null ? ' · ${story.district}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
