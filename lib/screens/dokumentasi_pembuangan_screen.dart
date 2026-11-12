import 'dart:convert';
import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
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
  String _documentationType = 'disposal';
  DateTime _selectedDate = DateTime.now();
  DateTime? _filterDate;
  static const _pageSize = 10;
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;
  List<File> _photos = [];
  List<File> _scanPdfs = [];
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
    final dateKey = _filterDate?.toIso8601String().split('T').first ?? 'all';
    final cacheKey = 'mobile_disposals_${dateKey}_$_currentPage';
    final cached = await AuthService.getJsonCache(cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _items = List<Map<String, dynamic>>.from(cached['disposals'] ?? []);
        _totalPages = cached['totalPages'] as int? ?? 1;
        _totalItems = cached['total'] as int? ?? _items.length;
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

      final query = <String, String>{
        'page': '$_currentPage',
        'limit': '$_pageSize',
        if (_filterDate != null)
          'date': _filterDate!.toIso8601String().split('T').first,
      };
      final response = await http.get(
        Uri.parse('${AuthService.backendUrl}/api/disposals')
            .replace(queryParameters: query),
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
        final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
        _totalPages = pagination['totalPages'] as int? ?? 1;
        _totalItems = pagination['total'] as int? ?? _items.length;
      });
      await _saveItemsCache(cacheKey);
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

  Future<void> _pickFilterDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      _filterDate = picked;
      _currentPage = 1;
      _items = [];
      _isLoading = true;
    });
    await _loadItems();
  }

  Future<void> _clearFilterDate() async {
    setState(() {
      _filterDate = null;
      _currentPage = 1;
      _items = [];
      _isLoading = true;
    });
    await _loadItems();
  }

  Future<void> _changePage(int page) async {
    if (page < 1 || page > _totalPages || page == _currentPage) return;
    setState(() {
      _currentPage = page;
      _items = [];
      _isLoading = true;
    });
    await _loadItems();
  }

  Future<void> _scanDocument() async {
    try {
      final paths = await CunningDocumentScanner.getPictures(
        scannerSource: ScannerSource.cameraAndGallery,
        noOfPages: 25,
        asPdf: true,
      );
      if (paths == null || paths.isEmpty) return;
      setState(() {
        _scanPdfs = [..._scanPdfs, ...paths.map((path) => File(path))];
        _message = null;
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Pemindaian gagal: $error');
    }
  }

  Future<void> _pickPhotos({required bool fromCamera}) async {
    try {
      late final List<File> files;
      if (fromCamera) {
        final picked = await _imagePicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1800,
          imageQuality: 88,
        );
        if (picked == null) return;
        files = [File(picked.path)];
      } else {
        final picked =
            await _imagePicker.pickMultiImage(maxWidth: 1800, imageQuality: 88);
        if (picked.isEmpty) return;
        files = picked.map((photo) => File(photo.path)).toList();
      }
      setState(() {
        _photos = [..._photos, ...files];
        _message = null;
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Gagal memilih foto: $error');
    }
  }

  Future<void> _uploadDisposal() async {
    if (_photos.isEmpty && _scanPdfs.isEmpty) {
      setState(() => _message = _documentationType == 'receipt'
          ? 'Ambil foto atau scan dokumen tanda terima'
          : 'Ambil atau pilih minimal satu foto pembuangan');
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
      request.fields['documentationType'] = _documentationType;
      for (final photo in _photos) {
        request.files.add(
          await http.MultipartFile.fromPath('photos', photo.path),
        );
      }
      for (final pdf in _scanPdfs) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'scannedPdfs',
            pdf.path,
            filename:
                'scan_pembuangan_${DateTime.now().millisecondsSinceEpoch}.pdf',
          ),
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

      final documentLabel =
          _documentationType == 'receipt' ? 'tanda terima' : 'pembuangan';
      final successMessage = _scanPdfs.isEmpty
          ? 'Dokumentasi $documentLabel berhasil disimpan'
          : 'Foto dan PDF dokumentasi $documentLabel berhasil disimpan';
      final uploaded = body['disposal'];
      setState(() {
        if (uploaded is Map<String, dynamic>) {
          _items = [uploaded, ..._items];
        }
        _filterDate = null;
        _currentPage = 1;
        _isLoading = true;
        _message = successMessage;
        _scanPdfs = [];
        _photos = [];
        _journalController.clear();
        _selectedDivision = 'GROCERY';
        _documentationType = 'disposal';
        _selectedDate = DateTime.now();
      });
      await _saveItemsCache();
      await CunningDocumentScanner.cleanCache();
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

  void _removeScanPdf(int index) {
    setState(() {
      _scanPdfs = List<File>.from(_scanPdfs)..removeAt(index);
    });
  }

  Future<void> _saveItemsCache([String? cacheKey]) async {
    final dateKey = _filterDate?.toIso8601String().split('T').first ?? 'all';
    await AuthService.saveJsonCache(
        cacheKey ?? 'mobile_disposals_${dateKey}_$_currentPage', {
      'disposals': _items,
      'totalPages': _totalPages,
      'total': _totalItems,
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
              Tab(
                  icon: Icon(Icons.document_scanner_outlined),
                  text: 'Scan Form'),
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
                    _buildDateFilter(),
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
            'Tambah Dokumentasi',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _documentationType,
            decoration: const InputDecoration(labelText: 'Jenis dokumentasi'),
            items: const [
              DropdownMenuItem(value: 'disposal', child: Text('Pembuangan')),
              DropdownMenuItem(value: 'receipt', child: Text('Tanda Terima')),
            ],
            onChanged: (value) =>
                setState(() => _documentationType = value ?? 'disposal'),
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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhotos(fromCamera: true),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Foto Kamera'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhotos(fromCamera: false),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Dari Galeri'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildScanPicker(),
          if (_scanPdfs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${_scanPdfs.length} PDF hasil scan opsional siap disimpan.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanDocument,
                  icon: const Icon(Icons.document_scanner_outlined, size: 18),
                  label: const Text('Tambah PDF (Opsional)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _isUploading ? null : _uploadDisposal,
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label:
                Text(_isUploading ? 'Menyimpan data...' : 'Simpan Pembuangan'),
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

  Widget _buildScanPicker() {
    if (_scanPdfs.isEmpty) {
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
            child: Icon(Icons.document_scanner_outlined,
                size: 42, color: Color(0xFF8AA05A)),
          ),
        ),
      );
    }

    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _scanPdfs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 112,
                  height: 112,
                  color: const Color(0xFFFFF8DE),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.picture_as_pdf, color: Colors.red, size: 36),
                      Text('PDF siap'),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: InkWell(
                  onTap: () => _removeScanPdf(index),
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

  Widget _buildPhotoPicker() {
    if (_photos.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8EE),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Foto wajib. PDF hasil scan bersifat opsional.'),
      );
    }
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () =>
                    _showLocalImagePreview(_photos[index], 'Foto ${index + 1}'),
                child: Image.file(_photos[index],
                    width: 100, height: 100, fit: BoxFit.cover),
              ),
            ),
            Positioned(
              top: 3,
              right: 3,
              child: InkWell(
                onTap: () => setState(() => _photos.removeAt(index)),
                child: const CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.close, size: 15, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilter() {
    final filterText = _filterDate == null
        ? 'Semua tanggal'
        : _formatDate(_filterDate!.toIso8601String());
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickFilterDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(filterText, overflow: TextOverflow.ellipsis),
          ),
        ),
        if (_filterDate != null)
          IconButton(
            onPressed: _clearFilterDate,
            tooltip: 'Hapus filter tanggal',
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
        const SizedBox(width: 8),
        Text('$_totalItems data', style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed:
                _currentPage > 1 ? () => _changePage(_currentPage - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('Halaman $_currentPage dari $_totalPages'),
          IconButton(
            onPressed: _currentPage < _totalPages
                ? () => _changePage(_currentPage + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
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
      return Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('Belum ada dokumentasi pembuangan.')),
          ),
          _buildPagination(),
        ],
      );
    }

    return Column(
      children: [..._items.map(_buildItem), _buildPagination()],
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final division = item['division']?.toString() ?? '-';
    final dateText = _formatDate(item['date']?.toString());
    final uploadedBy = item['uploadedBy']?.toString() ?? '-';
    final journal = item['journal']?.toString().trim() ?? '';
    final documentationType = item['documentationType']?.toString() == 'receipt'
        ? 'Dokumentasi Tanda Terima'
        : 'Dokumentasi Pembuangan';
    final photos = List<String>.from(item['photos'] ?? []);
    final pdfs = List<String>.from(item['scannedPdfs'] ??
        (item['scannedPdf'] == null ? [] : [item['scannedPdf']]));

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
              '$documentationType - ${_divisionLabel(division)}',
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
            if (photos.isEmpty && pdfs.isEmpty)
              const Text('Tidak ada foto atau PDF',
                  style: TextStyle(color: Colors.black54))
            else if (photos.isEmpty)
              Row(
                children: [
                  const Icon(Icons.picture_as_pdf_outlined,
                      color: Color(0xFFC62828)),
                  const SizedBox(width: 8),
                  Text('${pdfs.length} PDF tersimpan di folder PDF'),
                ],
              )
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
            if (photos.isNotEmpty && pdfs.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.picture_as_pdf_outlined,
                      color: Color(0xFFC62828), size: 18),
                  const SizedBox(width: 6),
                  Text('${pdfs.length} PDF opsional tersimpan'),
                ],
              ),
            ],
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
    final pdfs = List<String>.from(item['scannedPdfs'] ??
        (item['scannedPdf'] == null ? [] : [item['scannedPdf']]));
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
                  'Jenis dokumentasi',
                  item['documentationType']?.toString() == 'receipt'
                      ? 'Tanda Terima'
                      : 'Pembuangan',
                ),
                _detailRow(
                  'Divisi',
                  _divisionLabel(item['division']?.toString() ?? '-'),
                ),
                _detailRow('Tanggal', _formatDate(item['date']?.toString())),
                _detailRow('Upload', item['uploadedBy']?.toString() ?? '-'),
                if (journal.isNotEmpty) _detailRow('Jurnal', journal),
                if (pdfs.isNotEmpty)
                  _detailRow('PDF Foto', '${pdfs.length} file tersimpan'),
                const SizedBox(height: 12),
                if (photos.isEmpty)
                  Text(pdfs.isEmpty
                      ? 'Tidak ada foto dokumentasi.'
                      : 'Foto dokumentasi sudah digabungkan menjadi PDF.')
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
    var selectedDocumentationType =
        item['documentationType']?.toString() == 'receipt'
            ? 'receipt'
            : 'disposal';
    final journalController =
        TextEditingController(text: item['journal']?.toString() ?? '');
    final newPhotos = <File>[];
    final newPdfs = <File>[];
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
                    initialValue: selectedDocumentationType,
                    items: const [
                      DropdownMenuItem(
                          value: 'disposal', child: Text('Pembuangan')),
                      DropdownMenuItem(
                          value: 'receipt', child: Text('Tanda Terima')),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) => setDialogState(() =>
                            selectedDocumentationType = value ?? 'disposal'),
                    decoration:
                        const InputDecoration(labelText: 'Jenis dokumentasi'),
                  ),
                  const SizedBox(height: 10),
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
                      decoration: const InputDecoration(labelText: 'Tanggal'),
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
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: isSaving
                        ? null
                        : () async {
                            try {
                              final paths =
                                  await CunningDocumentScanner.getPictures(
                                scannerSource: ScannerSource.cameraAndGallery,
                                noOfPages: 25,
                                asPdf: true,
                              );
                              if (paths != null && paths.isNotEmpty) {
                                setDialogState(() => newPdfs
                                    .addAll(paths.map((path) => File(path))));
                              }
                            } catch (error) {
                              if (mounted) {
                                await showAppPopup(context,
                                    title: 'Scan Gagal',
                                    message: error.toString(),
                                    success: false);
                              }
                            }
                          },
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: Text(newPdfs.isEmpty
                        ? 'Tambah PDF scan (opsional)'
                        : '${newPdfs.length} PDF baru'),
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
                            documentationType: selectedDocumentationType,
                            photos: newPhotos,
                            scannedPdfs: newPdfs,
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
      await _loadItems();
      await CunningDocumentScanner.cleanCache();
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
    required String documentationType,
    required List<File> photos,
    required List<File> scannedPdfs,
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
      request.fields['documentationType'] = documentationType;
      for (final photo in photos) {
        request.files.add(
          await http.MultipartFile.fromPath('photos', photo.path),
        );
      }
      for (final pdf in scannedPdfs) {
        request.files.add(
          await http.MultipartFile.fromPath('scannedPdfs', pdf.path),
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
      await _loadItems();
      if (mounted) {
        await showAppPopup(context,
            title: 'Berhasil',
            message: 'Data pembuangan berhasil dihapus',
            success: true);
      }
    } catch (error) {
      if (mounted) {
        await showAppPopup(context,
            title: 'Hapus Gagal', message: error.toString(), success: false);
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
