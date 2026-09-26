import 'dart:async';

import 'package:clock/clock.dart';
import 'package:dynamic_system_colors/dynamic_system_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';
import 'package:mona/controllers/notification_planner.dart';
import 'package:mona/controllers/notification_scheduler.dart';
import 'package:mona/data/providers/medication_intake_provider.dart';
import 'package:mona/data/providers/medication_schedule_provider.dart';
import 'package:mona/distribution.dart';
import 'package:mona/i18n/build_context_extensions.dart';
import 'package:mona/i18n/locale_provider.dart';
import 'package:mona/i18n/tok_localizations.dart';
import 'package:mona/services/home_widget_service.dart';
import 'package:mona/services/notification_service.dart';
import 'package:mona/services/preferences_service.dart';
import 'package:mona/theme/app_theme_controller.dart';
import 'package:mona/theme/material_ui_theme.dart';
import 'package:provider/provider.dart';
import 'ui/views/main_page.dart';

class MonaApp extends StatefulWidget {
  const MonaApp({super.key});

  @override
  State<MonaApp> createState() => _MonaAppState();
}

class _MonaAppState extends State<MonaApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _mainPageKey = GlobalKey<MainPageState>();
  StreamSubscription<Uri?>? _widgetClickSubscription;
  String? _lastTimeZone;
  late MedicationScheduleProvider _medicationScheduleProvider;
  late MedicationIntakeProvider _medicationIntakeProvider;
  late PreferencesService _preferencesService;
  late LocaleProvider _localeProvider;
  late NotificationScheduler _notificationScheduler;
  final HomeWidgetService _homeWidgetService = HomeWidgetService();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastTimeZone = clock.now().timeZoneOffset.toString();

    if (isIOS) _listenForWidgetTaps();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService().initialize();
      if (!mounted) return;
      _medicationScheduleProvider = context.read<MedicationScheduleProvider>();
      _medicationIntakeProvider = context.read<MedicationIntakeProvider>();
      _preferencesService = context.read<PreferencesService>();
      _localeProvider = context.read<LocaleProvider>();
      _notificationScheduler = NotificationScheduler(
        NotificationPlanner(
            _medicationIntakeProvider, _medicationScheduleProvider),
        _preferencesService,
      );
      _initialized = true;

      _medicationScheduleProvider.addListener(_regenerateNotifications);
      _medicationIntakeProvider.addListener(_regenerateNotifications);
      _preferencesService.addListener(_regenerateNotifications);
      _regenerateNotifications();

      _medicationIntakeProvider.addListener(_regenerateHomeWidget);
      if (isIOS) {
        _medicationScheduleProvider.addListener(_regenerateHomeWidget);
        _preferencesService.addListener(_regenerateHomeWidget);
      }
      _localeProvider.addListener(_regenerateHomeWidget);
      _regenerateHomeWidget();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetClickSubscription?.cancel();
    if (_initialized) {
      _medicationScheduleProvider.removeListener(_regenerateNotifications);
      _medicationIntakeProvider.removeListener(_regenerateNotifications);
      _preferencesService.removeListener(_regenerateNotifications);
      _medicationIntakeProvider.removeListener(_regenerateHomeWidget);
      if (isIOS) {
        _medicationScheduleProvider.removeListener(_regenerateHomeWidget);
        _preferencesService.removeListener(_regenerateHomeWidget);
      }
      _localeProvider.removeListener(_regenerateHomeWidget);
    }
    super.dispose();
  }

  Future<void> _listenForWidgetTaps() async {
    try {
      await HomeWidget.setAppGroupId(HomeWidgetService.appGroupId);
      if (!mounted) return;
      _widgetClickSubscription =
          HomeWidget.widgetClicked.listen(_openWidgetUrl);
      _openWidgetUrl(await HomeWidget.initiallyLaunchedFromHomeWidget());
    } catch (error) {
      debugPrint('Could not initialize widget tap navigation: $error');
    }
  }

  void _openWidgetUrl(Uri? url) {
    if (!HomeWidgetService.isHomeWidgetUrl(url)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      _mainPageKey.currentState?.showHome();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _regenerateNotifications() {
    if (!_initialized || !mounted) return;

    final locale = context.read<LocaleProvider>().locale;
    _notificationScheduler.regenerateAll(locale.intlLanguageTag);
  }

  void _regenerateHomeWidget() {
    if (!_initialized || !mounted) return;

    _homeWidgetService
        .sync(
      _medicationIntakeProvider,
      _medicationScheduleProvider,
      _localeProvider,
    )
        .catchError((Object error) {
      debugPrint('Could not sync home widget: $error');
    });
  }

  void _checkTimezoneChange() {
    final currentTimezone = clock.now().timeZoneOffset.toString();
    if (_lastTimeZone != currentTimezone) {
      _lastTimeZone = currentTimezone;
      _regenerateNotifications();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkTimezoneChange();
      if (isIOS) _regenerateHomeWidget();
    } else if (state == AppLifecycleState.paused) {
      _regenerateHomeWidget();
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (!_initialized) return;
    _localeProvider.updateSystemLocale(
      locales?.first ?? WidgetsBinding.instance.platformDispatcher.locale,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppThemeProvider>();
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final themes = context.read<AppThemeProvider>().buildThemeData(
              systemLight: lightDynamic,
              systemDark: darkDynamic,
            );
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Mona',
          locale: context.watch<LocaleProvider>().locale,
          supportedLocales: context.watch<LocaleProvider>().supportedLocales,
          localizationsDelegates: const [
            TokMaterialLocalizationsDelegate(),
            TokCupertinoLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: themes.theme,
          darkTheme: themes.darkTheme,
          themeMode: ThemeMode.system,
          builder: (context, child) => withMaterialUiTheme(
            scheme: Theme.of(context).colorScheme,
            child: child ?? const SizedBox.shrink(),
          ),
          home: MainPage(key: _mainPageKey),
        );
      },
    );
  }
}
