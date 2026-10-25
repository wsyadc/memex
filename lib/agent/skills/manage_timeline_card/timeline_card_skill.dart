// ignore_for_file: non_constant_identifier_names

import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:logging/logging.dart';
import 'package:memex/agent/run_mode/agent_action_approval_service.dart';
import 'package:memex/data/model/chat_artifact.dart';
import 'package:memex/data/services/asset_reference_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/timeline_card_event_publisher.dart';

final logger = Logger('TimelineCardSkill');

bool _nonEmpty(String? value) => value != null && value.trim().isNotEmpty;

String? _artifactSnippet(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  return text.length > 160 ? '${text.substring(0, 160)}…' : text;
}

List<String> _assetImagePathsForArtifact(List<String> assets) {
  final paths = <String>[];
  final imageMarker = RegExp(r'^!\[[^\]]*\]\(fs://([^)]+)\)$');
  for (final asset in assets) {
    final match = imageMarker.firstMatch(asset.trim());
    if (match == null) continue;
    final fileName = match.group(1)?.trim();
    if (fileName == null || fileName.isEmpty) continue;
    paths.add('fs://$fileName');
  }
  return paths;
}

/// Skill for managing Timeline Cards
class TimelineCardSkill extends Skill {
  TimelineCardSkill({
    super.forceActivate,
    bool stopAfterSuccessSaveCard = false,
    bool enableFinishSummary = false,
  }) : super(
          name: "manage_timeline_card", // Renamed as requested
          description:
              "Creates new timeline cards from user input or updates existing timeline card details based on feedback. "
              "Organizes text and photos into a single journal layout. "
              "Use when: 1. User posts new content needing a timeline card. 2. User provides feedback to modify an existing timeline card.",
          systemPrompt: _buildSystemPrompt(),
          tools: _buildTools(
            stopAfterSuccessSaveCard,
            enableFinishSummary: enableFinishSummary,
          ),
        );

  static String _buildSystemPrompt() => r'''
将文字和照片整理为一篇简体中文日记。只使用 save_timeline_card 保存。
fact 是用户原文，保留原句；ui_configs 中唯一的 classic_card.data.content 是整理后的正文，保留用户语气与事件细节；title 是简短标题。根据原文和照片确定记录时间，只有当前发生的事件才采用当前位置。照片引用原样放入 assets，正文不写文件路径。
卡片固定 classic_card 版式；ui_configs 只提供 [{"template_id":"classic_card","data":{"content":"整理后的正文"}}]。选择 1–3 个合适标签；get_card_metadata 可读取允许的标签。
已有 fact_id 必须复用。每篇独立导入的日记需要自己的 fact_id，保存成功后才返回完成。不得创建其他类型的内容或进行额外分析。
''';

  static Future<String> getTimelineCardMetadata(String userId) async {
    final fileService = FileSystemService.instance;
    await fileService.ensureTagsFileInitialized(userId);
    final tagsListRaw = await fileService.readTagsFile(userId);
    final tagsList = tagsListRaw.map((t) => t['name'] as String).toList();

    final sb = StringBuffer('日记采用统一图文版式。\n');
    sb.writeln("# Existing Tags");
    if (tagsList.isEmpty) {
      sb.writeln("No tags currently available. Create tags as needed.");
    } else {
      for (final tag in tagsList) {
        sb.writeln("- $tag");
      }
    }

    return sb.toString();
  }

