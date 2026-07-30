import 'package:flutter/material.dart';
import '../common/theme/theme.dart';
import 'routes/customer_routes.dart';

class CustomerApp extends StatelessWidget {
  static final ValueNotifier<bool> isPinkTheme = ValueNotifier<bool>(false);
  static final ValueNotifier<Map<String, dynamic>?> activePromo = ValueNotifier<Map<String, dynamic>?>(null);
  final String initialRoute;

  const CustomerApp({super.key, this.initialRoute = '/'});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isPinkTheme,
      builder: (context, isPink, _) {
        return MaterialApp(
          title: 'Torkk',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          darkTheme: AppTheme.getTheme(isPink: isPink),
          initialRoute: initialRoute,
          routes: CustomerRoutes.routes,
        );
      },
    );
  }
}
