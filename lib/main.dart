import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

const String apiBase = 'https://loboc.rgbwater.com/api';
const Color primaryBlue = Color(0xFF1565C0);
const Color lightBlue = Color(0xFF1976D2);
const Color accentBlue = Color(0xFF42A5F5);

void main() => runApp(const MeterReaderApp());

class MeterReaderApp extends StatelessWidget {
  const MeterReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loboc Meter Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: primaryBlue,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// ─── AUTH GATE ─────────────────────────────────────────────
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) {
      try {
        final resp = await http.get(
          Uri.parse('$apiBase/auth/me'),
          headers: _authHeaders(token),
        ).timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          setState(() { _loggedIn = true; _checking = false; });
          return;
        }
      } catch (_) {
        // Offline but have token - trust local
        final user = prefs.getString('auth_user');
        if (user != null) {
          setState(() { _loggedIn = true; _checking = false; });
          return;
        }
      }
      await prefs.remove('auth_token');
      await prefs.remove('auth_user');
    }
    setState(() { _loggedIn = false; _checking = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_loggedIn) return HomeScreen(onLogout: () => setState(() => _loggedIn = false));
    return LoginScreen(onLoginSuccess: () => setState(() => _loggedIn = true));
  }
}

Map<String, String> _authHeaders(String token) => {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Authorization': 'Bearer $token',
};

Future<String?> _getToken() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('auth_token');
}

