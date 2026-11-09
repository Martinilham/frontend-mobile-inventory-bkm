import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:inventory_bkm_mobile/services/auth_service.dart';
import 'package:inventory_bkm_mobile/widgets/app_feedback.dart';

class FormPhotoDocumentScreen extends StatefulWidget {
  const FormPhotoDocumentScreen({super.key});

  @override
  State<FormPhotoDocumentScreen> createState() =>
      _FormPhotoDocumentScreenState();
}

class _FormPhotoDocumentScreenState extends State<FormPhotoDocumentScreen> {
  final _nameController = TextEditingController();
  final _imagePicker = ImagePicker();
  DateTime _selectedDate = DateTime.now();
  File? _photo;
  bool _isLoading = true;
  bool _isUploading = false;
  String? _message;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, String>> _customerRows = [];
  String _recognizedText = '';
  bool _isReading = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final cached =
        await AuthService.getJsonCache('mobile_form_photo_documents');
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
        Uri.parse('${AuthService.backendUrl}/api/form-photo-documents'),
        headers: await AuthService.authHeaders(token),
      );
      final body = jsonDecode(response.body);

      if (response.statusCode >= 400) {
        setState(() =>
            _message = body['message']?.toString() ?? 'Gagal memuat data');
        return;
      }

      final items = List<Map<String, dynamic>>.from(body['items'] ?? []);
      setState(() => _items = items);
      await AuthService.saveJsonCache('mobile_form_photo_documents', {
        'items': items,
      });
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

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final photo = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (photo == null) return;
      setState(() {
        _photo = File(photo.path);
        _customerRows = [];
        _recognizedText = '';
        _message = null;
      });
    } catch (error) {
      setState(() => _message = 'Gagal mengambil foto: $error');
    }
  }

  Future<void> _upload() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _message = 'Nama wajib diisi');
      return;
    }
    if (_photo == null) {
      setState(() => _message = 'Foto wajib dipilih');
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
        Uri.parse('${AuthService.backendUrl}/api/form-photo-documents/upload'),
      );
      request.headers.addAll(await AuthService.authHeaders(token));
      request.fields['name'] = name;
      request.fields['formDate'] =
          _selectedDate.toIso8601String().split('T').first;
      request.fields['recognizedText'] = _recognizedText;
      request.fields['customerRows'] = jsonEncode(_customerRows);
      request.files
          .add(await http.MultipartFile.fromPath('photo', _photo!.path));

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

      const successMessage = 'Dokumentasi foto data form berhasil diunggah';
      setState(() {
        _message = successMessage;
        _nameController.clear();
        _photo = null;
        _customerRows = [];
        _recognizedText = '';
        _selectedDate = DateTime.now();
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

  Future<void> _readForm() async {
    if (_photo == null) {
      setState(() => _message = 'Pilih foto form terlebih dahulu');
      return;
    }
    setState(() {
      _isReading = true;
      _message = null;
    });
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(_photo!.path));
      final lines = <({String text, double x, double y})>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          lines.add((
            text: line.text.trim(),
            x: line.boundingBox.center.dx,
            y: line.boundingBox.center.dy
          ));
        }
      }
      final headers = <String, List<String>>{
        'date': ['tanggal'],
        'memberNumber': ['member'],
        'customerName': ['nama'],
        'address': ['alamat'],
        'phone': ['telepon'],
        'note': ['keterangan'],
        'cashier': ['kasir'],
      };
      final headerCenters = <String, double>{};
      final headerYPositions = <double>[];
      for (final line in lines) {
        final lower = line.text.toLowerCase();
        for (final entry in headers.entries) {
          if (entry.value.any(lower.contains)) {
            headerCenters[entry.key] = line.x;
            headerYPositions.add(line.y);
          }
        }
      }
      if (headerCenters.length < 3) {
        setState(() {
          _recognizedText = result.text.trim();
          _customerRows = [];
          _message =
              'Teks terbaca. Kolom form belum terdeteksi; pastikan foto tegak dan seluruh tabel terlihat.';
        });
        return;
      }
      final headerY = headerYPositions.fold<double>(0, (a, b) => a > b ? a : b);
      final body = lines.where((line) => line.y > headerY + 8).toList()
        ..sort((a, b) => a.y.compareTo(b.y));
      final grouped = <List<({String text, double x, double y})>>[];
      for (final line in body) {
        if (grouped.isEmpty || (grouped.last.first.y - line.y).abs() > 24)
          grouped.add([line]);
        else
          grouped.last.add(line);
      }
      final rows = <Map<String, String>>[];
      for (final group in grouped) {
        final row = <String, String>{};
        for (final line in group) {
          final nearest = headerCenters.entries.reduce((a, b) =>
              (a.value - line.x).abs() < (b.value - line.x).abs() ? a : b);
          row.update(nearest.key, (old) => '$old ${line.text}',
              ifAbsent: () => line.text);
        }
        final date = row['date'] ?? '';
        if (date.isNotEmpty &&
            row.values.any((value) => value.trim().isNotEmpty)) {
          rows.add({
            for (final key in headers.keys) key: (row[key] ?? '').trim(),
            'date': _normalizeOcrDate(date)
          });
        }
      }
      setState(() {
        _recognizedText = result.text.trim();
        _customerRows = rows;
        _message =
            'OCR selesai: ${rows.length} baris terdeteksi. Periksa kembali hasil sebelum disimpan.';
      });
    } catch (error) {
      setState(() => _message = 'Gagal membaca form: $error');
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _isReading = false);
    }
  }

  String _normalizeOcrDate(String value) {
    final match = RegExp(r'(\d{1,2})\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{2,4})')
        .firstMatch(value);
    if (match == null) return value;
    var year = int.parse(match.group(3)!);
    if (year < 100) year += 2000;
    return '${match.group(1)!.padLeft(2, '0')}/${match.group(2)!.padLeft(2, '0')}/$year';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Form Update Data Customer')),
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
                    'Data Form',
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
            'Dokumentasi Form Update Data Customer',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Nama',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(18),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Tanggal',
                prefixIcon: Icon(Icons.calendar_month_outlined),
              ),
              child: Text(_formatDate(_selectedDate.toIso8601String())),
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
              child: _photo == null
                  ? const Center(
                      child: Icon(Icons.image_outlined,
                          size: 42, color: Color(0xFF8AA05A)),
                    )
                  : Image.file(_photo!, fit: BoxFit.contain),
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
          OutlinedButton.icon(
            onPressed: _isReading || _isUploading ? null : _readForm,
            icon: _isReading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.document_scanner_outlined),
            label:
                Text(_isReading ? 'Membaca form...' : 'Baca Form dengan OCR'),
          ),
          if (_customerRows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
                '${_customerRows.length} baris terbaca; periksa hasil OCR sebelum menyimpan.',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            ..._customerRows.take(5).map((row) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      '${row['date']} • ${row['memberNumber']} • ${row['customerName']}'),
                )),
          ],
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _isUploading ? null : _upload,
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label: Text(_isUploading ? 'Mengunggah...' : 'Simpan Foto Form'),
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
        child: Center(child: Text('Belum ada foto data form.')),
      );
    }

    return Column(children: _items.map(_buildItem).toList());
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final imageUrl = item['imageUrl']?.toString() ?? '';
    final fullUrl =
        imageUrl.isNotEmpty ? '${AuthService.backendUrl}$imageUrl' : '';
    final name = item['name']?.toString() ?? '-';
    final dateText = _formatDate(item['formDate']?.toString());
    final uploadedBy = item['uploadedBy']?.toString() ?? '-';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(dateText,
                    style: const TextStyle(
                        color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('Upload: $uploadedBy',
                    style: const TextStyle(
                        color: Color(0xFF6D7F87), fontSize: 12)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _showFormDetails(item),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text('Lihat foto & data (${(item['customerRows'] as List<dynamic>?)?.length ?? 0})'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFormDetails(Map<String, dynamic> item) async {
    final imageUrl = item['imageUrl']?.toString() ?? '';
    final fullUrl = imageUrl.isEmpty ? '' : '${AuthService.backendUrl}$imageUrl';
    final rows = List<Map<String, dynamic>>.from(
      (item['customerRows'] as List<dynamic>? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map)),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        maxChildSize: 0.96,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
          children: [
            Text(item['name']?.toString() ?? 'Form Customer',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(height: 4),
            Text('Tanggal: ${_formatDate(item['formDate']?.toString())}'),
            if (fullUrl.isNotEmpty) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(fullUrl, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(
                        height: 180, child: Center(child: Text('Foto tidak dapat dimuat')))),
              ),
            ],
            const SizedBox(height: 18),
            Text('Data Customer (${rows.length})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Text((item['recognizedText']?.toString() ?? '').trim().isEmpty
                  ? 'Data OCR belum tersedia.'
                  : item['recognizedText'].toString())
            else
              ...rows.asMap().entries.map((entry) {
                final row = entry.value;
                const fields = <(String, String)>[
                  ('Tanggal', 'date'), ('No Member', 'memberNumber'),
                  ('Nama', 'customerName'), ('Alamat', 'address'),
                  ('No Telepon', 'phone'), ('Keterangan', 'note'),
                  ('Staff Kasir', 'cashier'),
                ];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Data ${entry.key + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const Divider(),
                        ...fields.map((field) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text('${field.$1}: ${(row[field.$2] ?? '-').toString().trim().isEmpty ? '-' : row[field.$2]}'),
                        )),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
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
