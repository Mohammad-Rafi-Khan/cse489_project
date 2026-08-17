import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'providers/auth_provider.dart';
import 'providers/product_provider.dart';
import 'providers/task_provider.dart';

// Screens
import 'screens/auth/login_screen.dart';
import 'screens/auth/registration_screen.dart';
import 'screens/employee/employee_dashboard.dart';
import 'screens/employee/my_tasks_screen.dart';
import 'screens/manager/manager_dashboard.dart';
import 'screens/manager/assign_task_screen.dart';
import 'screens/manager/assigned_tasks_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/products/product_list_screen.dart';
import 'screens/products/product_form_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase — handles auth session persistence automatically
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  runApp(const RetailFlowApp());
}

class RetailFlowApp extends StatelessWidget {
  const RetailFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
      ],
      child: MaterialApp(
        title: 'RetailFlow',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.light,
          ),
          cardTheme: CardThemeData(
            elevation: 1,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            showCloseIcon: true,
          ),
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        // Startup screen checks for an existing session and routes accordingly
        home: const _AppStartupScreen(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegistrationScreen(),
          '/employee-dashboard': (context) => const EmployeeDashboardScreen(),
          '/my-tasks': (context) => const MyTasksScreen(),
          '/manager-dashboard': (context) => const ManagerDashboardScreen(),
          '/assign-task': (context) => const AssignTaskScreen(),
          '/assigned-tasks': (context) => const AssignedTasksScreen(),
          '/admin-dashboard': (context) => const AdminDashboardScreen(),
          '/products': (context) => const ProductListScreen(),
          '/product-form': (context) => const ProductFormScreen(),
        },
      ),
    );
  }
}

/// Shown while the app checks for an existing Supabase session at startup.
/// Routes the user to the correct screen without showing the login screen
/// if they are already signed in.
class _AppStartupScreen extends StatefulWidget {
  const _AppStartupScreen();

  @override
  State<_AppStartupScreen> createState() => _AppStartupScreenState();
}

class _AppStartupScreenState extends State<_AppStartupScreen> {
  @override
  void initState() {
    super.initState();
    // Wait for the first frame so that Providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  Future<void> _checkSession() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.checkExistingSession();

    if (!mounted) return;

    if (authProvider.isAuthenticated) {
      _routeByRole(authProvider.profile?.role);
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _routeByRole(String? role) {
    switch (role) {
      case 'manager':
        Navigator.pushReplacementNamed(context, '/manager-dashboard');
        break;
      case 'admin':
        Navigator.pushReplacementNamed(context, '/admin-dashboard');
        break;
      default:
        Navigator.pushReplacementNamed(context, '/employee-dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.store_rounded,
                    size: 46,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'RetailFlow',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Retail Management System',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.55),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
