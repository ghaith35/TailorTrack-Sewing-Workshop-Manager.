// lib/main.dart

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'sewing/sewing_dashboard.dart';
import 'embroidery/embroidery_dashboard.dart';
import 'design/design_dashboard.dart';

/// Holds the discovered server URI (e.g. http://192.168.0.10:8888)
Uri? globalServerUri;

/// Listens for your server's UDP broadcasts on port 9999.
class ServerDiscovery {
  RawDatagramSocket? _socket;
  final _controller = StreamController<Uri>.broadcast();

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 9999);
    _socket!
      ..broadcastEnabled = true
      ..listen(_onData);
  }

  void _onData(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket!.receive();
    if (dg == null) return;

    final msg = utf8.decode(dg.data);
    if (!msg.startsWith('SEWING_SERVER:')) return;

    final parts = msg.split(':');
    if (parts.length < 2) return;

    final port = parts[1];
    final ip   = dg.address.address;
    final uri  = Uri.parse('http://$ip:$port');

    globalServerUri = uri;
    _controller.add(uri);
  }

  Stream<Uri> get onServerFound => _controller.stream;

  void dispose() {
    _socket?.close();
    _controller.close();
  }
}

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? _token, _role;
  bool _loading     = true;
  bool _discovering = true;
  late ServerDiscovery _disc;

  @override
  void initState() {
    super.initState();
    _loadAuth();
    _startDiscovery();
  }

  Future<void> _loadAuth() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _token   = prefs.getString('auth_token');
      _role    = prefs.getString('auth_role');
      _loading = false;
    });
  }

  Future<void> _startDiscovery() async {
    _disc = ServerDiscovery();
    await _disc.start();
    // once we get the first broadcast, stop showing the spinner
    _disc.onServerFound.first.then((_) {
      if (!mounted) return;
      setState(() => _discovering = false);
    });
  }

  Future<void> _onLogin(String token, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('auth_role', role);
    setState(() {
      _token = token;
      _role  = role;
    });
  }

  Future<void> _onLogout(BuildContext ctx) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_role');
    Navigator.of(ctx).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  void dispose() {
    _disc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // wait for both auth _and_ server discovery
    if (_loading || _discovering || globalServerUri == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'نظام إدارة المعمل',
      theme: ThemeData(
        fontFamily: 'NotoSansArabic',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar')],
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: _token == null
          ? LoginPage(onLogin: _onLogin)
          : HomePage(role: _role!, onLogout: _onLogout),
      routes: {
        '/login':       (ctx) => LoginPage(onLogin: _onLogin),
        '/home':        (ctx) => HomePage(role: _role!, onLogout: _onLogout),
        '/sewing':      (ctx) => SewingDashboard(role: _role!),
        '/embroidery':  (ctx) => EmbroideryDashboard(role: _role!),
        '/design':      (ctx) => const DesignDashboard(),
        '/manage-users':(ctx) => _token == null
                             ? const ErrorScreen('Unauthorized access')
                             : ManageUsersPage(token: _token!, role: _role!),
      },
    );
  }
}

class ErrorScreen extends StatelessWidget {
  final String message;
  const ErrorScreen(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('خطأ')),
        body: Center(child: Text(message, style: const TextStyle(fontSize: 18))),
      );
}

