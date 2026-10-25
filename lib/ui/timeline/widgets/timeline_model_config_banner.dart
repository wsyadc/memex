import 'package:flutter/material.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/user_storage.dart';

class TimelineModelConfigBanner extends StatefulWidget {
  const TimelineModelConfigBanner({super.key, required this.onConfigureTap});

  final Future<void> Function() onConfigureTap;

  @override
  State<TimelineModelConfigBanner> createState() =>
      _TimelineModelConfigBannerState();
}

class _TimelineModelConfigBannerState extends State<TimelineModelConfigBanner>
    with WidgetsBindingObserver {
  bool _showBanner = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    EventBusService.instance.addHandler(
      EventBusMessageType.llmConfigChanged,
      _handleLLMConfigChanged,
    );
    _checkModelConfig();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    EventBusService.instance.removeHandler(
      EventBusMessageType.llmConfigChanged,
      _handleLLMConfigChanged,
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkModelConfig();
    }
  }

  Future<void> _checkModelConfig() async {
    final configs = await UserStorage.getLLMConfigs();
    final defaultKey = await UserStorage.getDefaultLLMConfigKey();
    final hasValid = configs.any((config) =>
        config.key == defaultKey &&
        config.type != LLMConfig.typeMemex &&
        config.isValid);
    if (mounted && !hasValid != _showBanner) {
      setState(() => _showBanner = !hasValid);
    }
  }

  void _handleLLMConfigChanged(EventBusMessage message) {
    if (!mounted) return;
    _checkModelConfig();
  }

  Future<void> _openModelConfig() async {
    await widget.onConfigureTap();
    await _checkModelConfig();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showBanner) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: GestureDetector(
        onTap: _openModelConfig,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.92),
                Colors.white.withValues(alpha: 0.82),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF818CF8),
                      Color(0xFF6366F1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UserStorage.l10n.configureNow,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      UserStorage.l10n.modelNotConfiguredBanner,
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFF64748B).withValues(alpha: 0.9),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: Color(0xFF6366F1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
