import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/card_attachments/card_attachment_data.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/settings/widgets/model_config_list_page.dart';
import 'package:memex/ui/settings/widgets/settings_page.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/journal_entry_card.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';
import 'package:memex/ui/timeline/widgets/timeline_model_config_banner.dart';
import 'package:memex/utils/user_storage.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen(
      {super.key,
      required this.viewModel,
      this.onInputTap,
      this.onRefreshAction,
      this.insightViewModel,
      this.personaAvatarViewModel});

  final TimelineViewModel viewModel;
  final VoidCallback? onInputTap;
  final VoidCallback? onRefreshAction;
  // Kept as optional constructor compatibility for existing embeddings.
  final Object? insightViewModel;
  final Object? personaAvatarViewModel;

  @override
  State<TimelineScreen> createState() => TimelineScreenState();
}

class TimelineScreenState extends State<TimelineScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void scrollToTopAndRefresh() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    widget.viewModel.refresh();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 600) {
      widget.viewModel.loadMore();
    }
  }

  Future<void> _refresh() async {
    await widget.viewModel.refresh();
    widget.onRefreshAction?.call();
  }

  void _selectTag(String tag) {
    if (widget.viewModel.activeFilter == tag) return;
    widget.viewModel.setActiveFilter(tag);
    widget.viewModel.loadCards(refresh: true);
  }

  Future<void> _openCard(TimelineCardModel card) async {
    final result = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(
            builder: (_) => TimelineCardDetailScreen(cardId: card.id)));
    if (!mounted) return;
    if (result is Map && result['action'] == 'filter_tag') {
      _selectTag(result['tag'] as String);
    } else if (result == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.viewModel, widget.viewModel.load]),
      builder: (context, _) {
        final vm = widget.viewModel;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
            child: Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(l10n.journalTitle,
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                            letterSpacing: -0.5)),
                    const SizedBox(height: 5),
                    Text(l10n.journalSubtitle,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF94A3B8))),
                  ])),
              IconButton(
                  tooltip: l10n.calendar,
                  icon: const Icon(Icons.calendar_today_outlined, size: 21),
                  onPressed: () => context.push(AppRoutes.calendar)),
              IconButton(
                  tooltip: l10n.settings,
                  icon: const Icon(Icons.tune_rounded, size: 22),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()))),
            ]),
          ),
          TimelineModelConfigBanner(onConfigureTap: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ModelConfigListPage()));
          }),
          if (vm.tags.isNotEmpty)
            SizedBox(
                height: 44,
                child: TimelineFilterBar(
                    viewModel: vm, onTagSelected: _selectTag)),
          Expanded(child: _buildFeed(vm)),
        ]);
      },
    );
  }

  Widget _buildFeed(TimelineViewModel vm) {
    if ((vm.isLoading || vm.load.running) && vm.cards.isEmpty) {
      return const Center(child: AgentLogoLoading(size: 72));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: vm.cards.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(32, 90, 32, 120),
              children: [
                  Icon(
                      vm.errorMessage == null
                          ? Icons.menu_book_outlined
                          : Icons.error_outline_rounded,
                      size: 52,
                      color: const Color(0xFFB8BDD8)),
                  const SizedBox(height: 22),
                  Text(vm.errorMessage ?? UserStorage.l10n.journalEmpty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569))),
                  const SizedBox(height: 10),
                  Text(UserStorage.l10n.journalEmptyHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14, height: 1.6, color: Color(0xFF94A3B8))),
                  const SizedBox(height: 20),
                  Center(
                      child: TextButton(
                          onPressed: vm.errorMessage == null
                              ? widget.onInputTap
                              : _refresh,
                          child: Text(vm.errorMessage == null
                              ? UserStorage.l10n.journalCapture
                              : UserStorage.l10n.retry))),
                ])
          : ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              itemCount: vm.cards.length +
                  (vm.hasMore ? 1 : 0) +
                  (vm.errorMessage == null ? 0 : 1),
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (_, index) {
                if (index == vm.cards.length && vm.errorMessage != null) {
                  return ListTile(
                      title: Text(vm.errorMessage!),
                      trailing: IconButton(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh)));
                }
                if (index >= vm.cards.length) {
                  return const Center(
                      child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator()));
                }
                final card = vm.cards[index];
                return JournalEntryCard(
                    key: ValueKey(card.id),
                    card: card,
                    onTap: () => _openCard(card),
                    onTagTap: _selectTag);
              },
            ),
    );
  }
}

/// Compatibility wrapper for views which embed a timeline entry.
class TimelineEntryItem extends StatelessWidget {
  const TimelineEntryItem(
      {super.key,
      required this.card,
      required this.onTap,
      this.attachments = const [],
      this.isDemoTarget = false});
  final TimelineCardModel card;
  final VoidCallback onTap;
  final List<CardAttachmentData> attachments;
  final bool isDemoTarget;
  @override
  Widget build(BuildContext context) =>
      JournalEntryCard(card: card, onTap: onTap);
}

/// Horizontal navigation through all records and their tags.
class TimelineFilterBar extends StatelessWidget {
  const TimelineFilterBar({
    super.key,
    required this.viewModel,
    this.onPageSelected,
    this.onTagSelected,
    VoidCallback? onInsightSelected,
    this.scrollController,
  });

  final TimelineViewModel viewModel;
  final ValueChanged<int>? onPageSelected;
  final ValueChanged<String>? onTagSelected;
  final ScrollController? scrollController;

  void _select(int index) {
    final tag = index == 0 ? 'all' : viewModel.tags[index - 1].name;
    if (onTagSelected != null) {
      onTagSelected!(tag);
    } else if (viewModel.activeFilter != tag) {
      viewModel.setViewMode(TimelineViewMode.timeline);
      viewModel.setActiveFilter(tag);
      viewModel.loadCards(refresh: true);
    }
    onPageSelected?.call(index);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) => ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          scrollDirection: Axis.horizontal,
          itemCount: viewModel.tags.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            final value = index == 0 ? 'all' : viewModel.tags[index - 1].name;
            return ChoiceChip(
              label: Text(
                  index == 0 ? UserStorage.l10n.timelineFilterAll : '#$value'),
              selected: viewModel.activeFilter == value,
              showCheckmark: false,
              onSelected: (_) => _select(index),
              side: BorderSide.none,
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFFE8E9FF),
              labelStyle: TextStyle(
                  fontSize: 12,
                  color: viewModel.activeFilter == value
                      ? const Color(0xFF4F46E5)
                      : const Color(0xFF64748B)),
            );
          },
        ),
      );
}
