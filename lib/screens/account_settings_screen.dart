import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:inventory_bkm_mobile/screens/login_screen.dart';
import 'package:inventory_bkm_mobile/services/auth_service.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _backendUrlController =
      TextEditingController(text: AuthService.backendUrl);
  String? _username;
  String? _role;
  Map<String, dynamic>? _currentUser;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _isLoadingUsers = true;
  String? _usersMessage;
  List<Map<String, dynamic>> _users = [];

  @override
  void dispose() {
    _backendUrlController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadBiometric();
    _loadUsers();
  }

  Future<void> _loadUser() async {
    final user = await AuthService.getUser();
    setState(() {
      _currentUser = user;
      _username = user?['username']?.toString();
      _role = user?['role']?.toString();
    });
  }

  Future<void> _loadBiometric() async {
    final available = await AuthService.isBiometricAvailable();
    final enabled = await AuthService.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
    });
  }

  Future<void> _setBiometric(bool enabled) async {
    if (enabled) {
      final ok = await AuthService.authenticateBiometric();
      if (!ok) return;
    }
    await AuthService.setBiometricEnabled(enabled);
    if (!mounted) return;
    setState(() => _biometricEnabled = enabled);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(enabled
          ? 'Sidik jari berhasil diaktifkan'
          : 'Sidik jari dinonaktifkan'),
    ));
  }

  Future<void> _loadUsers() async {
    final cached = await AuthService.getJsonCache('mobile_registered_users');
    if (cached != null && mounted) {
      setState(() {
        _users = List<Map<String, dynamic>>.from(cached['users'] ?? []);
        _isLoadingUsers = false;
      });
    }

    setState(() {
      _isLoadingUsers = _users.isEmpty;
      _usersMessage = null;
    });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() => _usersMessage = 'Silakan login ulang');
        return;
      }

      final response = await http.get(
        Uri.parse('${AuthService.backendUrl}/api/auth/users'),
        headers: await AuthService.authHeaders(token),
      );
      final body = jsonDecode(response.body);

      if (response.statusCode == 403) {
        setState(() =>
            _usersMessage = 'Daftar akun hanya dapat dilihat oleh role EDP.');
        return;
      }
      if (response.statusCode >= 400) {
        setState(() =>
            _usersMessage = body['message']?.toString() ?? 'Gagal memuat akun');
        return;
      }

      final users = List<Map<String, dynamic>>.from(body['users'] ?? []);
      setState(() => _users = users);
      await AuthService.saveJsonCache('mobile_registered_users', {
        'users': users,
      });
    } catch (error) {
      setState(() => _usersMessage = 'Gagal memuat akun: $error');
    } finally {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _logout() async {
    await AuthService.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _saveBackendUrl() async {
    try {
      await AuthService.setBackendUrl(_backendUrlController.text);
      await AuthService.clearLocalSession();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan alamat server: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFF8DE), Color(0xFFEAF7E3)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: RefreshIndicator(
        onRefresh: () async {
          await _loadUser();
          await _loadUsers();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 92),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Akun Setting',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _InfoRow(label: 'Username', value: _username ?? '-'),
                    const SizedBox(height: 8),
                    _InfoRow(
                        label: 'Role', value: (_role ?? '-').toUpperCase()),
                    const SizedBox(height: 8),
                    _InfoRow(
                        label: 'Nomor HP',
                        value: _currentUser?['phoneNumber']?.toString() ?? '-'),
                    const SizedBox(height: 8),
                    _InfoRow(
                        label: 'Status',
                        value: _currentUser?['active'] == false
                            ? 'Nonaktif'
                            : 'Aktif'),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Login dengan sidik jari'),
                      subtitle: Text(_biometricAvailable
                          ? 'Aktifkan untuk login cepat di perangkat ini'
                          : 'Sidik jari tidak tersedia di perangkat ini'),
                      value: _biometricEnabled && _biometricAvailable,
                      onChanged: _biometricAvailable ? _setBiometric : null,
                      secondary: const Icon(Icons.fingerprint),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildServerSettingsCard(),
            const SizedBox(height: 16),
            _buildUsersCard(),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Keluar'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Koneksi Server',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 8),
            const Text(
              'Gunakan Dev Tunnel VS Code atau alamat backend lokal.',
              style: TextStyle(color: Color(0xFF6D7F87)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _backendUrlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'URL server',
                hintText: 'https://...devtunnels.ms',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => _backendUrlController.text =
                      AuthService.defaultBackendUrl,
                  child: const Text('Gunakan Dev Tunnel'),
                ),
                TextButton(
                  onPressed: () =>
                      _backendUrlController.text = 'http://10.0.2.2:3000',
                  child: const Text('Lokal (Android Emulator)'),
                ),
              ],
            ),
            const Text(
              'Ponsel fisik: isi http://IP-KOMPUTER:3000 dan pastikan ponsel '
              'serta komputer berada di Wi-Fi yang sama. Dev Tunnel: '
              'https://rkcbt3vw-3000.asse.devtunnels.ms',
              style: TextStyle(color: Color(0xFF6D7F87), fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saveBackendUrl,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan & Masuk Ulang'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Akun Terdaftar',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                ),
                IconButton(
                  onPressed: _loadUsers,
                  tooltip: 'Muat ulang',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_isLoadingUsers)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_usersMessage != null)
              _buildMessage(_usersMessage!)
            else if (_users.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('Belum ada akun terdaftar.'),
              )
            else
              Column(
                children: _users.map(_buildUserTile).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final username = user['username']?.toString() ?? '-';
    final role = user['role']?.toString() ?? '-';
    final active = user['active'] != false;
    final online = user['online'] == true;
    final phone = user['phoneNumber']?.toString() ?? '-';
    final createdAt = _formatDateTime(user['createdAt']?.toString());
    final lastSeen = _formatDateTime(user['lastSeenAt']?.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFE9A8)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: active
                    ? const [Color(0xFF8CC63F), Color(0xFFFFD54F)]
                    : const [Color(0xFFB0BEC5), Color(0xFFE0E0E0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.person_outline, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  '${role.toUpperCase()} - ${active ? 'Aktif' : 'Nonaktif'}',
                  style:
                      const TextStyle(color: Color(0xFF6D7F87), fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text('No HP: ${phone.trim().isEmpty ? '-' : phone}',
                    style: const TextStyle(
                        color: Color(0xFF6D7F87), fontSize: 12)),
                if (createdAt != '-') ...[
                  const SizedBox(height: 3),
                  Text('Dibuat $createdAt',
                      style: const TextStyle(
                          color: Color(0xFF8A8F75), fontSize: 11)),
                ],
                if (lastSeen != '-') ...[
                  const SizedBox(height: 3),
                  Text('Terakhir aktif $lastSeen',
                      style: const TextStyle(
                          color: Color(0xFF8A8F75), fontSize: 11)),
                ],
              ],
            ),
          ),
          _StatusBadge(online: online && active),
        ],
      ),
    );
  }

  Widget _buildMessage(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF6D4C00))),
    );
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'null') return '-';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '-';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} $hour:$minute';
  }
}

class _StatusBadge extends StatelessWidget {
  final bool online;

  const _StatusBadge({required this.online});

  @override
  Widget build(BuildContext context) {
    final color = online ? const Color(0xFF2E7D32) : const Color(0xFF9E9E9E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            online ? 'Online' : 'Offline',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: Colors.black54))),
        Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    );
  }
}
