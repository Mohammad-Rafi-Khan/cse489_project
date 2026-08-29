import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'providers/attendance_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/branch_provider.dart';
import 'providers/issue_provider.dart';
import 'providers/leave_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/points_provider.dart';
import 'providers/product_provider.dart';
import 'providers/reports_provider.dart';
import 'providers/sales_provider.dart';
import 'providers/shift_provider.dart';
import 'providers/task_provider.dart';
import 'providers/user_management_provider.dart';

// Screens
import 'screens/admin/admin_dashboard.dart';
import 'screens/admin/branch_management_screen.dart';
import 'screens/admin/sales_import_screen.dart';
import 'screens/admin/user_management_screen.dart';
import 'screens/attendance/attendance_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/registration_screen.dart';
import 'screens/employee/employee_dashboard.dart';
import 'screens/employee/my_schedule_screen.dart';
import 'screens/employee/my_tasks_screen.dart';
import 'screens/employee/points_history_screen.dart';
import 'screens/issues/issue_report_screen.dart';
import 'screens/leave/leave_request_screen.dart';
import 'screens/manager/assign_task_screen.dart';
import 'screens/manager/assigned_tasks_screen.dart';
import 'screens/manager/manager_dashboard.dart';
import 'screens/manager/sales_performance_screen.dart';
import 'screens/manager/sales_target_screen.dart';
import 'screens/manager/shift_management_screen.dart';
import 'screens/manager/task_template_screen.dart';
import 'screens/notifications/notification_center_screen.dart';
import 'screens/products/product_form_screen.dart';
import 'screens/products/product_list_screen.dart';
import 'screens/reports/reports_screen.dart';

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
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => ShiftProvider()),
        ChangeNotifierProvider(create: (_) => SalesProvider()),
        ChangeNotifierProvider(create: (_) => BranchProvider()),
        ChangeNotifierProvider(create: (_) => UserManagementProvider()),
        ChangeNotifierProvider(create: (_) => IssueProvider()),
        ChangeNotifierProvider(create: (_) => LeaveProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => PointsProvider()),
        ChangeNotifierProvider(create: (_) => ReportsProvider()),
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
          '/login': (ctx) => const LoginScreen(),
          '/register': (ctx) => const RegistrationScreen(),
          '/employee-dashboard': (ctx) => const EmployeeDashboardScreen(),
          '/my-tasks': (ctx) => const MyTasksScreen(),
          '/points-history': (ctx) => const _RouteGuard(
            requiredRoles: {'employee', 'manager', 'admin'},
            child: PointsHistoryScreen(),
          ),
          '/my-schedule': (ctx) => const _RouteGuard(
            requiredRoles: {'employee', 'manager', 'admin'},
            child: MyScheduleScreen(),
          ),
          '/notifications': (ctx) => const _RouteGuard(
            requiredRoles: {'employee', 'manager', 'admin'},
            child: NotificationCenterScreen(),
          ),
          '/products': (ctx) => const _RouteGuard(
            requiredRoles: {'employee', 'manager', 'admin'},
            child: ProductListScreen(),
          ),
          '/issues': (ctx) => const _RouteGuard(
            requiredRoles: {'employee', 'manager', 'admin'},
            child: IssueReportScreen(),
          ),
          '/leave-requests': (ctx) => const _RouteGuard(
            requiredRoles: {'employee', 'manager', 'admin'},
            child: LeaveRequestScreen(),
          ),
          '/reports': (ctx) => const _RouteGuard(
            requiredRoles: {'employee', 'manager', 'admin'},
            child: ReportsScreen(),
          ),
          '/attendance': (ctx) => const _RouteGuard(
            requiredRoles: {'employee', 'manager', 'admin'},
            child: AttendanceScreen(),
          ),
          // Manager-level routes
          '/manager-dashboard': (ctx) => const _RouteGuard(
            requiredRoles: {'manager', 'admin'},
            child: ManagerDashboardScreen(),
          ),
          '/assign-task': (ctx) => const _RouteGuard(
            requiredRoles: {'manager', 'admin'},
            child: AssignTaskScreen(),
          ),
          '/assigned-tasks': (ctx) => const _RouteGuard(
            requiredRoles: {'manager', 'admin'},
            child: AssignedTasksScreen(),
          ),
          '/task-templates': (ctx) => const _RouteGuard(
            requiredRoles: {'manager', 'admin'},
            child: TaskTemplateScreen(),
          ),
          '/shift-management': (ctx) => const _RouteGuard(
            requiredRoles: {'manager', 'admin'},
            child: ShiftManagementScreen(),
          ),
          '/sales-performance': (ctx) => const _RouteGuard(
            requiredRoles: {'manager', 'admin'},
            child: SalesPerformanceScreen(),
          ),
          // Admin-only routes
          '/admin-dashboard': (ctx) => const _RouteGuard(
            requiredRoles: {'admin'},
            child: AdminDashboardScreen(),
          ),
          '/branch-management': (ctx) => const _RouteGuard(
            requiredRoles: {'admin'},
            child: BranchManagementScreen(),
          ),
          '/user-management': (ctx) => const _RouteGuard(
            requiredRoles: {'admin'},
            child: UserManagementScreen(),
          ),
          '/sales-targets': (ctx) => const _RouteGuard(
            requiredRoles: {'manager', 'admin'},
            child: SalesTargetScreen(),
          ),
          '/sales-import': (ctx) => const _RouteGuard(
            requiredRoles: {'admin'},
            child: SalesImportScreen(),
          ),
          '/product-form': (ctx) => const _RouteGuard(
            requiredRoles: {'manager', 'admin'},
            child: ProductFormScreen(),
          ),
        },
      ),
    );
  }
}

/// Shown while the app checks for an existing Supabase session at startup.
class _AppStartupScreen extends StatefulWidget {
  const _AppStartupScreen();

  @override
  State<_AppStartupScreen> createState() => _AppStartupScreenState();
}

class _AppStartupScreenState extends State<_AppStartupScreen> {
  @override
  void initState() {
    super.initState();
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
                    color: colorScheme.onSurface.withValues(alpha: 0.55),
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

/// Guards a route to users whose role is in [requiredRoles].
///
/// When a user navigates to a guarded route without the required role, they are
/// immediately redirected to their correct role-appropriate dashboard. This is a
/// defence-in-depth measure — the database RLS policies are the primary security
/// control, but this prevents confusing UX from showing admin screens to employees.
class _RouteGuard extends StatelessWidget {
  final Set<String> requiredRoles;
  final Widget child;

  const _RouteGuard({required this.requiredRoles, required this.child});

  @override
  Widget build(BuildContext context) {
    final role = context.read<AuthProvider>().profile?.role;

    if (role != null && requiredRoles.contains(role)) {
      return child;
    }

    // Redirect asynchronously after build to avoid calling Navigator during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final destination = switch (role) {
        'admin' => '/admin-dashboard',
        'manager' => '/manager-dashboard',
        _ => '/employee-dashboard',
      };
      Navigator.pushReplacementNamed(context, destination);
    });

    // Show spinner while redirecting
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
