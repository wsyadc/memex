import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/ui/settings/view_models/data_import_viewmodel.dart';
import 'package:memex/ui/settings/widgets/backup_restore_page.dart';
import 'package:memex/ui/settings/widgets/data_import_page.dart';
import 'package:memex/ui/settings/widgets/data_storage_page.dart';
import 'package:memex/ui/settings/widgets/debug_settings_screen.dart';
import 'package:memex/ui/settings/widgets/location_context_settings_page.dart';
import 'package:memex/ui/settings/widgets/model_config_list_page.dart';
import 'package:memex/utils/user_storage.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
          title: Text(l10n.settings), backgroundColor: const Color(0xFFF7F8FA)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: const Color(0xFFEDEEFF),
                borderRadius: BorderRadius.circular(24)),
            child: Row(children: [
              const Icon(Icons.menu_book_rounded,
                  size: 32, color: Color(0xFF6366F1)),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(l10n.journalTitle,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3730A3))),
                    const SizedBox(height: 6),
                    Text(l10n.journalSettingsSubtitle,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF777BA1))),
                  ])),
            ]),
          ),
          const SizedBox(height: 24),
          _SettingsRow(
              icon: Icons.auto_awesome_outlined,
              title: l10n.modelConfiguration,
              subtitle: l10n.journalModelHint,
              onTap: () => _open(context, const ModelConfigListPage())),
          _SettingsRow(
              icon: Icons.location_on_outlined,
              title: l10n.location,
              subtitle: l10n.locationContextDescription,
              onTap: () => _open(context, const LocationContextSettingsPage())),
          const SizedBox(height: 12),
          _SettingsRow(
              icon: Icons.phone_android_rounded,
              title: l10n.dataStorage,
              subtitle: l10n.journalLocalData,
              onTap: () => _open(context, const DataStoragePage())),
          _SettingsRow(
              icon: Icons.file_upload_outlined,
              title: l10n.dataImportTitle,
              subtitle: l10n.journalImportDescription,
              onTap: () => _open(
                  context,
                  DataImportPage(
                      viewModel: DataImportViewModel(router: MemexRouter())))),
          _SettingsRow(
              icon: Icons.backup_outlined,
              title: l10n.backupAndRestore,
              subtitle: l10n.automaticBackup,
              onTap: () => _open(context, const BackupRestorePage())),
          const SizedBox(height: 12),
          _SettingsRow(
              icon: Icons.terminal_rounded,
              title: l10n.debugging,
              subtitle: '${l10n.viewLogs} · ${l10n.asyncTaskList}',
              onTap: () => _open(context,
                  DebugSettingsScreen.forRouter(router: MemexRouter()))),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            leading: Icon(icon, color: const Color(0xFF6366F1), size: 23),
            title: Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, height: 1.5, color: Color(0xFF94A3B8)))),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFCBD5E1)),
            onTap: onTap,
          ),
        ),
      );
}
