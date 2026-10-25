import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/ui/core/widgets/local_image.dart';
import 'package:memex/utils/user_storage.dart';

bool shouldShowCardAddress(String address) {
  final value = address.trim();
  return value.isNotEmpty && value != 'Unknown';
}

String _journalContent({
  required String rawContent,
  required List<UiConfig> uiConfigs,
  required String title,
}) {
  for (final config in uiConfigs) {
    if (config.templateId != 'classic_card') continue;
    final content = config.data['content'];
    if (content is String && content.trim().isNotEmpty) return content.trim();
  }
  final original = rawContent.trim();
  if (original.isNotEmpty) return original;
  final parts = <String>[];
  for (final config in uiConfigs) {
    for (final key in ['content', 'text', 'description', 'summary']) {
      final value = config.data[key];
      if (value is String &&
          value.trim().isNotEmpty &&
          !parts.contains(value.trim())) {
        parts.add(value.trim());
        break;
      }
    }
  }
  return parts.isEmpty ? title : parts.join('\n\n');
}

/// Selectable journal prose, original input, and tag navigation for detail views.
class TimelineCardDetailBodySection extends StatelessWidget {
  const TimelineCardDetailBodySection(
      {super.key, required this.detail, this.onTagTap})
      : assert(detail != null),
        card = null;

  const TimelineCardDetailBodySection.fromTimeline(
      {super.key, required this.card, this.onTagTap})
      : assert(card != null),
        detail = null;

  final CardDetailModel? detail;
  final TimelineCardModel? card;
  final ValueChanged<String>? onTagTap;

  @override
  Widget build(BuildContext context) {
    final rawContent = detail?.rawContent ?? card?.rawText ?? '';
    final tags = detail?.tags ?? card?.tags ?? const <String>[];
    final content = _journalContent(
      rawContent: rawContent,
      uiConfigs: detail?.uiConfigs ?? card?.uiConfigs ?? const <UiConfig>[],
      title: detail?.title ?? card?.title ?? '',
    );
    if (content.isEmpty && tags.isEmpty) return const SizedBox.shrink();
    return SelectionArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (content.isNotEmpty)
          Text(content,
              style: const TextStyle(
                  fontSize: 16, height: 1.8, color: Color(0xFF273244))),
        if (rawContent.trim().isNotEmpty && rawContent.trim() != content) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(UserStorage.l10n.originalInput,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(rawContent,
                      style: const TextStyle(
                          fontSize: 15, height: 1.7, color: Color(0xFF64748B))))
            ],
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
              spacing: 8,
              runSpacing: 6,
              children: tags
                  .map((tag) => InkWell(
                        onTap: onTagTap == null ? null : () => onTagTap!(tag),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Text('#$tag',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF6366F1))),
                        ),
                      ))
                  .toList()),
        ],
      ]),
    );
  }
}

/// One presentation for both newly captured records and existing journal data.
/// AI prose is separate from the original record, which stays available in detail.
class JournalEntryCard extends StatelessWidget {
  const JournalEntryCard({
    super.key,
    required this.card,
    this.expanded = false,
    this.onTap,
    this.onImageTap,
    this.onTagTap,
    this.onRetry,
    this.retrying = false,
  });

  final TimelineCardModel card;
  final bool expanded;
  final VoidCallback? onTap;
  final ValueChanged<int>? onImageTap;
  final ValueChanged<String>? onTagTap;
  final VoidCallback? onRetry;
  final bool retrying;

  String get _content => _journalContent(
        rawContent: card.rawText ?? '',
        uiConfigs: card.uiConfigs,
        title: card.title ?? '',
      );

  List<String> get imageUrls {
    final images = <String>{
      for (final asset in card.assets ?? [])
        if (asset.isImage) asset.url,
    };
    for (final config in card.uiConfigs) {
      final legacy = config.data['images'];
      if (legacy is List) {
        images.addAll(legacy.whereType<String>());
      }
    }
    return images.toList();
  }

  @override
  Widget build(BuildContext context) {
    final images = imageUrls;
    final content = _content;
    final address = card.address?.trim() ?? '';
    final failed = card.status == 'failed';
    final processing = card.status == 'processing';
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      size: 14, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  Text(
                    expanded
                        ? DateFormat('yyyy年M月d日 HH:mm').format(card.timestamp)
                        : card.displayTime(UserStorage.l10n),
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 14),
                TimelineCardDetailBodySection.fromTimeline(
                    card: card, onTagTap: onTagTap),
              ] else if (content.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(content,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, height: 1.75, color: Color(0xFF273244))),
              ],
              if (images.isNotEmpty) ...[
                const SizedBox(height: 16),
                if (expanded)
                  ...images.asMap().entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onTap: onImageTap == null
                              ? null
                              : () => onImageTap!(entry.key),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: LocalImage(
                                url: entry.value,
                                width: double.infinity,
                                fit: BoxFit.contain),
                          ),
                        ),
                      ))
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: images.length == 1 ? 4 / 3 : 1.6,
                      child: Row(children: [
                        for (var index = 0;
                            index < images.length && index < 3;
                            index++) ...[
                          if (index > 0) const SizedBox(width: 4),
                          Expanded(
                              child: Stack(fit: StackFit.expand, children: [
                            LocalImage(url: images[index], fit: BoxFit.cover),
                            if (index == 2 && images.length > 3)
                              ColoredBox(
                                  color: Colors.black38,
                                  child: Center(
                                      child: Text('+${images.length - 3}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 24)))),
                          ])),
                        ],
                      ]),
                    ),
                  ),
              ],
              if (!expanded && card.tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: card.tags
                        .map((tag) => InkWell(
                              onTap: onTagTap == null
                                  ? null
                                  : () => onTagTap!(tag),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Text('#$tag',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6366F1))),
                              ),
                            ))
                        .toList()),
              ],
              if (shouldShowCardAddress(address)) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(address,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF94A3B8)))),
                ]),
              ],
              if (processing || failed) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: failed
                          ? const Color(0xFFFFF7ED)
                          : const Color(0xFFF5F5FF),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                              failed
                                  ? Icons.error_outline_rounded
                                  : Icons.auto_awesome_outlined,
                              size: 16,
                              color: failed
                                  ? const Color(0xFFC2410C)
                                  : const Color(0xFF6366F1)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  failed
                                      ? UserStorage.l10n.journalFailed
                                      : UserStorage.l10n.journalProcessing,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: failed
                                          ? const Color(0xFFC2410C)
                                          : const Color(0xFF6366F1)))),
                        ]),
                        if (failed &&
                            card.failureReason?.isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Text(card.failureReason!,
                              style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: Color(0xFF9A3412))),
                        ],
                        if (failed && onRetry != null)
                          TextButton.icon(
                              onPressed: retrying ? null : onRetry,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: Text(UserStorage.l10n.journalRetry)),
                      ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
