import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:inventory_bkm_mobile/services/auth_service.dart';
import 'package:inventory_bkm_mobile/widgets/app_feedback.dart';

class AbsensiCekScreen extends StatefulWidget {
  const AbsensiCekScreen({super.key});

  @override
  State<AbsensiCekScreen> createState() => _AbsensiCekScreenState();
}

class _AbsensiCekScreenState extends State<AbsensiCekScreen> {
  static const _documentTypes = [
    {'value': 'izin', 'label': 'Surat Izin'},
    {'value': 'sakit', 'label': 'Surat Sakit'},
    {'value': 'cuti', 'label': 'Surat Cuti'},
    {'value': 'lemburan', 'label': 'Surat Lemburan'},
    {'value': 'pulang_cepat', 'label': 'Surat Pulang Cepat'},
  ];

  final _nameController = TextEditingController();
  final _imagePicker = ImagePicker();
  String _selectedType = 'izin';
  File? _proofPhoto;
  bool _isLoading = true;
  bool _isUploading = false;
  String? _message;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final cached = await AuthService.getJsonCache('mobile_absence_documents');
    if (cached != null && mounted) {
      setState(() {
        _items = List<Map<String, dynamic>>.from(cached['items'] ?? []);
        _isLoading = false;
      });
    }

    setState(() {
      _isLoading = _items.isEmpty;
      _message = null;
    });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() => _message = 'Silakan login ulang');
        return;
      }

      final response = await http.get(
        Uri.parse('${AuthService.backendUrl}/api/absence-documents'),
        headers: await AuthService.authHeaders(token),
      );
      final body = jsonDecode(response.body);

      if (response.statusCode >= 400) {
        setState(() =>
            _message = body['message']?.toString() ?? 'Gagal memuat data');
        return;
      }

      setState(() {
        _items = List<Map<String, dynamic>>.from(body['items'] ?? []);
      });
      await AuthService.saveJsonCache('mobile_absence_documents', {
        'items': _items,
      });
    } catch (error) {
      setState(() => _message = 'Gagal memuat data: $error');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final photo = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (photo == null) return;
      setState(() {
        _proofPhoto = File(photo.path);
        _message = null;
      });
    } catch (error) {
      setState(() => _message = 'Gagal mengambil foto: $error');
    }
  }

  Future<void> _uploadDocument() async {
    final employeeName = _nameController.text.trim();
    if (employeeName.isEmpty) {
      setState(() => _message = 'Nama wajib diisi');
      return;
    }
    if (_proofPhoto == null) {
      setState(() => _message = 'Foto bukti wajib dipilih');
      return;
    }

    setState(() {
      _isUploading = true;
      _message = null;
    });

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() => _message = 'Silakan login ulang');
        return;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AuthService.backendUrl}/api/absence-documents/upload'),
      );
      request.headers.addAll(await AuthService.authHeaders(token));
      request.fields['employeeName'] = employeeName;
      request.fields['documentType'] = _selectedType;
      request.files.add(
        await http.MultipartFile.fromPath('proofPhoto', _proofPhoto!.path),
      );

      final response = await request.send();
      final bodyText = await response.stream.bytesToString();
      final body = jsonDecode(bodyText);

      if (response.statusCode >= 400) {
        final message = body['message']?.toString() ?? 'Upload gagal';
        setState(() => _message = message);
        if (mounted) {
          await showAppPopup(context,
              title: 'Upload Gagal', message: message, success: false);
        }
        return;
      }

      const successMessage = 'Dokumentasi absensi berhasil diunggah';
      setState(() {
        _message = successMessage;
        _nameController.clear();
        _selectedType = 'izin';
        _proofPhoto = null;
      });
      if (mounted) {
        await showAppPopup(context,
            title: 'Berhasil', message: successMessage, success: true);
      }
      await _loadItems();
    } catch (error) {
      final message = 'Upload gagal: $error';
      setState(() => _message = message);
      if (mounted) {
        await showAppPopup(context,
            title: 'Upload Gagal', message: message, success: false);
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Absensi Cek')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFF8DE), Color(0xFFEAF7E3)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _loadItems,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 92),
          children: [
            _buildForm(),
            if (_message != null) ...[
              const SizedBox(height: 10),
              _buildMessage(_message!),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Data Dokumentasi',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Muat ulang',
                  onPressed: _loadItems,
                ),
              ],
            ),
            _buildList(),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7FA65A).withOpacity(0.14),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tambah Dokumentasi',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedType,
            decoration: const InputDecoration(labelText: 'Jenis dokumentasi'),
            items: _documentTypes
                .map((item) => DropdownMenuItem(
                      value: item['value'],
                      child: Text(item['label']!),
                    ))
                .toList(),
            onChanged: (value) =>
                setState(() => _selectedType = value ?? 'izin'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Nama',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF8DE), Color(0xFFEAF7E3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: _proofPhoto == null
                  ? Center(
                      child: Icon(Icons.image_outlined,
                          size: 42, color: Color(0xFF8AA05A)),
                    )
                  : Image.file(_proofPhoto!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Galeri'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Kamera'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _isUploading ? null : _uploadDocument,
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label: Text(_isUploading ? 'Mengunggah...' : 'Simpan Dokumentasi'),
          ),
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

  Widget _buildList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Belum ada dokumentasi absensi.')),
      );
    }

    return Column(
      children: _items.map(_buildItem).toList(),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final imageUrl = item['imageUrl']?.toString() ?? '';
    final fullUrl =
        imageUrl.isNotEmpty ? '${AuthService.backendUrl}$imageUrl' : '';
    final name = item['employeeName']?.toString() ?? '-';
    final label = item['documentLabel']?.toString() ??
        item['documentType']?.toString() ??
        '-';
    final uploadedBy = item['uploadedBy']?.toString() ?? '-';
    final dateText = _formatDate(item['createdAt']?.toString());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fullUrl.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                fullUrl,
                fit: BoxFit.contain,
                headers: const {'Accept': 'image/*'},
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFFF3F4F6),
                  child: Center(child: Text('Foto tidak dapat dimuat')),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$dateText - Upload: $uploadedBy',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
