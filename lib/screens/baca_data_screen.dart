import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:inventory_bkm_mobile/services/auth_service.dart';
import 'package:inventory_bkm_mobile/widgets/app_feedback.dart';

class BacaDataScreen extends StatefulWidget {
  const BacaDataScreen({super.key});

  @override
  State<BacaDataScreen> createState() => _BacaDataScreenState();
}

class _BacaDataScreenState extends State<BacaDataScreen> {
  final _nameController = TextEditingController();
  final _resultController = TextEditingController();
  final _picker = ImagePicker();
  File? _photo;
  List<Map<String, dynamic>> _ocrLines = [];
  bool _isReading = false;
  bool _isUploading = false;
  String? _message;

  @override
  void dispose() {
    _nameController.dispose();
    _resultController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      _photo = File(picked.path);
      _ocrLines = [];
      _resultController.clear();
      _message = null;
    });
  }

  Future<void> _readText() async {
    if (_photo == null) {
      setState(() => _message = 'Pilih foto terlebih dahulu');
      return;
    }

    setState(() {
      _isReading = true;
      _message = null;
    });

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(_photo!.path);
      final recognized = await recognizer.processImage(inputImage);
      final lines = <Map<String, dynamic>>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final box = line.boundingBox;
          lines.add({
            'text': line.text,
            'left': box.left,
            'top': box.top,
            'right': box.right,
            'bottom': box.bottom,
          });
        }
      }
      setState(() {
        _ocrLines = lines;
        _resultController.text = recognized.text.trim();
        _message = recognized.text.trim().isEmpty
            ? 'Tidak ada teks yang terbaca'
            : 'Teks berhasil dibaca';
      });
    } catch (error) {
      setState(() => _message = 'Gagal membaca teks: $error');
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _isReading = false);
    }
  }

  Future<void> _uploadData() async {
    final name = _nameController.text.trim().toUpperCase();
    if (name.isEmpty) {
      setState(() => _message = 'Nama wajib diisi');
      return;
    }
    if (_photo == null) {
      setState(() => _message = 'Foto wajib dipilih');
      return;
    }

    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      setState(() => _message = 'Silakan login ulang');
      return;
    }

    setState(() {
      _isUploading = true;
      _message = null;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AuthService.backendUrl}/api/read-data/upload'),
      );
      request.headers.addAll(await AuthService.authHeaders(token));
      request.fields['name'] = name;
      request.fields['recognizedText'] = _resultController.text.trim();
      request.fields['ocrLines'] = jsonEncode(_ocrLines);
      request.files.add(await http.MultipartFile.fromPath('photo', _photo!.path));

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw Exception(decoded['message'] ?? 'Upload gagal');
      }

      const successMessage = 'Data berhasil dikirim ke desktop';
      setState(() {
        _nameController.clear();
        _resultController.clear();
        _ocrLines = [];
        _photo = null;
        _message = successMessage;
      });
      if (mounted) {
        await showAppPopup(context,
            title: 'Berhasil', message: successMessage, success: true);
      }
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Baca Data')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFF8DE), Color(0xFFEAF7E3)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF4C2), Color(0xFFFFFFFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7CA7B0).withOpacity(0.16),
                    blurRadius: 34,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Text Recognition',
                          style: TextStyle(
                            color: Color(0xFF6D7F87),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Scan form ke desktop',
                          style:
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    color: const Color(0xFF1D2B38),
                                    fontWeight: FontWeight.w800,
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
                    child: const Icon(Icons.document_scanner_outlined,
                        color: Colors.white, size: 34),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.94),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7CA7B0).withOpacity(0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Nama',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      height: 260,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFF8DE), Color(0xFFEAF7E3)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: _photo == null
                          ? const Center(
                              child: Icon(Icons.image_outlined,
                                  size: 54, color: Color(0xFF8AA0A8)),
                            )
                          : Image.file(_photo!, fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickPhoto(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Kamera'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickPhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Galeri'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _isReading ? null : _readText,
                    icon: _isReading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.document_scanner_outlined),
                    label: Text(_isReading ? 'Membaca...' : 'Baca teks'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _resultController,
                    minLines: 5,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Hasil OCR',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isUploading ? null : _uploadData,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label:
                          Text(_isUploading ? 'Mengirim...' : 'Kirim ke desktop'),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(_message!,
                          style: const TextStyle(color: Color(0xFF6D4C00))),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
