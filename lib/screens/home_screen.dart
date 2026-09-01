import 'dart:convert';

import 'package:animated_notch_bottom_bar/animated_notch_bottom_bar/animated_notch_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:inventory_bkm_mobile/screens/account_settings_screen.dart';
import 'package:inventory_bkm_mobile/screens/foto_product_screen.dart';
import 'package:inventory_bkm_mobile/screens/grabmerch_screen.dart';
import 'package:inventory_bkm_mobile/screens/menu_screen.dart';
import 'package:inventory_bkm_mobile/services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final NotchBottomBarController _notchController = NotchBottomBarController();
  String _role = 'user';
  bool _loadingRole = true;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = await AuthService.getRole();
    setState(() {
      _role = role ?? 'user';
      _loadingRole = false;
    });
  }

  bool get _isGrabmerchRole => _role == 'grabmerch';
  bool get _isEdpRole => _role == 'edp';

  String get _appBarTitle {
    if (_isGrabmerchRole) {
      switch (_currentIndex) {
        case 1:
          return 'Product';
        case 2:
          return 'Foto Product';
        case 3:
          return 'Grabmerch';
        default:
          return 'GrabMerch Mobile';
      }
    }
    switch (_currentIndex) {
      case 1:
        return 'Menu';
      case 2:
        return 'Dokumentasi';
      case 3:
        return 'Akun Setting';
      default:
        return 'Inventory BKM Grocery';
    }
  }

  List<Widget> get _pages {
    if (_isGrabmerchRole) {
      return [
        _HomeDashboardPage(
          role: _role,
          onOpenPrimary: () => setState(() => _currentIndex = 3),
          onOpenSecondary: () => setState(() => _currentIndex = 2),
        ),
        const _PlaceholderPage(title: 'Product'),
        const FotoProductScreen(),
        const GrabmerchScreen(),
      ];
    }
    if (_isEdpRole) {
      return [
        _HomeDashboardPage(
          role: _role,
          onOpenPrimary: () => setState(() => _currentIndex = 1),
          onOpenSecondary: () => setState(() => _currentIndex = 3),
        ),
        const MenuScreen(),
        const _PlaceholderPage(title: 'Dokumentasi'),
        const AccountSettingsScreen(),
      ];
    }
    return [
      _HomeDashboardPage(
        role: _role,
        onOpenPrimary: () => setState(() => _currentIndex = 1),
        onOpenSecondary: () => setState(() => _currentIndex = 3),
      ),
      const _PlaceholderPage(title: 'Menu'),
      const _PlaceholderPage(title: 'Dokumentasi'),
      const AccountSettingsScreen(),
    ];
  }

  List<BottomBarItem> get _bottomBarItems {
    if (_isGrabmerchRole) {
      return [
        _navItem(Icons.home_outlined, 'Home'),
        _navItem(Icons.shopping_bag_outlined, 'Product'),
        _navItem(Icons.photo_library_outlined, 'Foto Product'),
        _navItem(Icons.storefront_outlined, 'Grabmerch'),
      ];
    }
    return [
      _navItem(Icons.home_outlined, 'Home'),
      _navItem(Icons.menu_outlined, 'Menu'),
      _navItem(Icons.description_outlined, 'Dokumentasi'),
      _navItem(Icons.settings_outlined, 'Akun Setting'),
    ];
  }

  BottomBarItem _navItem(IconData icon, String label) {
    return BottomBarItem(
      inActiveItem: Center(child: Icon(icon, size: 20, color: Colors.grey)),
      activeItem: Center(
        child: Transform.translate(
          offset: const Offset(-8, 4),
          child: Icon(icon, size: 28, color: const Color(0xFF2E7D32)),
        ),
      ),
      itemLabel: label,
    );
  }

  @override
  void dispose() {
    _notchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pages = _pages;
    final safeIndex = _currentIndex.clamp(0, pages.length - 1);

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(_appBarTitle),
        centerTitle: false,
      ),
      body: pages[safeIndex],
      bottomNavigationBar: Transform.translate(
        offset: const Offset(2, 0),
        child: AnimatedNotchBottomBar(
          notchBottomBarController: _notchController,
          bottomBarItems: _bottomBarItems,
          onTap: (index) => setState(() => _currentIndex = index),
          color: Colors.white,
          kIconSize: 30.0,
          kBottomRadius: 24.0,
          showLabel: true,
          showShadow: true,
          itemLabelStyle:
              const TextStyle(color: Color(0xFF2E7D32), fontSize: 11),
          bottomBarHeight: 64.0,
          elevation: 12.0,
          circleMargin: 6.0,
          topMargin: 2.0,
        ),
      ),
    );
  }
}

class _HomeDashboardPage extends StatefulWidget {
  final String role;
  final VoidCallback onOpenPrimary;
  final VoidCallback onOpenSecondary;

