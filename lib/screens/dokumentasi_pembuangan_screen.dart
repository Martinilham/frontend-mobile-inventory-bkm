import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:inventory_bkm_mobile/services/auth_service.dart';
import 'package:inventory_bkm_mobile/widgets/app_feedback.dart';

class DokumentasiPembuanganScreen extends StatefulWidget {
  const DokumentasiPembuanganScreen({super.key});

  @override
  State<DokumentasiPembuanganScreen> createState() =>
      _DokumentasiPembuanganScreenState();
}

class _DokumentasiPembuanganScreenState
    extends State<DokumentasiPembuanganScreen> {
  static const _divisions = [
    {'value': 'GROCERY', 'label': 'Grocery'},
    {'value': 'SOZAI', 'label': 'Sozai'},
    {'value': 'SOZAI (SISA PRODUKSI)', 'label': 'Sozai (Sisa Produksi)'},
    {'value': 'FISH', 'label': 'Fish'},
    {'value': 'F&V', 'label': 'F&V'},
    {'value': 'MEAT', 'label': 'Meat'},
  ];

  final _imagePicker = ImagePicker();
  final _journalController = TextEditingController();
  String _selectedDivision = 'GROCERY';
  DateTime _selectedDate = DateTime.now();
  List<File> _photos = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String? _message;
  List<Map<String, dynamic>> _items = [];

  @override
  void dispose() {
    _journalController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final cached = await AuthService.getJsonCache('mobile_disposals');
    if (cached != null && mounted) {
      setState(() {
        _items = List<Map<String, dynamic>>.from(cached['disposals'] ?? []);
        _isLoading = false;
      });
    }

    if (!mounted) return;
    setState(() {
      _isLoading = _items.isEmpty;
      _message = null;
    });

    try {
      final token = await AuthService.getToken();
      if (!mounted) return;
      if (token == null) {
        setState(() => _message = 'Silakan login ulang');
        return;
      }

      final response = await http.get(
        Uri.parse('${AuthService.backendUrl}/api/disposals'),
        headers: await AuthService.authHeaders(token),
      );
      final body = jsonDecode(response.body);

      if (!mounted) return;
      if (response.statusCode >= 400) {
        setState(() =>
            _message = body['message']?.toString() ?? 'Gagal memuat data');
        return;
      }

      setState(() {
        _items = List<Map<String, dynamic>>.from(body['disposals'] ?? []);
      });
      await _saveItemsCache();
    } catch (error) {
      setState(() => _message = 'Gagal memuat data: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final photos = await _imagePicker.pickMultiImage(
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (photos.isEmpty) return;
      setState(() {
        _photos = [..._photos, ...photos.map((photo) => File(photo.path))];
        _message = null;
      });
    } catch (error) {
      setState(() => _message = 'Gagal memilih foto: $error');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (photo == null) return;
      setState(() {
        _photos = [..._photos, File(photo.path)];
        _message = null;
      });
    } catch (error) {
      setState(() => _message = 'Gagal mengambil foto: $error');
    }
  }

  Future<void> _uploadDisposal() async {
    if (_photos.isEmpty) {
      setState(() => _message = 'Minimal pilih satu foto dokumentasi');
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
        Uri.parse('${AuthService.backendUrl}/api/disposals/upload'),
      );
      request.headers.addAll(await AuthService.authHeaders(token));
      request.fields['division'] = _selectedDivision;
      request.fields['date'] = _selectedDate.toIso8601String().split('T').first;
      request.fields['journal'] = _journalController.text.trim();

      for (final photo in _photos) {
        request.files.add(
          await http.MultipartFile.fromPath('photos', photo.path),
        );
      }

      final response = await request.send();
      final bodyText = await response.stream.bytesToString();
      final body = jsonDecode(bodyText) as Map<String, dynamic>;

      if (response.statusCode >= 400) {
        final message = body['message']?.toString() ?? 'Upload gagal';
        setState(() => _message = message);
        if (mounted) {
          await showAppPopup(context,
              title: 'Upload Gagal', message: message, success: false);
        }
        return;
      }

      const successMessage = 'Dokumentasi pembuangan berhasil diunggah';
      final uploaded = body['disposal'];
      setState(() {
        if (uploaded is Map<String, dynamic>) {
          _items = [uploaded, ..._items];
        }
        _message = successMessage;
        _photos = [];
        _journalController.clear();
        _selectedDivision = 'GROCERY';
        _selectedDate = DateTime.now();
      });
      await _saveItemsCache();
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

  void _removePhoto(int index) {
    setState(() {
      _photos = List<File>.from(_photos)..removeAt(index);
    });
  }

  Future<void> _saveItemsCache() async {
    await AuthService.saveJsonCache('mobile_disposals', {
      'disposals': _items,
    });
  }

  String _storageUrl(String path) {
    if (path.startsWith('http')) return path;
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('/storage/')) {
      return '${AuthService.backendUrl}$normalized';
    }
    return '${AuthService.backendUrl}/storage/$normalized';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dokumentasi Pembuangan'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.add_photo_alternate_outlined), text: 'Input Foto'),
              Tab(icon: Icon(Icons.fact_check_outlined), text: 'Data Scan'),
            ],
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFF8DE), Color(0xFFEAF7E3)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: TabBarView(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 92),
                children: [
                  _buildForm(),
                  if (_message != null) ...[
                    const SizedBox(height: 10),
                    _buildMessage(_message!),
                  ],
                ],
              ),
              RefreshIndicator(
                onRefresh: _loadItems,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 92),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Data Scan Pembuangan',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Muat ulang',
                          onPressed: _loadItems,
                        ),
                      ],
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 10),
                      _buildMessage(_message!),
                    ],
                    const SizedBox(height: 10),
                    _buildList(),
                  ],
                ),
              ),
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
            'Tambah Dokumentasi Pembuangan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedDivision,
            decoration: const InputDecoration(labelText: 'Divisi'),
            items: _divisions
                .map((item) => DropdownMenuItem(
                      value: item['value'],
                      child: Text(item['label']!),
                    ))
                .toList(),
            onChanged: (value) =>
                setState(() => _selectedDivision = value ?? 'GROCERY'),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Tanggal',
                prefixIcon: Icon(Icons.calendar_month_outlined),
              ),
              child: Text(_formatDate(_selectedDate.toIso8601String())),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _journalController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Jurnal',
              prefixIcon: Icon(Icons.notes_outlined),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          _buildPhotoPicker(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Galeri'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFromCamera,
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Kamera'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _isUploading ? null : _uploadDisposal,
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label: Text(_isUploading ? 'Mengunggah...' : 'Simpan Pembuangan'),
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

  Widget _buildPhotoPicker() {
    if (_photos.isEmpty) {
      return AspectRatio(
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
          child: Center(
            child: Icon(Icons.image_outlined,
                size: 42, color: Color(0xFF8AA05A)),
          ),
        ),
      );
    }

    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () =>
                      _showLocalImagePreview(_photos[index], 'Foto ${index + 1}'),
                  child: Image.file(
                    _photos[index],
                    width: 112,
                    height: 112,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: InkWell(
                  onTap: () => _removePhoto(index),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
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
        child: Center(child: Text('Belum ada dokumentasi pembuangan.')),
      );
    }

    return Column(children: _items.map(_buildItem).toList());
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final division = item['division']?.toString() ?? '-';
    final dateText = _formatDate(item['date']?.toString());
    final uploadedBy = item['uploadedBy']?.toString() ?? '-';
    final journal = item['journal']?.toString().trim() ?? '';
    final photos = List<String>.from(item['photos'] ?? []);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _divisionLabel(division),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              '$dateText - Upload: $uploadedBy',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            if (journal.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                journal,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            if (photos.isEmpty)
              const Text('Tidak ada foto',
                  style: TextStyle(color: Colors.black54))
            else
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => _showImagePreview(
                          _storageUrl(photos[index]),
                          'Foto ${index + 1}',
                        ),
                        child: Image.network(
                          _storageUrl(photos[index]),
                          width: 96,
                          height: 96,
                          fit: BoxFit.contain,
                          headers: const {'Accept': 'image/*'},
                          errorBuilder: (_, __, ___) =>
                              const Center(child: Text('Gagal memuat')),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showDisposalDetail(item),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Preview'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _showEditDisposalDialog(item),
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: () => _confirmDeleteDisposal(item),
                  tooltip: 'Hapus',
                  color: Colors.red,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showImagePreview(String imageUrl, String title) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 0.7,
                  maxScale: 4,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      height: 260,
                      child: Center(child: Text('Gagal memuat foto')),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLocalImagePreview(File file, String title) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 0.7,
                  maxScale: 4,
                  child: Image.file(file, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDisposalDetail(Map<String, dynamic> item) async {
    final photos = List<String>.from(item['photos'] ?? []);
    final journal = item['journal']?.toString().trim() ?? '';

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preview Pembuangan'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow(
                  'Divisi',
                  _divisionLabel(item['division']?.toString() ?? '-'),
                ),
                _detailRow('Tanggal', _formatDate(item['date']?.toString())),
                _detailRow('Upload', item['uploadedBy']?.toString() ?? '-'),
                if (journal.isNotEmpty) _detailRow('Jurnal', journal),
                const SizedBox(height: 12),
                if (photos.isEmpty)
                  const Text('Tidak ada foto dokumentasi.')
                else
                  SizedBox(
                    height: 120,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: photos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: () => _showImagePreview(
                            _storageUrl(photos[index]),
                            'Foto ${index + 1}',
                          ),
                          child: Image.network(
                            _storageUrl(photos[index]),
                            width: 120,
                            height: 120,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _showEditDisposalDialog(item);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Future<void> _showEditDisposalDialog(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? item['_id']?.toString();
    if (id == null || id.isEmpty) {
      await showAppPopup(context,
          title: 'Tidak Bisa Edit',
          message: 'Data pembuangan tidak memiliki ID.',
          success: false);
      return;
    }

    var selectedDivision =
        (item['division']?.toString() ?? 'GROCERY').toUpperCase();
    if (!_divisions.any((division) => division['value'] == selectedDivision)) {
      selectedDivision = 'GROCERY';
    }
    var selectedDate =
        DateTime.tryParse(item['date']?.toString() ?? '') ?? DateTime.now();
    final journalController =
        TextEditingController(text: item['journal']?.toString() ?? '');
    final newPhotos = <File>[];
    var isSaving = false;

    try {
      final updated = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit Pembuangan'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedDivision,
                    items: _divisions
                        .map((division) => DropdownMenuItem(
                              value: division['value'],
                              child: Text(division['label']!),
                            ))
                        .toList(),
                    onChanged: isSaving
                        ? null
                        : (value) => setDialogState(
                            () => selectedDivision = value ?? 'GROCERY'),
                    decoration: const InputDecoration(labelText: 'Divisi'),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: isSaving
                        ? null
                        : () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2023),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setDialogState(() => selectedDate = picked);
                            }
                          },
                    child: InputDecorator(
                      decoration:
                          const InputDecoration(labelText: 'Tanggal'),
                      child: Text(_formatDate(selectedDate.toIso8601String())),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: journalController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Jurnal',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final picked = await _imagePicker.pickMultiImage(
                              maxWidth: 1600,
                              imageQuality: 82,
                            );
                            if (picked.isEmpty) return;
                            setDialogState(() {
                              newPhotos.addAll(
                                  picked.map((photo) => File(photo.path)));
                            });
                          },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(newPhotos.isEmpty
                        ? 'Tambah foto'
                        : '${newPhotos.length} foto baru'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('Batal'),
              ),
              ElevatedButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        try {
                          final result = await _updateDisposal(
                            id: id,
                            division: selectedDivision,
                            date: selectedDate,
                            journal: journalController.text,
                            photos: newPhotos,
                          );
                          if (context.mounted) {
                            Navigator.of(context).pop(result);
                          }
                        } catch (error) {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            await showAppPopup(context,
                                title: 'Update Gagal',
                                message: error.toString(),
                                success: false);
                          }
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(isSaving ? 'Menyimpan...' : 'Simpan'),
              ),
            ],
          ),
        ),
      );

      if (updated == null) return;
      setState(() {
        final index = _items.indexWhere((entry) =>
            (entry['id']?.toString() ?? entry['_id']?.toString()) == id);
        if (index == -1) {
          _items = [updated, ..._items];
        } else {
          _items = List<Map<String, dynamic>>.from(_items)..[index] = updated;
        }
        _message = 'Data pembuangan berhasil diperbarui';
      });
      await _saveItemsCache();
      if (mounted) {
        await showAppPopup(context,
            title: 'Berhasil',
            message: 'Data pembuangan berhasil diperbarui',
            success: true);
      }
    } finally {
      journalController.dispose();
    }
  }

  Future<Map<String, dynamic>> _updateDisposal({
    required String id,
    required String division,
    required DateTime date,
    required String journal,
    required List<File> photos,
  }) async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Silakan login ulang');
    }

    Future<http.StreamedResponse> send(String method, String path) async {
      final request = http.MultipartRequest(
        method,
        Uri.parse('${AuthService.backendUrl}$path'),
      );
      request.headers.addAll(await AuthService.authHeaders(token));
      request.fields['division'] = division;
      request.fields['date'] = date.toIso8601String().split('T').first;
      request.fields['journal'] = journal.trim();
      for (final photo in photos) {
        request.files.add(
          await http.MultipartFile.fromPath('photos', photo.path),
        );
      }
      return request.send();
    }

    var response = await send('POST', '/api/disposals/$id/update');
    var bodyText = await response.stream.bytesToString();
    if (response.statusCode == 404) {
      response = await send('PUT', '/api/disposals/$id');
      bodyText = await response.stream.bytesToString();
    }

    final body = jsonDecode(bodyText) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(body['message']?.toString() ?? 'Update gagal');
    }
    return Map<String, dynamic>.from(body['disposal'] ?? {});
  }

  Future<void> _confirmDeleteDisposal(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Pembuangan'),
        content: const Text('Yakin ingin menghapus data pembuangan ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _deleteDisposal(item);
  }

  Future<void> _deleteDisposal(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? item['_id']?.toString();
    if (id == null || id.isEmpty) {
      await showAppPopup(context,
          title: 'Tidak Bisa Hapus',
          message: 'Data pembuangan tidak memiliki ID.',
          success: false);
      return;
    }

    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        throw Exception('Silakan login ulang');
      }
      final response = await http.delete(
        Uri.parse('${AuthService.backendUrl}/api/disposals/$id'),
        headers: await AuthService.authHeaders(token),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw Exception(body['message']?.toString() ?? 'Hapus gagal');
      }

      setState(() {
        _items = _items
            .where((entry) =>
                (entry['id']?.toString() ?? entry['_id']?.toString()) != id)
            .toList();
        _message = 'Data pembuangan berhasil dihapus';
      });
      await _saveItemsCache();
      if (mounted) {
        await showAppPopup(context,
            title: 'Berhasil',
            message: 'Data pembuangan berhasil dihapus',
            success: true);
      }
    } catch (error) {
      if (mounted) {
        await showAppPopup(context,
            title: 'Hapus Gagal',
            message: error.toString(),
            success: false);
      }
    }
  }

  String _divisionLabel(String value) {
    return _divisions.firstWhere(
      (item) => item['value'] == value.toUpperCase(),
      orElse: () => {'label': value},
    )['label']!;
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
