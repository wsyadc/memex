import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:workmanager/workmanager.dart';
import 'package:memex/app_startup.dart';
import 'package:memex/config/dependencies.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/agent_background_task_service.dart';
import 'package:memex/data/services/local_task_executor.dart';
import 'package:memex/data/services/local_server_service.dart';
import 'package:memex/data/services/health_service.dart'
    show callbackDispatcher;
import 'package:memex/data/services/onboarding_service.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/app_action_link_service.dart';
import 'package:memex/data/services/app_action_service.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline_screen.dart';
import 'package:memex/ui/user_setup/widgets/user_setup_screen.dart';
import 'package:memex/ui/app_lock/widgets/lock_screen_page.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/core/themes/app_theme.dart';
import 'package:memex/ui/core/themes/bundled_google_fonts.dart';
import 'package:memex/ui/settings/widgets/model_config_list_page.dart';
import 'package:memex/ui/chat/widgets/open_super_agent_dialog.dart';
import 'package:memex/routing/router.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/wakelock_manager.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<RootShellState> rootShellKey = GlobalKey<RootShellState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureBundledGoogleFonts();

  // Initialize flavor from platform (set by --flavor flag)
  AppFlavor.init(appFlavor);

  await setupLogger();

  if (kDebugMode || AppFlavor.isDev) {
    await WakelockManager.acquire('debug_session');
  }

  await initializeStartupServices(
    initL10n: () async {
      await UserStorage.initL10n();
      await UserStorage.setLocale(const Locale('zh'));
    },
    initWorkmanager: () => Workmanager().initialize(callbackDispatcher),
    initAgentBridge: AgentBackgroundTaskService.instance.initializeNativeBridge,
    startLocalServer: LocalServerService.start,
  );

  // Cancel legacy pedometer background tasks on iOS without wiping newer
  // background registrations such as agent queue processing.
  if (Platform.isIOS) {
    await Workmanager().cancelByUniqueName('workmanager.background.task');
    await Workmanager().cancelByUniqueName('dailyStepSnapshotTask');
  }

  // Set status bar style & enable edge-to-edge
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  final appRouter = createAppRouter(
    rootNavigatorKey,
    () => RootShell(key: rootShellKey),
  );

  // Initialize quick actions (app icon long-press shortcuts).
  const QuickActions quickActions = QuickActions();
  quickActions.initialize((String shortcutType) {
    AppActionService.instance.handleAction(
      shortcutType,
      source: 'quick_action',
    );
  });
  unawaited(AppActionLinkService.instance.initialize());

  runApp(
    MultiProvider(
      providers: dependencyProviders,
      child: MemexApp(router: appRouter),
    ),
  );
}

/// Root route content: user check then loading / UserSetupScreen / MainScreen (Compass-style).
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => RootShellState();
}

class RootShellState extends State<RootShell> {
  bool _hasUser = false;
  bool _onboardingComplete = false;
  bool _isChecking = true;
  int _mainScreenEpoch =
      0; // incremented to force full rebuild on storage switch

  @override
  void initState() {
    super.initState();
    _checkUser();
  }

  Future<void> _checkUser() async {
    final hasUser = await UserStorage.hasUser();
    var onboardingDone = await OnboardingService.isOnboardingComplete();

    // Migration: existing users who set up before the onboarding flag was added
    // should be treated as onboarding-complete.
    if (hasUser && !onboardingDone) {
      final configs = await UserStorage.getLLMConfigs();
      final hasValidConfig = configs.any((c) => c.isValid);
      if (hasValidConfig) {
        await OnboardingService.markOnboardingComplete();
        onboardingDone = true;
      }
    }

    if (mounted) {
      setState(() {
        _hasUser = hasUser;
        _onboardingComplete = onboardingDone;
        _isChecking = false;
      });
    }
  }

  void _onUserCreated() async {
    await OnboardingService.markOnboardingComplete();
    if (!mounted) return;
    setState(() {
      _hasUser = true;
      _onboardingComplete = true;
    });
  }