  static List<Tool> _buildTools(
    bool stopAfterSuccessSaveCard, {
    required bool enableFinishSummary,
  }) {
    final saveProperties = <String, dynamic>{
      'fact_id': {
        'type': 'string',
        'description':
            'REQUIRED. For a brand-new record: the id you minted with `mint_record_fact_id` first. For editing/repairing: the existing card id (e.g. 2025/01/01.md#ts_123). Never invent an id — it must come from mint_record_fact_id or be an existing card.',
      },
      'title': {
        'type': 'string',
        'description':
            'A concise summary displayed on detail page header. Required for a new card; omit when editing to keep the existing title.',
      },
      'ui_configs': {
        'type': 'array',
        'description':
            'The journal body after paragraph and punctuation cleanup. Use exactly one classic_card entry. Original fact and photos are preserved separately.',
        'minItems': 1,
        'maxItems': 1,
        'items': {
          'type': 'object',
          'properties': {
            'template_id': {
              'type': 'string',
              'enum': ['classic_card'],
            },
            'data': {
              'type': 'object',
              'properties': {
                'content': {'type': 'string'},
              },
              'required': ['content'],
            },
          },
          'required': ['template_id', 'data'],
        },
      },
      'address': {
        'type': 'string',
        'description':
            'Location information for where the recorded card actually happened. Use raw input named places only when they are the actual occurrence, check-in, visit, photo capture, or activity location. For tasks, todos, reminders, plans, wishes, future destinations, or places the user merely wants to go to, omit address even if a place is mentioned. If raw input describes an immediate present-time event, check-in, photo capture, or daily activity and current_location_context is available, use its location_summary or full_address_candidate as a conservative default. Do not use current_location_context for memories, plans, remote events, or when raw input names a conflicting place. Do not be too specific. Use the format "City · Specific Location" (e.g., Beijing · Chaoyang Park) if possible, otherwise just the specific location name is fine.',
      },
      'user_mark_address': {
        'type': 'string',
        'description':
            'User-marked location information, set when raw input contains very close user-marked location',
      },
      'content_creation_date': {
        'type': 'string',
        'description':
            'The creation date of the content (e.g. image capture time), in format "YYYY-MM-DD HH:MM:SS". If not provided, current time will be used.',
      },
      'tags': {
        'type': 'array',
        'description':
            'Select 1-3 most appropriate tags strictly from internal pre-defined list. Do not invent new tags.',
        'items': {
          'type': 'object',
          'properties': {
            'name': {
              'type': 'string',
              'description':
                  "Tag name. MUST be one of: 'Project', 'Trip', 'Milestone', 'Health', 'Relationship', 'Finance', 'Knowledge', 'Emotion', 'Visual', 'Audio'.",
            },
            'icon': {
              'type': 'string',
              'description': 'Not used anymore, internal icons are hardcoded.',
            },
          },
          'required': ['name'],
        },
      },
      'fact': {
        'type': 'string',
        'description':
            "The original user text, copied faithfully. Existing original text is preserved by the app. Provide this for imported records without saved original text; put the organized journal body in ui_configs[0].data.content. Attachment references belong in assets.",
      },
      'assets': {
        'type': 'array',
        'description':
            "The image and audio files attached to this card, as bare `fs://...` references extracted from the attachment markers in the user message (for example `fs://photo.jpg`) — copied exactly, never invented or altered. Omit this field entirely to keep the card's existing assets unchanged; pass the full list to replace them. Required only when a new card has attachments.",
        'items': {'type': 'string'},
      },
      if (enableFinishSummary)
        'finish_summary': {
          'type': 'string',
          'description':
              'If this successful save completes the requested work, set this to the exact concise final summary to return. Include relevant work already done in this run. Omit it if another tool call, inspection, or repair is still needed.',
        },
    };

    return [
      Tool(
        name: 'get_card_metadata',
        description: 'Get journal tags.',
        parameters: {'type': 'object', 'properties': {}},
        executable: () async {
          final userId = AgentCallToolContext.current!.state.metadata['userId'];
          return getTimelineCardMetadata(userId);
        },
      ),
      Tool(
        name: 'save_timeline_card',
        description: "Saves or updates a journal card. Its "
            "original text and existing photos stay preserved. Put organized prose "
            "in classic_card.data.content. A new record needs a title and "
            "original text or photos. Omitted optional fields keep their value.",
        parameters: {
          'type': 'object',
          'properties': saveProperties,
          'required': ['fact_id'],
        },
        executable: (
          String? fact_id,
          String? title,
          dynamic ui_configs,
          String? address,
          String? user_mark_address,
          String? content_creation_date,
          dynamic tags,
          String? fact,
          dynamic assets, [
          String? finish_summary,
        ]) async {
          final fileService = FileSystemService.instance;

          // Access context
          final context = AgentCallToolContext.current;
          if (context == null) {
            throw StateError(
              "save_timeline_card must be called within an agent execution context.",
            );
          }

          // fact_id and userId are available via closure/args.

          logger.info("Saving card for fact: ${fact_id ?? '(new)'}");

          final userId = AgentCallToolContext.current!.state.metadata['userId'];
          final isSubAgent =
              AgentCallToolContext.current!.state.metadata['sub_agent_mode'] ==
                  true;

          final denied = await gateMutatingToolCall(
            toolName: 'save_timeline_card',
            summary: '${title ?? '(card)'}'
                '${fact_id == null ? '' : ' ($fact_id)'}',
          );
          if (denied != null) return denied;

          String? rollbackPlaceholderFactId;
          try {
            // Resolve identity and read the prior card FIRST — whether this is
            // a brand-new card or an edit drives what's required. fact_id is
            // always explicit now (minted via mint_record_fact_id for a new
            // record, or an existing card's id when editing); we never allocate
            // inside save.
            if (fact_id == null || fact_id.trim().isEmpty) {
              throw ArgumentError(
                "fact_id is required. Mint one with mint_record_fact_id first (for a new record), or pass an existing card's id when editing.",
              );
            }
            final resolvedFactId = fact_id.trim();
            final priorCard = await fileService.readCardFile(
              userId,
              resolvedFactId,
            );
            if (priorCard == null) {
              throw ArgumentError(
                "Card $resolvedFactId does not exist. Mint a fact_id with mint_record_fact_id before saving a new record, or pass the id of an existing card to edit.",
              );
            }
            // A freshly-minted placeholder has status 'processing' and was never
            // completed → this save is the brand-new card. An already-'completed'
            // card is an edit and emits a card-update event.
            final isNewCard = priorCard.status != 'completed';
            final isEmptyProcessingPlaceholder =
                _isEmptyProcessingPlaceholder(priorCard);
            if (isEmptyProcessingPlaceholder) {
              rollbackPlaceholderFactId = resolvedFactId;
            }

            // A new diary needs a title and source text or photos. Existing
            // source text stays intact; organized prose has its own UI field.
            if (isNewCard) {
              if (title == null || title.trim().isEmpty) {
                throw ArgumentError("title is required for a new card.");
              }
              if ((fact == null || fact.trim().isEmpty) &&
                  (priorCard.fact?.trim().isEmpty ?? true) &&
                  priorCard.assets.isEmpty &&
                  (assets == null ||
                      _normalizeListArgument(assets, 'assets').isEmpty)) {
                throw ArgumentError("fact is required for a new card.");
              }
            }

            // Guard: `fs://` references identify attachments and belong only in
            // `assets`. Keeping them out of `fact` (which is prose) prevents the
            // raw id leaking into the card's source-of-truth text.
            if (fact != null && fact.contains('fs://')) {
              throw ArgumentError(
                "The `fact` field must not contain an `fs://` reference. Write `fact` as a coherent record in the user's own words and speaking/writing style, using the image/audio content that matters to the record, and put the bare `fs://...` reference in the `assets` field instead.",
              );
            }

            String? organizedContent;
            if (ui_configs != null) {
              final entries = _normalizeListArgument(
                ui_configs,
                'ui_configs',
              );
              if (entries.length != 1 || entries.single is! Map) {
                throw ArgumentError(
                  'Provide one classic_card journal body.',
                );
              }
              final entry = entries.single as Map;
              final data = entry['data'];
              if (entry['template_id'] != 'classic_card' ||
                  data is! Map ||
                  data['content'] is! String ||
                  (data['content'] as String).trim().isEmpty) {
                throw ArgumentError(
                  'classic_card.data.content must contain the journal body.',
                );
              }
              organizedContent = (data['content'] as String).trim();
            }

            // 3. Load existing tags
            await fileService.ensureTagsFileInitialized(userId);
            final tagDefinitions = await fileService.readTagsFile(userId);
            final existingTagNames =
                tagDefinitions.map((t) => t['name'] as String).toSet();

            // 4. Strict Tag Processing — only predefined tags are allowed
            const Map<String, Map<String, String>> allowedTags = {
              'Project': {'icon': '🎯', 'icon_type': 'emoji'},
              'Trip': {'icon': '✈️', 'icon_type': 'emoji'},
              'Milestone': {'icon': '🏆', 'icon_type': 'emoji'},
              'Health': {'icon': '🏥', 'icon_type': 'emoji'},
              'Relationship': {'icon': '🫂', 'icon_type': 'emoji'},
              'Finance': {'icon': '💰', 'icon_type': 'emoji'},
              'Knowledge': {'icon': '💡', 'icon_type': 'emoji'},
              'Emotion': {'icon': '🎭', 'icon_type': 'emoji'},
              'Visual': {'icon': '📸', 'icon_type': 'emoji'},
              'Audio': {'icon': '🎙️', 'icon_type': 'emoji'},
            };

            final tagNames = <String>[];
            final newTagsToCreate = <Map<String, dynamic>>[];

            final tagsList =
                tags == null ? null : _normalizeListArgument(tags, 'tags');
            if (tagsList != null) {
              for (var tagObj in tagsList) {
                final extractMap = Map<String, dynamic>.from(tagObj as Map);
                var tagName = (extractMap['name'] as String?)?.trim() ?? '';

                if (tagName.isEmpty) continue;

                // Normalize capitalization (e.g. 'project' -> 'Project')
                tagName = tagName[0].toUpperCase() +
                    tagName.substring(1).toLowerCase();

                if (!allowedTags.containsKey(tagName)) {
                  throw ArgumentError(
                    "Invalid tag '$tagName'. You MUST only use tags from the following list: ${allowedTags.keys.join(', ')}.",
                  );
                }

                if (!tagNames.contains(tagName)) {
                  tagNames.add(tagName);
                }

                // Auto-persist the tag if it's the first time being used
                if (!existingTagNames.contains(tagName)) {
                  newTagsToCreate.add({
                    'name': tagName,
                    'icon': allowedTags[tagName]!['icon']!,
                    'icon_type': allowedTags[tagName]!['icon_type']!,
                  });
                  existingTagNames.add(tagName);
                }
              }
            }

            // 5. Save new tags to DB
            if (newTagsToCreate.isNotEmpty) {
              await fileService.appendNewTags(userId, newTagsToCreate);
            }

            // 9. Determine timestamp
            int? timestamp;
            if (content_creation_date != null &&
                content_creation_date.isNotEmpty) {
              try {
                timestamp = DateTime.parse(
                      content_creation_date,
                    ).millisecondsSinceEpoch ~/
                    1000;
              } catch (e) {
                logger.warning(
                  "Failed to parse content_creation_date: $content_creation_date",
                );
              }
            }

            // 10. Update Card File
            Map<String, dynamic>? locationInfo;
            if (user_mark_address != null) {
              locationInfo = await fileService.getUserLocationByName(
                userId,
                user_mark_address,
              );
            }

            // Normalize asset references. Tool callers provide bare
            // `fs://...` ids (view_image uses the same form). Cards still store
            // full markdown refs because the renderer uses the marker shape to
            // distinguish image vs audio.
            // Omitted (null) keeps prior assets. Provided refs add to the existing set: each fs:// reference must
            // resolve to a real file under Facts/assets, so a fabricated /
            // hallucinated reference never lands on the card.
            List<String>? assetsList;
            if (assets != null) {
              assetsList = <String>[...priorCard.assets];
              final assetEntries = _normalizeListArgument(assets, 'assets');
              for (var i = 0; i < assetEntries.length; i++) {
                final entry = assetEntries[i];
                final ref = entry?.toString().trim() ?? '';
                if (ref.isEmpty) continue;
                final asset = await _resolveRequiredAssetReference(
                  userId: userId,
                  reference: ref,
                  path: 'assets[$i]',
                );
                if (!assetsList.contains(asset.markdownRef)) {
                  assetsList.add(asset.markdownRef);
                }
              }
            }

            final updatedCardData = await fileService.updateCardFile(
              userId,
              resolvedFactId,
              createIfNotExists: true,
              (card) {
                final existingContent = card.uiConfigs
                    .where((config) => config.templateId == 'classic_card')
                    .firstOrNull
                    ?.data['content']
                    ?.toString();
                final displayContent = organizedContent ??
                    (_nonEmpty(existingContent)
                        ? existingContent!
                        : fact?.trim() ?? card.fact ?? '');
                var c = card.copyWith(
                  status: 'completed',
                  title: title?.trim(),
                  uiConfigs: [
                    UiConfig(
                      templateId: 'classic_card',
                      data: {
                        'content': displayContent,
                        'images': _assetImagePathsForArtifact(
                          assetsList ?? card.assets,
                        ),
                      },
                    ),
                  ],
                  fact: (card.fact != null || card.assets.isNotEmpty)
                      ? card.fact
                      : fact?.trim(),
                  clearFailureReason: true,
                  assets: assetsList,
                  timestamp: timestamp ??
                      (card.timestamp > 0
                          ? card.timestamp
                          : DateTime.now().millisecondsSinceEpoch ~/ 1000),
                  address: address ?? card.address,
                  tags: tagNames.isNotEmpty ? tagNames : card.tags,
                );
                if (locationInfo != null) {
                  c = c.copyWith(
                    userFixedAddress: locationInfo['name'] as String?,
                    userFixedLocation: UserFixedLocation(
                      lat: (locationInfo['lat'] as num?)?.toDouble(),
                      lng: (locationInfo['lng'] as num?)?.toDouble(),
                      name: locationInfo['name'] as String?,
                    ),
                  );
                }
                return c;
              },
            );

            if (updatedCardData == null) {
              throw StateError(
                "Card file not found for fact_id: $resolvedFactId, maybe it has been deleted",
              );
            }
            rollbackPlaceholderFactId = null;

            if (isNewCard) {
              await emitTimelineCardAdded(
                userId: userId,
                cardId: resolvedFactId,
                cardData: updatedCardData,
              );
            } else {
              await emitTimelineCardUpdated(
                userId: userId,
                cardId: resolvedFactId,
                cardData: updatedCardData,
              );
            }

            // Log event
            try {
              // Determine card file path from fact_id
              final parts = resolvedFactId.split('#');
              if (parts.length == 2) {
                final datePart = parts[0]; // e.g., "2025/01/21.md"
                final dateWithoutExt = datePart.replaceFirst('.md', '');
                final tsId = parts[1]; // e.g., "ts_1"
                final cardFileName = '${dateWithoutExt}_$tsId.yaml';
                final cardPath = 'Cards/$cardFileName';

                await fileService.eventLogService.logFileModified(
                  userId: userId,
                  filePath: cardPath,
                  description: 'Agent updated timeline card',
                  metadata: {'fact_id': resolvedFactId, 'title': title},
                );
              }
            } catch (e) {
              // Event logging failure should not break tool
            }

            return AgentToolResult(
              content: TextPart('Successfully saved timeline card.'),
              stopFlag: stopAfterSuccessSaveCard ||
                  (isSubAgent && _nonEmpty(finish_summary)),
              metadata: {
                'artifact': ChatArtifact.timelineCard(
                  cardId: resolvedFactId,
                  title: title ?? updatedCardData.title,
                  summary: _artifactSnippet(updatedCardData.fact),
                  imagePaths: _assetImagePathsForArtifact(
                    updatedCardData.assets,
                  ),
                  tags: updatedCardData.tags,
                  updated: !isNewCard,
                ).toJson(),
                if (isSubAgent && _nonEmpty(finish_summary))
                  'child_terminal_result': {
                    'status': 'completed',
                    'summary': finish_summary!.trim(),
                    'fact_id': resolvedFactId,
                    'card_changed': true,
                  },
              },
            );
          } catch (e, stack) {
            final factIdToRollback = rollbackPlaceholderFactId;
            if (factIdToRollback != null) {
              try {
                await fileService.deleteCard(userId, factIdToRollback);
                logger.warning(
                  'Rolled back empty processing placeholder after save_timeline_card failed: $factIdToRollback',
                );
              } catch (deleteError) {
                logger.warning(
                  'Failed to roll back processing placeholder $factIdToRollback: $deleteError',
                );
              }
            }
            logger.severe("SaveTimelineCard failed", e, stack);
            rethrow;
          }
        },
      ),
    ];
  }