class LoginPage extends StatefulWidget {
  final Future<void> Function(String token, String role) onLogin;
  const LoginPage({super.key, required this.onLogin});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  String _user = '', _pass = '';
  String? _err;
  bool _loading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() {
      _loading = true;
      _err     = null;
    });

    final base = globalServerUri!;
    try {
      final resp = await http.post(
        Uri.parse('${base.toString()}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': _user, 'password': _pass}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        await widget.onLogin(data['token'], data['role']);
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        setState(() => _err = 'فشل في تسجيل الدخول');
      }
    } catch (_) {
      setState(() => _err = 'خطأ في الاتصال');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول'), backgroundColor: Colors.teal),
      body: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width > 600
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          child: Card(
            color: Colors.teal[50],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock, size: 64, color: Colors.teal),
                  const SizedBox(height: 16),
                  Text(
                    'مرحبا بك في نظام إدارة المعمل',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal[800]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_err != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(children: [
                        const Icon(Icons.error, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_err!, style: const TextStyle(color: Colors.red))),
                      ]),
                    ),
                  TextFormField(
                    decoration: InputDecoration(
                      labelText: 'اسم المستخدم',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                    onSaved: (v) => _user = v!.trim(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    obscureText: true,
                    validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                    onSaved: (v) => _pass = v!.trim(),
                  ),
                  const SizedBox(height: 24),
                  _loading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('دخول', style: TextStyle(fontSize: 18, color: Colors.white)),
                        ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  final String role;
  final Future<void> Function(BuildContext) onLogout;
  const HomePage({super.key, required this.role, required this.onLogout});

  List<Map<String, dynamic>> getSections() {
    if (role == 'Manager') {
      return [
        {'title': 'التطريز', 'icon': Icons.format_paint_outlined, 'route': '/embroidery'},
      ];
    } else if (role == 'Accountant') {
      return [
        {'title': 'الخياطة', 'icon': Icons.local_offer_outlined, 'route': '/sewing'},
      ];
    }
    return [
      {'title': 'الخياطة', 'icon': Icons.local_offer_outlined, 'route': '/sewing'},
      {'title': 'التطريز', 'icon': Icons.format_paint_outlined, 'route': '/embroidery'},
      {'title': 'التصميم', 'icon': Icons.design_services_outlined, 'route': '/design'},
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sections = getSections();
    return Scaffold(
      appBar: AppBar(title: const Text('')),
      drawer: Drawer(
        child: ListView(children: [
          RoleGate(
            allowed: const ['Admin', 'SuperAdmin'],
            child: ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: const Text('إدارة الحسابات'),
              onTap: () => Navigator.pushNamed(context, '/manage-users'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('خروج'),
            onTap: () => onLogout(context),
          ),
        ]),
      ),
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: sections.map((s) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () => Navigator.pushNamed(context, s['route'] as String),
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(s['icon'] as IconData, size: 48, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(s['title'] as String, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class ManageUsersPage extends StatefulWidget {
  final String token, role;
  const ManageUsersPage({super.key, required this.token, required this.role});
  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage> {
  List<Map<String, dynamic>> users = [];
  bool loading = false;

  Future<Map<String, String>> get _authHeader async => {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json'
      };

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => loading = true);
    final rolesQuery = widget.role == 'Admin' ? '?roles=Manager,Accountant' : '';
    final base       = globalServerUri!;
    final resp = await http.get(
      Uri.parse('${base.toString()}/auth/admin/users$rolesQuery'),
      headers: await _authHeader,
    );
    if (resp.statusCode == 200) {
      users = (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>();
      setState(() => users = users);
    }
    setState(() => loading = false);
  }

  Future<void> _createUser() async {
    final usernameCtl = TextEditingController();
    final passwordCtl = TextEditingController();
    String role = 'Manager';
    final allowed = widget.role == 'Admin'
        ? ['Manager', 'Accountant']
        : ['Manager', 'Accountant', 'Admin', 'SuperAdmin'];

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSB) => AlertDialog(
          scrollable: true,
          title: const Text('إنشاء حساب جديد'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: usernameCtl,
              decoration: const InputDecoration(labelText: 'اسم المستخدم'),
              onChanged: (_) => setSB(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passwordCtl,
              decoration: const InputDecoration(labelText: 'كلمة المرور الأولية'),
              obscureText: true,
              onChanged: (_) => setSB(() {}),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'الدور'),
              value: role,
              items: allowed.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => setSB(() => role = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: usernameCtl.text.isNotEmpty && passwordCtl.text.isNotEmpty
                  ? () async {
                      final base = globalServerUri!;
                      final resp = await http.post(
                        Uri.parse('${base.toString()}/auth/admin/users'),
                        headers: await _authHeader,
                        body: jsonEncode({
                          'username': usernameCtl.text.trim(),
                          'initialPassword': passwordCtl.text,
                          'role': role,
                        }),
                      );
                      Navigator.pop(ctx);
                      if (resp.statusCode == 200) _fetchUsers();
                    }
                  : null,
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetPassword(int userId) async {
    final newPassCtl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSB) => AlertDialog(
          scrollable: true,
          title: const Text('إعادة تعيين كلمة المرور'),
          content: TextField(
            controller: newPassCtl,
            decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
            obscureText: true,
            onChanged: (_) => setSB(() {}),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: newPassCtl.text.isNotEmpty
                  ? () async {
                      final base = globalServerUri!;
                      final resp = await http.post(
                        Uri.parse('${base.toString()}/auth/admin/users/$userId/reset-password'),
                        headers: await _authHeader,
                        body: jsonEncode({'newPassword': newPassCtl.text}),
                      );
                      Navigator.pop(ctx);
                      if (resp.statusCode == 200) _fetchUsers();
                    }
                  : null,
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUser(int userId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل تريد حذف هذا الحساب نهائيًا؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final base = globalServerUri!;
    final resp = await http.delete(
      Uri.parse('${base.toString()}/auth/admin/users/$userId'),
      headers: await _authHeader,
    );
    if (resp.statusCode == 200) _fetchUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة الحسابات')),
      floatingActionButton: RoleGate(
        allowed: const ['Admin', 'SuperAdmin'],
        child: FloatingActionButton(
          onPressed: _createUser,
          child: const Icon(Icons.add),
          tooltip: 'إنشاء حساب',
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: users.length,
              itemBuilder: (_, i) {
                final u = users[i];
                return ListTile(
                  title: Text(u['username']),
                  subtitle: Text(u['role']),
                  trailing: PopupMenuButton<String>(
                    onSelected: (a) {
                      if (a == 'reset') _resetPassword(u['id']);
                      if (a == 'delete') _deleteUser(u['id']);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'reset', child: Text('إعادة تعيين كلمة المرور')),
                      PopupMenuItem(value: 'delete', child: Text('حذف الحساب')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class RoleGate extends StatelessWidget {
  final List<String> allowed;
  final Widget child;
  const RoleGate({super.key, required this.allowed, required this.child});
  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_MyAppState>();
    final role = state?._role ?? '';
    return allowed.contains(role) ? child : const SizedBox.shrink();
  }
}