// ─── LOGIN SCREEN ──────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const LoginScreen({super.key, required this.onLoginSuccess});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  Future<void> _login() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter username and password');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await http.post(
        Uri.parse('$apiBase/auth/login'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(resp.body);
      if (resp.statusCode == 200 && data['status'] == 'ok') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', data['token']);
        await prefs.setString('auth_user', json.encode(data['user']));
        widget.onLoginSuccess();
      } else {
        setState(() => _error = data['message'] ?? 'Login failed');
      }
    } catch (e) {
      setState(() => _error = 'Cannot connect to server');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [primaryBlue, lightBlue, accentBlue],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: primaryBlue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.water_drop, color: primaryBlue, size: 40),
                    ),
                    const SizedBox(height: 16),
                    const Text('Loboc Meter Reader',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryBlue),
                    ),
                    const SizedBox(height: 4),
                    Text('Sign in to continue', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _usernameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Username', prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: TextStyle(color: Colors.red[700], fontSize: 13))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity, height: 48,
                      child: FilledButton(
                        onPressed: _loading ? null : _login,
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryBlue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _loading
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Sign In', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() { _usernameCtrl.dispose(); _passwordCtrl.dispose(); super.dispose(); }
}

// ─── HOME SCREEN ───────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const HomeScreen({super.key, required this.onLogout});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  List<dynamic> _barangays = [];
  List<dynamic> _consumers = [];
  Map<String, dynamic>? _selectedBarangay;
  bool _loading = false;
  String _syncStatus = '';
  String _readingDate = '';
  final Map<int, TextEditingController> _readingControllers = {};
  final _searchCtrl = TextEditingController();

  Map<String, dynamic> _pendingReadings = {};
  Map<String, List<dynamic>> _cachedConsumers = {};
  List<dynamic> _cachedBarangays = [];

  Timer? _syncTimer;
  Timer? _autoDownloadTimer;
  String? _userName;
  String? _userRole;
  bool _autoDownloading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _readingDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _loadUserInfo();
    _loadOfflineData();
    _loadBarangays();
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) => _syncPending());
    _autoDownloadTimer = Timer.periodic(const Duration(minutes: 10), (_) => _autoDownloadIfOnline());
    Future.delayed(const Duration(seconds: 3), () => _autoDownloadIfOnline());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _autoDownloadTimer?.cancel();
    for (var c in _readingControllers.values) c.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString('auth_user');
    if (userStr != null) {
      final user = json.decode(userStr);
      setState(() { _userName = user['name']; _userRole = user['role']; });
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    if (token == null) return {'Content-Type': 'application/json', 'Accept': 'application/json'};
    return _authHeaders(token);
  }

  Future<http.Response> _authGet(String path) async {
    final headers = await _getHeaders();
    final resp = await http.get(Uri.parse('$apiBase$path'), headers: headers).timeout(const Duration(seconds: 15));
    if (resp.statusCode == 401) _handleUnauth();
    return resp;
  }

  Future<http.Response> _authPost(String path, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final resp = await http.post(Uri.parse('$apiBase$path'), headers: headers, body: json.encode(data)).timeout(const Duration(seconds: 15));
    if (resp.statusCode == 401) _handleUnauth();
    return resp;
  }

  void _handleUnauth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_user');
    widget.onLogout();
  }

  Future<void> _loadOfflineData() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingStr = prefs.getString('pending_readings');
    final barangaysStr = prefs.getString('cached_barangays');
    final consumersStr = prefs.getString('cached_consumers');
    if (pendingStr != null) _pendingReadings = json.decode(pendingStr);
    if (barangaysStr != null) _cachedBarangays = json.decode(barangaysStr);
    if (consumersStr != null) {
      _cachedConsumers = (json.decode(consumersStr) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, List<dynamic>.from(v)));
    }
    setState(() {});
  }

  Future<void> _saveOfflineData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_readings', json.encode(_pendingReadings));
    await prefs.setString('cached_barangays', json.encode(_cachedBarangays));
    await prefs.setString('cached_consumers', json.encode(_cachedConsumers));
  }

  Future<void> _autoDownloadIfOnline() async {
    if (_autoDownloading) return;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return;
      _autoDownloading = true;
      if (_pendingReadings.isNotEmpty) await _syncPending();
      await _downloadAllData(silent: true);
      _autoDownloading = false;
    } catch (_) {
      _autoDownloading = false;
    }
  }

  Future<void> _loadBarangays() async {
    setState(() => _loading = true);
    try {
      final resp = await _authGet('/reader/barangays');
      if (resp.statusCode == 200) {
        _barangays = json.decode(resp.body);
        _cachedBarangays = _barangays;
        await _saveOfflineData();
      }
    } catch (e) {
      _barangays = _cachedBarangays;
    }
    setState(() => _loading = false);
  }

  Future<void> _loadConsumers(Map<String, dynamic> barangay) async {
    setState(() { _selectedBarangay = barangay; _loading = true; });
    try {
      final resp = await _authGet('/reader/consumers/${barangay['id']}');
      if (resp.statusCode == 200) {
        _consumers = json.decode(resp.body);
        _cachedConsumers[barangay['id'].toString()] = _consumers;
        await _saveOfflineData();
      }
    } catch (e) {
      _consumers = _cachedConsumers[barangay['id'].toString()] ?? [];
    }
    _readingControllers.clear();
    for (var c in _consumers) {
      final key = '${c['id']}_$_readingDate';
      final existing = _pendingReadings[key];
      _readingControllers[c['id']] = TextEditingController(text: existing?.toString() ?? '');
    }
    setState(() => _loading = false);
  }

  void _saveReading(int consumerId, String value) {
    final key = '${consumerId}_$_readingDate';
    if (value.trim().isNotEmpty) {
      _pendingReadings[key] = int.tryParse(value.trim()) ?? value.trim();
    } else {
      _pendingReadings.remove(key);
    }
    _saveOfflineData();
    setState(() {});
  }

  Future<void> _syncPending() async {
    if (_pendingReadings.isEmpty) return;
    setState(() => _syncStatus = 'Syncing...');
    final readings = <Map<String, dynamic>>[];
    for (var entry in _pendingReadings.entries) {
      final parts = entry.key.split('_');
      if (parts.length >= 2) {
        readings.add({
          'consumer_id': int.parse(parts[0]),
          'reading_date': parts.sublist(1).join('_'),
          'meter_reading': entry.value,
        });
      }
    }
    try {
      final resp = await _authPost('/reader/sync', {'readings': readings});
      if (resp.statusCode == 200) {
        final result = json.decode(resp.body);
        if (result['status'] == 'ok') {
          _pendingReadings.clear();
          await _saveOfflineData();
          setState(() => _syncStatus = 'Synced ${result['saved']} readings');
        } else {
          setState(() => _syncStatus = 'Sync error');
        }
      }
    } catch (e) {
      setState(() => _syncStatus = 'Offline - will retry');
    }
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _syncStatus = '');
    });
  }

  Future<void> _downloadAllData({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final bResp = await _authGet('/reader/barangays');
      if (bResp.statusCode == 200) {
        _cachedBarangays = json.decode(bResp.body);
        _barangays = _cachedBarangays;
        int totalConsumers = 0;
        for (var b in _cachedBarangays) {
          final cResp = await _authGet('/reader/consumers/${b['id']}');
          if (cResp.statusCode == 200) {
            final consumers = json.decode(cResp.body);
            _cachedConsumers[b['id'].toString()] = List<dynamic>.from(consumers);
            totalConsumers += consumers.length as int;
          }
        }
        await _saveOfflineData();
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloaded $totalConsumers consumers from ${_cachedBarangays.length} barangays'), backgroundColor: primaryBlue),
          );
        }
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    if (!silent) setState(() => _loading = false);
    if (silent && mounted) setState(() {});
  }

  Future<void> _logout() async {
    try { await _authPost('/auth/logout', {}); } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_user');
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loboc Meter Reader'),
        leading: _selectedBarangay != null && _currentTab == 0
            ? IconButton(icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() { _selectedBarangay = null; _consumers = []; _searchCtrl.clear(); }))
            : null,
        actions: [
          if (_syncStatus.isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Text(_syncStatus, style: const TextStyle(fontSize: 12)))),
          if (_pendingReadings.isNotEmpty)
            Badge(label: Text('${_pendingReadings.length}'),
              child: IconButton(icon: const Icon(Icons.sync), onPressed: _syncPending, tooltip: 'Sync now')),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        indicatorColor: primaryBlue.withValues(alpha: 0.15),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.water_drop), label: 'Readings'),
          NavigationDestination(
            icon: Badge(isLabelVisible: _pendingReadings.isNotEmpty, label: Text('${_pendingReadings.length}'),
              child: const Icon(Icons.pending_actions)),
            label: 'Pending',
          ),
          const NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentTab) {
      case 0: return _selectedBarangay != null ? _buildConsumerList() : _buildBarangayList();
      case 1: return _buildPendingList();
      case 2: return _buildSettings();
      default: return const SizedBox();
    }
  }

  Widget _buildBarangayList() {
    return Column(children: [
      Container(
        width: double.infinity, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryBlue.withValues(alpha: 0.08), primaryBlue.withValues(alpha: 0.03)])),
        child: Column(children: [
          const Icon(Icons.water_drop, size: 40, color: primaryBlue),
          const SizedBox(height: 8),
          Text('Reading Date: $_readingDate', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text('${_pendingReadings.length} pending readings', style: TextStyle(color: Colors.grey[600])),
        ]),
      ),
      const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Align(alignment: Alignment.centerLeft, child: Text('Select Barangay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))),
      Expanded(
        child: ListView.builder(
          itemCount: _barangays.length,
          itemBuilder: (context, index) {
            final b = _barangays[index];
            final cached = _cachedConsumers[b['id'].toString()];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: primaryBlue.withValues(alpha: 0.12), child: const Icon(Icons.location_on, color: primaryBlue)),
                title: Text(b['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: cached != null ? Text('${cached.length} consumers cached') : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _loadConsumers(b),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildConsumerList() {
    final search = _searchCtrl.text.toLowerCase();
    final filtered = search.isEmpty ? _consumers
        : _consumers.where((c) => c['name'].toString().toLowerCase().contains(search) || c['account_code'].toString().toLowerCase().contains(search)).toList();
    final readCount = _consumers.where((c) => _pendingReadings.containsKey('${c['id']}_$_readingDate')).length;

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryBlue.withValues(alpha: 0.08), primaryBlue.withValues(alpha: 0.03)])),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_selectedBarangay?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('$readCount / ${_consumers.length} read  |  $_readingDate', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ])),
          if (readCount > 0)
            FilledButton.icon(onPressed: _syncPending, icon: const Icon(Icons.sync, size: 18), label: const Text('Sync'),
              style: FilledButton.styleFrom(backgroundColor: primaryBlue)),
        ]),
      ),
      Padding(padding: const EdgeInsets.all(8),
        child: TextField(controller: _searchCtrl,
          decoration: InputDecoration(hintText: 'Search consumer...', prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true, filled: true, fillColor: Colors.grey[50]),
          onChanged: (_) => setState(() {}))),
      Expanded(
        child: ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final c = filtered[index];
            final key = '${c['id']}_$_readingDate';
            final hasReading = _pendingReadings.containsKey(key);
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              color: hasReading ? Colors.blue[50] : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: hasReading ? primaryBlue : Colors.grey[300]!, width: hasReading ? 1.5 : 0.5)),
              child: Padding(padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Container(width: 4, height: 50,
                    decoration: BoxDecoration(color: hasReading ? primaryBlue : Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(c['account_code'], style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    if (c['last_reading'] != null)
                      Padding(padding: const EdgeInsets.only(top: 2),
                        child: Text('Last: ${c['last_reading']} (${c['last_reading_date']})', style: TextStyle(color: Colors.grey[500], fontSize: 11))),
                  ])),
                  SizedBox(width: 100, child: TextField(
                    controller: _readingControllers[c['id']],
                    decoration: InputDecoration(hintText: 'Reading',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: hasReading ? primaryBlue : Colors.grey[400]!)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: primaryBlue, width: 2)),
                      isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      suffixIcon: hasReading ? const Icon(Icons.check_circle, color: primaryBlue, size: 20) : null),
                    keyboardType: TextInputType.number, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    onChanged: (v) => _saveReading(c['id'], v),
                  )),
                ])),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildPendingList() {
    if (_pendingReadings.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text('No pending readings', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
      ]));
    }
    final entries = _pendingReadings.entries.toList();
    final grouped = <String, List<MapEntry<String, dynamic>>>{};
    for (var entry in entries) {
      final parts = entry.key.split('_');
      final date = parts.length >= 2 ? parts.sublist(1).join('-') : 'Unknown';
      grouped.putIfAbsent(date, () => []).add(entry);
    }
    return Column(children: [
      Container(padding: const EdgeInsets.all(16), child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${entries.length} pending readings', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text('Tap sync to upload', style: TextStyle(color: Colors.grey[600])),
        ]),
        const Spacer(),
        FilledButton.icon(onPressed: _syncPending, icon: const Icon(Icons.sync), label: const Text('Sync Now'),
          style: FilledButton.styleFrom(backgroundColor: primaryBlue)),
      ])),
      Expanded(child: ListView(
        children: grouped.entries.map((dateGroup) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(dateGroup.key, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600]))),
            ...dateGroup.value.map((entry) {
              final parts = entry.key.split('_');
              final consumerId = parts[0];
              String consumerName = 'Consumer #$consumerId';
              for (var consumers in _cachedConsumers.values) {
                for (var c in consumers) {
                  if (c['id'].toString() == consumerId) { consumerName = c['name']; break; }
                }
              }
              return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: primaryBlue.withValues(alpha: 0.1), child: const Icon(Icons.speed, color: primaryBlue)),
                  title: Text(consumerName),
                  trailing: Text('${entry.value}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ));
            }),
          ]);
        }).toList(),
      )),
    ]);
  }

  Widget _buildSettings() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        CircleAvatar(radius: 24, backgroundColor: primaryBlue,
          child: Text((_userName ?? 'U')[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_userName ?? 'User', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(_userRole ?? '', style: TextStyle(color: Colors.grey[600])),
        ])),
        OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout, size: 18), label: const Text('Logout'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red)),
      ]))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Reading Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.calendar_today, color: primaryBlue),
          title: Text(_readingDate, style: const TextStyle(fontSize: 18)),
          shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
          onTap: () async {
            final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 30)));
            if (date != null) setState(() => _readingDate = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}');
          },
        ),
      ]))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Offline Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        Text('Auto-syncs every 2 min, auto-downloads every 10 min', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        const SizedBox(height: 12),
        _infoRow(Icons.location_on, 'Cached barangays', '${_cachedBarangays.length}'),
        _infoRow(Icons.people, 'Cached consumer lists', '${_cachedConsumers.length}'),
        _infoRow(Icons.pending_actions, 'Pending readings', '${_pendingReadings.length}'),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: () => _downloadAllData(), icon: const Icon(Icons.download), label: const Text('Download All Data Now'),
          style: FilledButton.styleFrom(backgroundColor: primaryBlue))),
      ]))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('About', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        const Text('Loboc Municipal Waterworks'),
        Text('Meter Reader App v2.0.0', style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text('Server: $apiBase', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ]))),
    ]);
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(icon, size: 20, color: Colors.grey[600]),
      const SizedBox(width: 8),
      Text(label),
      const Spacer(),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ]));
  }
}