  const _HomeDashboardPage({
    required this.role,
    required this.onOpenPrimary,
    required this.onOpenSecondary,
  });

  @override
  State<_HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeDashboardPageState extends State<_HomeDashboardPage> {
  bool _isLoading = true;
  String? _message;
  String _username = '-';
  final Map<String, int> _stats = {
    'pembuangan': 0,
    'absensi': 0,
    'ocr': 0,
    'formFoto': 0,
    'produk': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final cached = await AuthService.getJsonCache('mobile_home_${widget.role}');
    final username = await AuthService.getUsername();
    if (cached != null && mounted) {
      setState(() {
        _username = username ?? '-';
        _stats.addAll(Map<String, int>.from(cached['stats'] ?? {}));
        _isLoading = false;
      });
    }

    setState(() {
      _username = username ?? '-';
      _isLoading = _stats.values.every((value) => value == 0);
      _message = null;
    });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() => _message = 'Silakan login ulang');
        return;
      }

      final stats = Map<String, int>.from(_stats);
      if (widget.role == 'grabmerch') {
        stats['produk'] = await _countEndpoint(token, '/api/grabmerch', 'items');
      } else {
        stats['pembuangan'] =
            await _countEndpoint(token, '/api/disposals', 'disposals');
        stats['absensi'] =
            await _countEndpoint(token, '/api/absence-documents', 'items');
        if (widget.role == 'edp') {
          stats['ocr'] = await _countEndpoint(token, '/api/read-data', 'items');
          stats['formFoto'] =
              await _countEndpoint(token, '/api/form-photo-documents', 'items');
        }
      }

      setState(() {
        _stats
          ..clear()
          ..addAll(stats);
      });
      await AuthService.saveJsonCache('mobile_home_${widget.role}', {
        'stats': _stats,
      });
    } catch (error) {
      setState(() => _message = 'Gagal memuat ringkasan: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<int> _countEndpoint(String token, String path, String key) async {
    final response = await http.get(
      Uri.parse('${AuthService.backendUrl}$path'),
      headers: await AuthService.authHeaders(token),
    );
    if (response.statusCode >= 400) return 0;
    final body = jsonDecode(response.body);
    final items = body is Map<String, dynamic> ? body[key] : null;
    return items is List ? items.length : 0;
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
        onRefresh: _loadDashboard,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 92),
          children: [
            _buildHero(context),
            const SizedBox(height: 16),
            _buildStats(),
            const SizedBox(height: 16),
            _buildActions(),
            if (_message != null) ...[
              const SizedBox(height: 12),
              _buildMessage(_message!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF4C2), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7FA65A).withOpacity(0.14),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Selamat bekerja',
                    style: TextStyle(color: Color(0xFF6D7F87))),
                const SizedBox(height: 6),
                Text(
                  _username,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF1D2B38),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Role ${widget.role.toUpperCase()}',
                  style: const TextStyle(
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8CC63F), Color(0xFFFFB74D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.dashboard_customize_outlined,
                color: Colors.white, size: 34),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final cards = widget.role == 'grabmerch'
        ? [
            _StatItem('Foto Produk', _stats['produk'] ?? 0,
                Icons.photo_library_outlined),
          ]
        : [
            _StatItem(
                'Pembuangan', _stats['pembuangan'] ?? 0, Icons.delete_outline),
            _StatItem('Absensi', _stats['absensi'] ?? 0,
                Icons.assignment_turned_in_outlined),
            _StatItem('Baca Data', _stats['ocr'] ?? 0,
                Icons.document_scanner_outlined),
            _StatItem('Foto Form', _stats['formFoto'] ?? 0,
                Icons.photo_camera_back_outlined),
          ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, index) {
        final item = cards[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.94),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(item.icon, color: const Color(0xFF2E7D32)),
              Text(
                _isLoading ? '...' : item.value.toString(),
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              Text(item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF6D7F87))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActions() {
    final primaryLabel =
        widget.role == 'grabmerch' ? 'Upload GrabMerch' : 'Buka Menu';
    final secondaryLabel =
        widget.role == 'grabmerch' ? 'Foto Produk' : 'Akun & Status';
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: widget.onOpenPrimary,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(primaryLabel),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: widget.onOpenSecondary,
            icon: const Icon(Icons.chevron_right_rounded),
            label: Text(secondaryLabel),
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF6D4C00))),
    );
  }
}

class _StatItem {
  final String label;
  final int value;
  final IconData icon;

  const _StatItem(this.label, this.value, this.icon);
}

class _PlaceholderPage extends StatelessWidget {
  final String title;

  const _PlaceholderPage({required this.title});

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
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.86),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7CA7B0).withOpacity(0.18),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8CC63F), Color(0xFFFFB74D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.local_florist_outlined,
                    color: Colors.white, size: 36),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF1D2B38),
                      fontWeight: FontWeight.w800,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Papaya Fresh Gallery',
                style: TextStyle(color: Color(0xFF6D7F87)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
