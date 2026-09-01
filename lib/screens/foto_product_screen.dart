import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:inventory_bkm_mobile/services/auth_service.dart';

class FotoProductScreen extends StatefulWidget {
  const FotoProductScreen({super.key});

  @override
  State<FotoProductScreen> createState() => _FotoProductScreenState();
}

class _FotoProductScreenState extends State<FotoProductScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final cached = await AuthService.getJsonCache('mobile_grabmerch_photos');
    if (cached != null && mounted) {
      setState(() {
        _items = List<Map<String, dynamic>>.from(cached['items'] ?? []);
        _isLoading = false;
      });
    }

    setState(() {
      _isLoading = _items.isEmpty;
      _error = null;
    });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() => _error = 'Silakan login ulang');
        return;
      }

      final uri = Uri.parse('${AuthService.backendUrl}/api/grabmerch');
      final response = await http.get(
        uri,
        headers: await AuthService.authHeaders(token),
      );
      final body = jsonDecode(response.body);

      if (response.statusCode >= 400) {
        setState(() => _error = body['message']?.toString() ?? 'Gagal memuat foto produk');
        return;
      }

      final items = List<Map<String, dynamic>>.from(body['items'] ?? []);
      setState(() => _items = items);
      await AuthService.saveJsonCache('mobile_grabmerch_photos', {
        'items': items,
      });
    } catch (error) {
      setState(() => _error = 'Gagal memuat foto produk: $error');
    } finally {
      setState(() => _isLoading = false);
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
        onRefresh: _loadItems,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _loadItems, child: const Text('Coba lagi')),
              ],
            ),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('Belum ada foto produk hasil upload GrabMerch.')),
        ],
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final imageUrl = item['imageUrl']?.toString() ?? '';
        final fullUrl =
            imageUrl.isNotEmpty ? '${AuthService.backendUrl}$imageUrl' : '';
        final productName = item['productName']?.toString() ?? '-';
        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: fullUrl.isEmpty
                    ? const ColoredBox(
                        color: Color(0xFFFFF8DE),
                        child: Center(
                          child: Icon(Icons.image_not_supported_outlined),
                        ),
                      )
                    : Image.network(
                        fullUrl,
                        fit: BoxFit.cover,
                        headers: const {'Accept': 'image/*'},
                        errorBuilder: (_, __, ___) =>
                            const Center(child: Text('Gagal memuat')),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
