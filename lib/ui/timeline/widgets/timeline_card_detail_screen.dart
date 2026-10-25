import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/core/widgets/local_image.dart';
import 'package:memex/ui/timeline/widgets/location_picker_page.dart';
import 'package:memex/ui/timeline/widgets/journal_entry_card.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

export 'journal_entry_card.dart'
    show TimelineCardDetailBodySection, shouldShowCardAddress;

class TimelineCardDetailScreen extends StatefulWidget {
  const TimelineCardDetailScreen(
      {super.key, required this.cardId, this.showDemoHint = false});
  final String cardId;
  final bool showDemoHint;

  @override
  State<TimelineCardDetailScreen> createState() =>
      _TimelineCardDetailScreenState();
}

class _TimelineCardDetailScreenState extends State<TimelineCardDetailScreen> {
  final MemexRouter _memexRouter = MemexRouter();
  CardDetailModel? _detail;
  bool _isLoading = true;
  bool _retrying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    EventBusService.instance
        .addHandler(EventBusMessageType.cardUpdated, _onCardChanged);
    EventBusService.instance
        .addHandler(EventBusMessageType.cardDetailUpdated, _onCardChanged);
    _fetchDetail();
  }

  @override
  void dispose() {
    EventBusService.instance
        .removeHandler(EventBusMessageType.cardUpdated, _onCardChanged);
    EventBusService.instance
        .removeHandler(EventBusMessageType.cardDetailUpdated, _onCardChanged);
    super.dispose();
  }

  void _onCardChanged(EventBusMessage message) {
    if (message is CardUpdatedMessage && message.id == widget.cardId ||
        message is CardDetailUpdatedMessage &&
            message.cardId == widget.cardId) {
      _fetchDetail();
    }
  }

  Future<void> _fetchDetail() async {
    try {
      final detail = await _memexRouter.fetchCardDetail(widget.cardId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = UserStorage.l10n.loadDetailFailedRetryShort;
      });
      ToastHelper.showError(context, error);
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    final result = await _memexRouter.retryJournalCard(widget.cardId);
    if (!mounted) return;
    setState(() => _retrying = false);
    result.when(
      onOk: (_) {
        ToastHelper.showSuccess(context, UserStorage.l10n.journalRetryQueued);
        _fetchDetail();
      },
      onError: (error, _) => ToastHelper.showError(context, error),
    );
  }

  Future<void> _editTime() async {
    if (_detail == null) return;

    final initialDate = _detail!.timestamp;
    final now = DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 365)),
    );

    if (date == null) return;
    if (!mounted) return;

    // Use CupertinoDatePicker for cleaner time selection
    // Default to initial time or now if same day
    final initialTime = TimeOfDay.fromDateTime(initialDate);
    var selectedDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      initialTime.hour,
      initialTime.minute,
    );

    final timeResult = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: Text(UserStorage.l10n.cancel),
                    onPressed: () => Navigator.pop(context),
                  ),
                  CupertinoButton(
                    child: Text(UserStorage.l10n.confirm),
                    onPressed: () => Navigator.pop(context, selectedDateTime),
                  ),
                ],
              ),
              SizedBox(
                height: 200,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: selectedDateTime,
                  use24hFormat: true,
                  onDateTimeChanged: (DateTime newDateTime) {
                    selectedDateTime = newDateTime;
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (timeResult == null) return;

    final newDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      timeResult.hour,
      timeResult.minute,
    );

    // Optimistic Update
    final oldDetail = _detail;
    setState(() {
      _detail = _detail!.copyWith(timestamp: newDateTime);
    });

    try {
      // API call
      // Server expects unix timestamp in seconds
      final timestamp = newDateTime.millisecondsSinceEpoch ~/ 1000;
      await _memexRouter.updateCardTime(widget.cardId, timestamp);
      if (!mounted) return;
      ToastHelper.showSuccess(context, UserStorage.l10n.timeUpdated);
    } catch (e) {
      if (!mounted) return;
      // Revert
      setState(() {
        _detail = oldDetail;
      });
      ToastHelper.showError(
        context,
        UserStorage.l10n.updateFailed(e.toString()),
      );
    }
  }

  Future<void> _editLocation() async {
    if (_detail == null) return;

    final result = await Navigator.push<LocationPickerResult>(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerPage(
          initialName: _detail!.address,
          initialPoint: (_detail!.lat != null && _detail!.lng != null)
              ? LatLng(_detail!.lat!, _detail!.lng!)
              : null,
        ),
      ),
    );

    if (result != null) {
      // Optimistic Update
      final oldDetail = _detail;
      setState(() {
        _detail = _detail!.copyWith(
          address: result.name ?? result.address,
          lat: result.point.latitude,
          lng: result.point.longitude,
        );
      });

      try {
        await _memexRouter.updateCardLocation(
          widget.cardId,
          result.point.latitude,
          result.point.longitude,
          result.name ?? result.address ?? '',
        );
        if (!mounted) return;
        ToastHelper.showSuccess(context, UserStorage.l10n.locationUpdated);
      } catch (e) {
        if (!mounted) return;
        // Revert
        setState(() {
          _detail = oldDetail;
        });
        ToastHelper.showError(
          context,
          UserStorage.l10n.updateFailed(e.toString()),
        );
      }
    }
  }

  Future<void> _deleteCard() async {
    if (_detail == null) return;

    // show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(UserStorage.l10n.confirmDelete),
        content: Text(UserStorage.l10n.confirmDeleteCardMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(UserStorage.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(UserStorage.l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // call delete API
      await _memexRouter.deleteCard(widget.cardId);

      if (mounted) {
        ToastHelper.showSuccess(context, UserStorage.l10n.deleteSuccess);
        // go back
        Navigator.of(context).pop(true); // true = deleted, refresh timeline
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showError(
          context,
          UserStorage.l10n.deleteFailed(e.toString()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final detail = _detail;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8FA),
        title: Text(l10n.journalTitle),
        actions: [
          if (detail != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'time':
                    _editTime();
                  case 'location':
                    _editLocation();
                  case 'calendar':
                    context.push(AppRoutes.calendar, extra: detail.timestamp);
                  case 'delete':
                    _deleteCard();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'time', child: Text(l10n.journalEditTime)),
                PopupMenuItem(value: 'location', child: Text(l10n.location)),
                PopupMenuItem(value: 'calendar', child: Text(l10n.calendar)),
                const PopupMenuDivider(),
                PopupMenuItem(
                    value: 'delete',
                    child: Text(l10n.delete,
                        style: const TextStyle(color: Colors.red))),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: AgentLogoLoading())
          : detail == null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_errorMessage ?? l10n.cardDetailNotFound),
                  TextButton(onPressed: _fetchDetail, child: Text(l10n.retry)),
                ]))
              : RefreshIndicator(
                  onRefresh: _fetchDetail,
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (_errorMessage != null)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(_errorMessage!,
                                  style: const TextStyle(color: Colors.red))),
                        _buildEntry(detail),
                      ]),
                ),
    );
  }

  Widget _buildEntry(CardDetailModel detail) {
    final card = TimelineCardModel(
      id: detail.id,
      timestamp: detail.timestamp,
      tags: detail.tags,
      status: detail.status,
      title: detail.title,
      uiConfigs: detail.uiConfigs,
      assets: detail.assets,
      rawText: detail.rawContent,
      address: detail.address,
      failureReason: detail.failureReason,
    );
    return JournalEntryCard(
      card: card,
      expanded: true,
      retrying: _retrying,
      onRetry: _retry,
      onTagTap: (tag) =>
          Navigator.pop(context, {'action': 'filter_tag', 'tag': tag}),
      onImageTap: (index) {
        final images = JournalEntryCard(card: card).imageUrls;
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    _JournalImageGallery(images: images, initialIndex: index)));
      },
    );
  }
}

class _JournalImageGallery extends StatefulWidget {
  const _JournalImageGallery(
      {required this.images, required this.initialIndex});
  final List<String> images;
  final int initialIndex;
  @override
  State<_JournalImageGallery> createState() => _JournalImageGalleryState();
}

class _JournalImageGalleryState extends State<_JournalImageGallery> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text('${_index + 1} / ${widget.images.length}')),
        body: PhotoViewGallery.builder(
          pageController: _controller,
          itemCount: widget.images.length,
          onPageChanged: (index) => setState(() => _index = index),
          builder: (_, index) => PhotoViewGalleryPageOptions(
              imageProvider: LocalImage.provider(widget.images[index]),
              initialScale: PhotoViewComputedScale.contained),
        ),
      );
}
