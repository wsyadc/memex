import 'dart:convert';
import 'dart:io';

import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/journal_write_coordinator.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';

class InputDraft {
  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> imagePaths;
  final Map<String, String> imageOriginalFilenames;

  const InputDraft({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.imagePaths = const [],
    this.imageOriginalFilenames = const {},
  });

  bool get isEmpty => text.trim().isEmpty && imagePaths.isEmpty;

  int get characterCount => text.runes.length;

  Map<String, dynamic> toJson() => {
        'version': 2,
        'id': id,
        'text': text,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'image_paths': imagePaths,
        'image_original_filenames': imageOriginalFilenames,
      };

  factory InputDraft.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return InputDraft(
      id: json['id'] as String? ?? 'active',
      text: json['text'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? now,
      imagePaths:
          (json['image_paths'] as List?)?.whereType<String>().toList() ??
              const [],
      imageOriginalFilenames: (json['image_original_filenames'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          const {},
    );
  }
}

class InputDraftService {
  static final InputDraftService instance = InputDraftService._();

  final _logger = getLogger('InputDraftService');
  final _lock = Lock();
  final Map<String, Map<String, String>> _storedImagesByUser = {};

  InputDraftService._();

  Future<InputDraft?> loadActiveDraft() async {
    try {
      final file = await _activeDraftFile();
      return await _lock.synchronized(() => _readDraft(file));
    } catch (e, st) {
      _logger.warning('Failed to load active input draft: $e', e, st);
      return null;
    }
  }

  Future<bool> hasActiveDraft() async {
    final draft = await loadActiveDraft();
    return draft != null && !draft.isEmpty;
  }

  Future<void> saveTextDraft(String text) async {
    await saveDraft(text: text);
  }

  Future<InputDraft?> saveDraft({
    required String text,
    List<String> imagePaths = const [],
    Map<String, String> imageOriginalFilenames = const {},
  }) async {
    final userId = await _requireUserId();
    return JournalWriteCoordinator.protect(() => _lock.synchronized(() async {
          try {
            final fileService = FileSystemService.instance;
            final file = File(fileService.getActiveDraftPath(userId));
            if (text.trim().isEmpty && imagePaths.isEmpty) {
              if (await file.exists()) await file.delete();
              return null;
            }
            final previous = await _readDraft(file);
            final storedImages =
                _storedImagesByUser.putIfAbsent(userId, () => {});
            final savedPaths = <String>[];
            final savedNames = <String, String>{};
            for (final sourcePath in imagePaths) {
              var storedPath = storedImages[sourcePath];
              if (storedPath == null || !await File(storedPath).exists()) {
                if (path.isWithin(
                    fileService.getAssetsPath(userId), sourcePath)) {
                  if (!await File(sourcePath).exists()) {
                    throw FileSystemException(
                        'Draft photo is missing', sourcePath);
                  }
                  storedPath = sourcePath;
                } else {
                  final (_, relativePath) = await fileService.saveAssetFromFile(
                    userId: userId,
                    sourcePath: sourcePath,
                    assetType: 'img',
                  );
                  storedPath = fileService.toAbsolutePath(relativePath);
                }
                storedImages[sourcePath] = storedPath;
              }
              savedPaths.add(storedPath);
              savedNames[storedPath] = imageOriginalFilenames[sourcePath] ??
                  path.basename(sourcePath);
            }
            if (previous != null &&
                previous.text == text &&
                _samePaths(previous.imagePaths, savedPaths) &&
                savedNames.entries.every(
                  (entry) =>
                      previous.imageOriginalFilenames[entry.key] == entry.value,
                )) {
              return previous;
            }
            final now = DateTime.now();
            final draft = InputDraft(
              id: previous?.id ?? 'active',
              text: text,
              createdAt: previous?.createdAt ?? now,
              updatedAt: now,
              imagePaths: savedPaths,
              imageOriginalFilenames: savedNames,
            );

            await file.parent.create(recursive: true);
            final json = draft.toJson();
            json['image_paths'] =
                savedPaths.map(fileService.toRelativePath).toList();
            json['image_original_filenames'] = savedNames.map(
              (key, value) => MapEntry(fileService.toRelativePath(key), value),
            );
            final tempFile = File('${file.path}.tmp');
            await tempFile.writeAsString(jsonEncode(json), flush: true);
            await tempFile.rename(file.path);
            return draft;
          } catch (e, st) {
            _logger.warning('Failed to save active input draft: $e', e, st);
            rethrow;
          }
        }));
  }

  Future<void> clearActiveDraft({
    String? expectedText,
    List<String>? expectedImagePaths,
  }) async {
    final file = await _activeDraftFile();
    return JournalWriteCoordinator.protect(() => _lock.synchronized(() async {
          try {
            if (expectedText != null || expectedImagePaths != null) {
              final current = await _readDraft(file);
              if (current == null ||
                  (expectedText != null && current.text != expectedText) ||
                  (expectedImagePaths != null &&
                      !_samePaths(current.imagePaths, expectedImagePaths))) {
                return;
              }
            }
            if (await file.exists()) {
              await file.delete();
            }
          } catch (e, st) {
            _logger.warning('Failed to clear active input draft: $e', e, st);
            rethrow;
          }
        }));
  }

  Future<InputDraft?> _readDraft(File file) async {
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final fileService = FileSystemService.instance;
    final saved = InputDraft.fromJson(json);
    if (saved.isEmpty) return null;
    return InputDraft(
      id: saved.id,
      text: saved.text,
      createdAt: saved.createdAt,
      updatedAt: saved.updatedAt,
      imagePaths: saved.imagePaths.map(fileService.toAbsolutePath).toList(),
      imageOriginalFilenames: saved.imageOriginalFilenames.map(
        (key, value) => MapEntry(fileService.toAbsolutePath(key), value),
      ),
    );
  }

  bool _samePaths(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  Future<String> _requireUserId() async {
    final userId = await UserStorage.getUserId();
    if (userId == null || userId.isEmpty) {
      throw StateError('Cannot save a draft without an active user');
    }
    return userId;
  }

  Future<File> _activeDraftFile() async {
    final userId = await _requireUserId();
    final filePath = FileSystemService.instance.getActiveDraftPath(userId);
    return File(filePath);
  }
}