  /// Reset state and re-check user. Called after account deletion or storage switch.
  void resetAndRecheck() {
    setState(() {
      _hasUser = false;
      _onboardingComplete = false;
      _isChecking = true;
      _mainScreenEpoch++;
    });
    _checkUser();
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: AgentLogoLoading()));
    }
    if (!_hasUser || !_onboardingComplete) {
      return UserSetupScreen(onUserCreated: _onUserCreated);
    }
    return MultiProvider(
      key: ValueKey(_mainScreenEpoch),
      providers: [
        ChangeNotifierProvider<TimelineViewModel>(
          create: (c) =>
              TimelineViewModel(router: c.read<MemexRouter>())..init(),
        ),
      ],
      child: const MainScreen(),
    );
  }
}

class MemexApp extends StatefulWidget {
  const MemexApp({super.key, required this.router});

  final GoRouter router;

  @override
  State<MemexApp> createState() => _MemexAppState();
}

class _MemexAppState extends State<MemexApp> with WidgetsBindingObserver {
  bool _hasUser = false;
  bool _isLocked = true; // Default to locked on start
  bool _requiresAuth = true; // Whether actual authentication is required
  DateTime? _lastPausedTime; // Track when app was paused

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUser();
    _checkLockSettings();
  }

  Future<void> _checkLockSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isLockEnabled = prefs.getBool('app_lock_enabled') ?? false;
    if (mounted) {
      setState(() {
        // If lock is strictly required only when enabled, we update _isLocked.
        // Default _isLocked is true. If disabled, we unlock immediately.
        if (!isLockEnabled) {
          _isLocked = false;
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(
        LocalTaskExecutor.instance.recordGracefulShutdown(
          reason: 'app_lifecycle_paused',
        ),
      );
      unawaited(AgentBackgroundTaskService.instance.onAppPaused());
      _lastPausedTime = DateTime.now();
      _checkLockSettingsBeforeLocking();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(LocalTaskExecutor.instance.clearGracefulShutdownMarker());
      unawaited(AgentBackgroundTaskService.instance.onAppResumed());
      MemexRouter().scheduleAutoBackupCheck(trigger: 'foreground');
      _checkGracePeriod();
    } else if (state == AppLifecycleState.detached) {
      unawaited(
        LocalTaskExecutor.instance.recordGracefulShutdown(
          reason: 'app_lifecycle_detached',
        ),
      );
    }
  }

  Future<void> _checkLockSettingsBeforeLocking() async {
    final prefs = await SharedPreferences.getInstance();
    final isLockEnabled = prefs.getBool('app_lock_enabled') ?? false;
    if (isLockEnabled && mounted) {
      setState(() {
        _isLocked = true;
        _requiresAuth = false; // Just show privacy screen initially
      });
    }
  }

  Future<void> _checkGracePeriod() async {
    if (!_isLocked) return;

    if (_lastPausedTime != null) {
      final difference = DateTime.now().difference(_lastPausedTime!);
      // If less than 5 minutes, unlock automatically
      if (difference.inMinutes < 5) {
        if (mounted) {
          setState(() {
            _isLocked = false;
          });
        }
      } else {
        // More than 5 minutes, require auth
        if (mounted) {
          setState(() {
            _requiresAuth = true;
          });
        }
      }
    } else {
      // No pause time recorded (e.g. cold start), require auth
      if (mounted) {
        setState(() {
          _requiresAuth = true;
        });
      }
    }
  }

  Future<void> _checkUser() async {
    final hasUser = await UserStorage.hasUser();
    if (mounted) {
      setState(() {
        _hasUser = hasUser;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: UserStorage.localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp.router(
          title: 'Memex',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode
              .light, // Unified light mode, disabling adaptive dark mode
          locale: const Locale('zh'),
          routerConfig: widget.router,
          builder: (context, child) {
            return _AppActionReadiness(
              canHandleActions: !_isLocked,
              child: Stack(
                children: [
                  if (child != null) child,
                  if (_isLocked && _hasUser)
                    _requiresAuth
                        ? LockScreen(
                            onUnlock: () {
                              setState(() {
                                _isLocked = false;
                              });
                            },
                          )
                        : const PrivacyScreen(),
                ],
              ),
            );
          },
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh')],
        );
      },
    );
  }
}

class _AppActionReadiness extends InheritedWidget {
  const _AppActionReadiness({
    required this.canHandleActions,
    required super.child,
  });

  final bool canHandleActions;

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AppActionReadiness>()
            ?.canHandleActions ??
        true;
  }

  @override
  bool updateShouldNotify(_AppActionReadiness oldWidget) {
    return canHandleActions != oldWidget.canHandleActions;
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final EventBusService _eventBus = EventBusService.instance;
  StreamSubscription<String>? _appActionSubscription;
  bool _isInvalidConfigDialogShowing = false;
  bool _isErrorNotificationDialogShowing = false;
  bool _canHandleAppActions = false;
  bool _hasRequestedInitialAppActionCheck = false;
  bool _isAppActionCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    _eventBus.connect();
    _eventBus.addHandler(
        EventBusMessageType.invalidModelConfig, _handleInvalidModelConfig);
    _eventBus.addHandler(
        EventBusMessageType.errorNotification, _handleErrorNotification);
    AppActionService.instance.attach();
    _appActionSubscription = AppActionService.instance.actionStream.listen((_) {
      _consumeAppActionIfReady(waitForLateAction: false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _canHandleAppActions = _AppActionReadiness.of(context);
    if (!_canHandleAppActions) return;
    if (!_hasRequestedInitialAppActionCheck) {
      _hasRequestedInitialAppActionCheck = true;
      _consumeAppActionIfReady(waitForLateAction: true);
    } else if (AppActionService.instance.hasPendingAction) {
      _consumeAppActionIfReady(waitForLateAction: false);
    }
  }

  void _consumeAppActionIfReady({required bool waitForLateAction}) {
    if (!_canHandleAppActions || _isAppActionCheckScheduled) return;
    _isAppActionCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_canHandleAppActions) {
        _isAppActionCheckScheduled = false;
        return;
      }
      final action = waitForLateAction
          ? await AppActionService.instance.consumePendingAction()
          : AppActionService.instance.consumeIfPending();
      _isAppActionCheckScheduled = false;
      if (mounted &&
          _canHandleAppActions &&
          action == AppActionService.quickNoteAction) {
        _openCapture();
      }
    });
  }

  void _openCapture() => openSuperAgentDialog(context);

  @override
  void dispose() {
    _appActionSubscription?.cancel();
    AppActionService.instance.detach();
    _eventBus.removeHandler(
        EventBusMessageType.invalidModelConfig, _handleInvalidModelConfig);
    _eventBus.removeHandler(
        EventBusMessageType.errorNotification, _handleErrorNotification);
    super.dispose();
  }

  void _handleInvalidModelConfig(EventBusMessage message) {
    if (!mounted) return;
    if (message is! InvalidModelConfigMessage) return;

    // Check if dialog is already showing to prevent stacking
    if (_isInvalidConfigDialogShowing) return;

    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    setState(() => _isInvalidConfigDialogShowing = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(UserStorage.l10n.warning),
        content: Text(
          UserStorage.l10n.invalidModelConfigDetailed(
            message.agentId,
            message.configKey,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted) {
                setState(() => _isInvalidConfigDialogShowing = false);
              }
            },
            child: Text(UserStorage.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted) {
                setState(() => _isInvalidConfigDialogShowing = false);
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ModelConfigListPage(),
                ),
              );
            },
            child: Text(UserStorage.l10n.modelConfig),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isInvalidConfigDialogShowing = false);
      }
    });
  }

  void _handleErrorNotification(EventBusMessage message) {
    if (!mounted) return;
    if (message is! ErrorNotificationMessage) return;
    if (_isErrorNotificationDialogShowing) return;

    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    setState(() => _isErrorNotificationDialogShowing = true);

    final isAuthError = message.errorCategory == 'authenticationError';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(UserStorage.l10n.llmErrorDialogTitle),
        content: Text(message.errorMessage),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted) {
                setState(() => _isErrorNotificationDialogShowing = false);
              }
            },
            child: Text(UserStorage.l10n.cancel),
          ),
          if (isAuthError)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (mounted) {
                  setState(() => _isErrorNotificationDialogShowing = false);
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ModelConfigListPage(),
                  ),
                );
              },
              child: Text(UserStorage.l10n.goToModelConfig),
            ),
        ],
      ),
    ).then((_) {
      if (mounted) setState(() => _isErrorNotificationDialogShowing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        bottom: false,
        child: TimelineScreen(
          viewModel: context.read<TimelineViewModel>(),
          onInputTap: _openCapture,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCapture,
        icon: const Icon(Icons.edit_outlined),
        label: Text(UserStorage.l10n.journalCapture),
      ),
    );
  }
}
