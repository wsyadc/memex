import 'package:flutter/material.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/settings/widgets/model_config_edit_page.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/utils/toast_helper.dart';

/// A single active model shared by capture and journal organization.
/// Saved configurations remain on disk when the active model changes.
class ModelConfigListPage extends StatefulWidget {
  const ModelConfigListPage(
      {super.key,
      this.popOnConfigSaved = false,
      this.autoOpenFirstConfig = false,
      this.simpleSetupMode = true});
  final bool popOnConfigSaved;
  final bool autoOpenFirstConfig;
  final bool simpleSetupMode;
  @override
  State<ModelConfigListPage> createState() => _ModelConfigListPageState();
}

class _ModelConfigListPageState extends State<ModelConfigListPage> {
  LLMConfig? _config;
  bool _loading = true;
  bool _openedInitialConfig = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final router = MemexRouter();
      final configs = (await router.getLLMConfigs())
          .where((config) => config.type != LLMConfig.typeMemex)
          .toList();
      final defaultKey = await router.getDefaultLLMConfigKey();
      LLMConfig? selected;
      for (final config in configs) {
        if (config.key == defaultKey) selected = config;
      }
      selected ??= configs.where((config) => config.isValid).firstOrNull ??
          configs.firstOrNull;
      if (!mounted) return;
      setState(() {
        _config = selected;
        _loading = false;
        _error = null;
      });
      if (widget.autoOpenFirstConfig && !_openedInitialConfig) {
        _openedInitialConfig = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _edit();
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _edit() async {
    final key = await Navigator.push<String>(
        context,
        MaterialPageRoute(
            builder: (_) => ModelConfigEditPage(
                config: _config,
                isDefaultConfig: true,
                simpleSetupMode: true)));
    if (key == null || !mounted) return;
    try {
      await MemexRouter().setDefaultLLMConfigKey(key);
      if (!mounted) return;
      if (widget.popOnConfigSaved) {
        Navigator.pop(context, key);
      } else {
        await _load();
      }
    } catch (error) {
      if (mounted) ToastHelper.showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
          title: Text(l10n.modelConfiguration),
          backgroundColor: const Color(0xFFF7F8FA)),
      body: _loading
          ? const Center(child: AgentLogoLoading())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 16),
                const Icon(Icons.auto_awesome_outlined,
                    size: 44, color: Color(0xFF6366F1)),
                const SizedBox(height: 24),
                Text(l10n.journalModelHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, color: Color(0xFF64748B))),
                const SizedBox(height: 24),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                _config?.modelId.isNotEmpty == true
                                    ? _config!.modelId
                                    : l10n.journalModelEmpty,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w600)),
                            if (_config != null) ...[
                              const SizedBox(height: 10),
                              Text(_config!.type,
                                  style: const TextStyle(
                                      fontSize: 13, color: Color(0xFF94A3B8))),
                            ],
                            const SizedBox(height: 24),
                            SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                    onPressed: _edit,
                                    icon: const Icon(Icons.tune_rounded,
                                        size: 18),
                                    label: Text(l10n.modelConfig))),
                          ])),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  TextButton(onPressed: _load, child: Text(l10n.retry)),
                ],
              ],
            ),
    );
  }
}