  static List<dynamic> _normalizeListArgument(dynamic value, String name) {
    if (value is List) {
      return value;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        throw ArgumentError('$name must be a non-empty array.');
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded;
        }
        throw ArgumentError(
          '$name must be an array or a JSON-encoded array string.',
        );
      } on FormatException catch (e) {
        throw ArgumentError(
          '$name must be valid JSON when passed as a string: '
          '${e.message}',
        );
      }
    }
    throw ArgumentError(
      '$name must be an array or a JSON-encoded array string, got ${value.runtimeType}.',
    );
  }

  static bool _isEmptyProcessingPlaceholder(CardData card) {
    if (card.status != 'processing') return false;
    if (card.fact?.trim().isNotEmpty ?? false) return false;
    if (card.title?.trim().isNotEmpty ?? false) return false;
    if (card.assets.isNotEmpty) return false;
    if (card.uiConfigs.isEmpty) return true;
    if (card.uiConfigs.length != 1) return false;

    final config = card.uiConfigs.single;
    if (config.templateId != 'classic_card') return false;

    final content = config.data['content'];
    if (content != null && content.toString().trim().isNotEmpty) {
      return false;
    }

    return config.data.entries.every((entry) {
      if (entry.key == 'content') return true;
      final value = entry.value;
      if (value == null) return true;
      if (value is String) return value.trim().isEmpty;
      if (value is Iterable) return value.isEmpty;
      if (value is Map) return value.isEmpty;
      return false;
    });
  }

  static Future<AssetReference> _resolveRequiredAssetReference({
    required String userId,
    required String reference,
    required String path,
  }) async {
    if (!reference.startsWith('fs://')) {
      throw ArgumentError(
        '$path must be a bare `fs://filename.ext` reference to an existing image or audio file under Facts/assets; got "$reference".',
      );
    }

    final fileName = AssetReferenceService.extractFileNameFromReference(
      reference,
    );
    if (fileName == null) {
      throw ArgumentError(
        '$path has an invalid local media reference "$reference". Use a bare `fs://filename.ext` reference with a supported image or audio extension.',
      );
    }
    if (reference != 'fs://$fileName') {
      throw ArgumentError(
        '$path must be exactly `fs://$fileName`; do not add markdown, query strings, paths, or surrounding text.',
      );
    }

    final asset = await AssetReferenceService.resolveExistingFileName(
      userId: userId,
      fileName: fileName,
    );
    if (asset == null) {
      throw ArgumentError(
        '$path references "$reference", but no supported image or audio file with that name exists under Facts/assets.',
      );
    }
    return asset;
  }
}
