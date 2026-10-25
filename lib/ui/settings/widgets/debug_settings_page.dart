import 'package:flutter/material.dart';
import 'package:memex/ui/settings/widgets/agent_state_viewer_page.dart';
import 'package:memex/ui/settings/widgets/async_task_list_page.dart';
import 'package:memex/ui/settings/widgets/log_viewer_page.dart';
import 'package:memex/utils/user_storage.dart';

class DebugSettingsPage extends StatelessWidget {
  const DebugSettingsPage({
    super.key,
    Future<void> Function()? onClearToken,
    Future<void> Function()? onReprocessComments,
    bool isReprocessingComments = false,
    required this.onClearData,
    required this.onClearFailedAgentContexts,
    required this.onCloneToTestUser,
    required this.onReprocessCards,
    required this.onRebuildSearchIndex,
    required this.isClearingData,
    required this.isClearingFailedAgentContexts,
    required this.isCloningTestUser,
    required this.isReprocessingCards,
    required this.isRebuildingSearchIndex,
  });

  final Future<void> Function() onClearData;
  final Future<void> Function() onClearFailedAgentContexts;
  final Future<void> Function() onCloneToTestUser;
  final Future<void> Function() onReprocessCards;
  final Future<void> Function() onRebuildSearchIndex;
  final bool isClearingData;
  final bool isClearingFailedAgentContexts;
  final bool isCloningTestUser;
  final bool isReprocessingCards;
  final bool isRebuildingSearchIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    Widget item(IconData icon, String title, VoidCallback onTap,
            {bool busy = false}) =>
        Card(
          elevation: 0,
          color: Colors.white,
          child: ListTile(
            leading: Icon(icon, color: const Color(0xFF6366F1)),
            title: Text(title),
            trailing: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right_rounded),
            onTap: busy ? null : onTap,
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.debugging)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        item(Icons.receipt_long_outlined, l10n.viewLogs,
            () => open(const LogViewerPage())),
        item(Icons.pending_actions_rounded, l10n.asyncTaskList,
            () => open(const AsyncTaskListPage())),
        item(Icons.data_object_rounded, l10n.agentStates,
            () => open(const AgentStateViewerPage())),
        const SizedBox(height: 16),
        item(Icons.refresh_rounded, l10n.reprocessCards, onReprocessCards,
            busy: isReprocessingCards),
        item(Icons.manage_search_rounded, l10n.rebuildSearchIndex,
            onRebuildSearchIndex,
            busy: isRebuildingSearchIndex),
        item(Icons.cleaning_services_outlined, l10n.clearFailedAgentContexts,
            onClearFailedAgentContexts,
            busy: isClearingFailedAgentContexts),
        item(Icons.copy_all_outlined, l10n.cloneToTestUser, onCloneToTestUser,
            busy: isCloningTestUser),
        const SizedBox(height: 16),
        item(Icons.delete_outline_rounded, l10n.clearData, onClearData,
            busy: isClearingData),
      ]),
    );
  }
}
