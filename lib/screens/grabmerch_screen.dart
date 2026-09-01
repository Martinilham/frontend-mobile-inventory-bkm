import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:inventory_bkm_mobile/screens/grabmerch_helper.dart';
import 'package:inventory_bkm_mobile/services/auth_service.dart';
import 'package:inventory_bkm_mobile/widgets/app_feedback.dart';

class GrabmerchScreen extends StatefulWidget {
  const GrabmerchScreen({super.key});

  @override
  State<GrabmerchScreen> createState() => _GrabmerchScreenState();
}

class _GrabmerchScreenState extends State<GrabmerchScreen> {
  final TextEditingController _productNameController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  File? _pickedImage;
  Uint8List? _processedImageBytes;
  bool _isProcessing = false;
  bool _autoRemoveBg = true;
  String _removeBgMethod = 'removebg';
  int _removeBgStrength = 58;
  bool _isUploading = false;
  String? _uploadMessage;
  String? _processingStatus;
  bool _bgRemovedViaApi = false;
  bool _mengandungBabi = true;
  String _selectedLogo = 'blok_m';
  String _logoLayer = 'front';
  int _logoOpacity = 46;
  int _logoSize = 82;
  int _logoOffsetY = 12;
  String _labelLayer = 'front';
  int _labelOpacity = 68;
  int _labelSize = 26;
  int _labelOffsetX = 10;
  int _labelOffsetY = 8;
  int _productZoom = 100;
  int _productRotate = 0;
  int _productOffsetX = 0;
  int _productOffsetY = 5;

  Uint8List? _logoBlokMBytes;
  Uint8List? _logoBlokBBytes;
  Uint8List? _labelBabiBytes;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    try {
      final logo = await rootBundle.load('assets/logos/logo_papaya.png');
      final label = await rootBundle.load('assets/logos/label_babi.png');
      setState(() {
        _logoBlokMBytes = logo.buffer.asUint8List();
        _logoBlokBBytes = logo.buffer.asUint8List();
        _labelBabiBytes = label.buffer.asUint8List();
      });
    } catch (error) {
      setState(() => _uploadMessage = 'Logo tidak ditemukan. Pastikan assets/logos/ sudah terisi.');
    }
  }

  Uint8List? get _activeLogoBytes {
    return _selectedLogo == 'blok_m' ? _logoBlokMBytes : _logoBlokBBytes;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (photo == null) return;

      setState(() {
        _pickedImage = File(photo.path);
        _processedImageBytes = null;
        _uploadMessage = null;
      });
      await _processPreview();
    } catch (error) {
      setState(() => _uploadMessage = 'Gagal memilih gambar: $error');
    }
  }

  Future<Uint8List?> _callBackendRemoveBg(Uint8List imageBytes) async {
    final token = await AuthService.getToken();
    if (token == null) {
      throw Exception('Token tidak ditemukan. Silakan login ulang.');
    }

    final uri = Uri.parse('${AuthService.backendUrl}/api/grabmerch/remove-bg');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await AuthService.authHeaders(token));
    request.files.add(http.MultipartFile.fromBytes(
      'photo',
      imageBytes,
      filename: 'photo.jpg',
    ));
    request.fields['removeBgMethod'] = _removeBgMethod;

    final response = await request.send().timeout(const Duration(seconds: 90));
    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      throw Exception(body);
    }
    return response.stream.toBytes();
  }

  Future<void> _processPreview() async {
    if (_pickedImage == null) return;

    setState(() {
      _isProcessing = true;
      _uploadMessage = null;
      _processingStatus = 'Memproses preview...';
      _bgRemovedViaApi = false;
    });

    try {
      var bytes = await _pickedImage!.readAsBytes();

      if (_autoRemoveBg && (_removeBgMethod == 'removebg' || _removeBgMethod == 'iloveapi')) {
        final providerLabel =
            _removeBgMethod == 'iloveapi' ? 'iLoveAPI' : 'Remove.bg';
        setState(() => _processingStatus = 'Menghapus background via $providerLabel...');
        try {
          final removed = await _callBackendRemoveBg(bytes);
          if (removed != null && removed.isNotEmpty) {
            bytes = removed;
            _bgRemovedViaApi = true;
          }
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _processedImageBytes = null;
            _isProcessing = false;
            _processingStatus = null;
            _uploadMessage =
                '$providerLabel gagal. Coba restart backend, atau ganti ke Local fallback.\nDetail: $error';
          });
          return;
        }
      } else if (_autoRemoveBg && _removeBgMethod == 'local') {
        setState(() => _processingStatus = 'Menghapus background lokal...');
      }

      setState(() => _processingStatus = 'Menyusun logo dan label...');

      final result = await compute(
        processImageBytes,
        ImageProcessingArgs(
          bytes: bytes,
          removeBgStrength: _removeBgStrength,
          autoRemoveBg: _autoRemoveBg && !_bgRemovedViaApi,
          mengandungBabi: _mengandungBabi,
          logoKey: _selectedLogo,
          logoLayer: _logoLayer,
          logoOpacity: _logoOpacity,
          logoSize: _logoSize,
          logoOffsetY: _logoOffsetY,
          labelLayer: _labelLayer,
          labelOpacity: _labelOpacity,
          labelSize: _labelSize,
          labelOffsetX: _labelOffsetX,
          labelOffsetY: _labelOffsetY,
          productZoom: _productZoom,
          productRotate: _productRotate,
          productOffsetX: _productOffsetX,
          productOffsetY: _productOffsetY,
          logoBytes: _activeLogoBytes,
          labelBytes: _labelBabiBytes,
        ),
      );

      if (!mounted) return;
      setState(() {
        _processedImageBytes = result;
        _isProcessing = false;
        _processingStatus = null;
        if (_bgRemovedViaApi) {
          final providerLabel =
              _removeBgMethod == 'iloveapi' ? 'iLoveAPI' : 'Remove.bg';
          _uploadMessage = 'Background berhasil dihapus via $providerLabel. Preview siap diunggah.';
        } else if (_autoRemoveBg && _removeBgMethod == 'local') {
          _uploadMessage =
              'Preview lokal selesai. Naikkan Kekuatan jika BG belum hilang. Untuk foto kompleks, gunakan Remove.bg API.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _processedImageBytes = null;
        _uploadMessage = 'Gagal memproses preview: $error';
        _isProcessing = false;
        _processingStatus = null;
      });
    }
  }

  void _onPresetChanged() {
    if (_pickedImage != null) {
      _processPreview();
    }
  }

  void _resetPosition() {
    setState(() {
      _productZoom = 100;
      _productRotate = 0;
      _productOffsetX = 0;
      _productOffsetY = 5;
      _logoOpacity = 46;
      _logoSize = 82;
      _logoOffsetY = 12;
      _labelOpacity = 68;
      _labelSize = 26;
      _labelOffsetX = 10;
      _labelOffsetY = 8;
    });
    _onPresetChanged();
  }

  Map<String, dynamic> _buildPreset() {
    return {
      'mengandungBabi': _mengandungBabi,
      'selectedLogo': _selectedLogo,
      'logoLayer': _logoLayer,
      'logoOpacity': _logoOpacity,
      'logoSize': _logoSize,
      'logoOffsetY': _logoOffsetY,
      'labelLayer': _labelLayer,
      'labelOpacity': _labelOpacity,
      'labelSize': _labelSize,
      'labelOffsetX': _labelOffsetX,
      'labelOffsetY': _labelOffsetY,
      'productZoom': _productZoom,
      'productRotate': _productRotate,
      'productOffsetX': _productOffsetX,
      'productOffsetY': _productOffsetY,
      'removeBgStrength': _removeBgStrength,
      'autoRemoveBg': _autoRemoveBg,
      'removeBgMethod': _removeBgMethod,
    };
  }

  Future<void> _downloadPreset() async {
    final preset = jsonEncode(_buildPreset());
    await Clipboard.setData(ClipboardData(text: preset));
    setState(() => _uploadMessage = 'Preset disalin ke clipboard');
  }

  Future<void> _downloadJpg() async {
    if (_processedImageBytes == null) {
      setState(() => _uploadMessage = 'Belum ada hasil export untuk diunduh');
      return;
    }
    try {
      final dir = Directory('${Directory.systemTemp.path}/grabmerch');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/hasil_export_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(_processedImageBytes!);
      setState(() => _uploadMessage = 'JPG tersimpan: ${file.path}');
    } catch (error) {
      setState(() => _uploadMessage = 'Gagal menyimpan JPG: $error');
    }
  }

  Future<void> _uploadGrabMerch() async {
    final productName = _productNameController.text.trim();
    if (productName.isEmpty) {
      setState(() => _uploadMessage = 'Nama produk tidak boleh kosong');
      return;
    }
    if (_pickedImage == null) {
      setState(() => _uploadMessage = 'Silakan pilih foto produk terlebih dahulu');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadMessage = null;
    });

    try {
      await _processPreview();

      if (_processedImageBytes == null) {
        setState(() {
          _uploadMessage = 'Upload dibatalkan: preview belum siap atau background gagal dihapus.';
          _isUploading = false;
        });
        return;
      }

      if (_autoRemoveBg &&
          (_removeBgMethod == 'removebg' || _removeBgMethod == 'iloveapi') &&
          !_bgRemovedViaApi) {
        final providerLabel =
            _removeBgMethod == 'iloveapi' ? 'iLoveAPI' : 'Remove.bg';
        setState(() {
          _uploadMessage = 'Upload dibatalkan: $providerLabel belum berhasil menghapus background.';
          _isUploading = false;
        });
        return;
      }

      final uri = Uri.parse('${AuthService.backendUrl}/api/grabmerch/upload');
      final token = await AuthService.getToken();
      if (token == null) {
        setState(() => _uploadMessage = 'Token tidak ditemukan. Silakan login ulang.');
        return;
      }

      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await AuthService.authHeaders(token));
      request.fields['productName'] = productName;
      request.files.add(http.MultipartFile.fromBytes(
        'photo',
        _processedImageBytes!,
        filename: 'processed.jpg',
      ));
      request.fields['clientProcessed'] = 'true';

      request.fields['productType'] = _mengandungBabi ? 'mengandung_babi' : 'normal';
      request.fields['logoKey'] = _selectedLogo;
      request.fields['logoLayer'] = _logoLayer;
      request.fields['logoOpacity'] = _logoOpacity.toString();
      request.fields['logoSize'] = _logoSize.toString();
      request.fields['logoOffsetY'] = _logoOffsetY.toString();
      request.fields['labelLayer'] = _labelLayer;
      request.fields['labelOpacity'] = _labelOpacity.toString();
      request.fields['labelSize'] = _labelSize.toString();
      request.fields['labelOffsetX'] = _labelOffsetX.toString();
      request.fields['labelOffsetY'] = _labelOffsetY.toString();
      request.fields['removeBgMethod'] = _removeBgMethod;
      request.fields['autoRemoveBg'] = _autoRemoveBg ? 'true' : 'false';
      request.fields['removeBgStrength'] = _removeBgStrength.toString();
      request.fields['productZoom'] = _productZoom.toString();
      request.fields['productRotate'] = _productRotate.toString();
      request.fields['productOffsetX'] = _productOffsetX.toString();
      request.fields['productOffsetY'] = _productOffsetY.toString();

      final response = await request.send();
      final body = await response.stream.bytesToString();
      if (response.statusCode >= 400) {
        final message = 'Unggah gagal: $body';
        setState(() => _uploadMessage = message);
        if (mounted) {
          await showAppPopup(context,
              title: 'Upload Gagal', message: message, success: false);
        }
        return;
      }

      const successMessage = 'Upload berhasil! Hasil akan muncul di Foto Product dan dashboard admin.';
      setState(() {
        _uploadMessage = successMessage;
        _productNameController.clear();
        _pickedImage = null;
        _processedImageBytes = null;
      });
      if (mounted) {
        await showAppPopup(context,
            title: 'Berhasil', message: successMessage, success: true);
      }
    } catch (error) {
      final message = 'Unggah gagal: $error';
      setState(() => _uploadMessage = message);
      if (mounted) {
        await showAppPopup(context,
            title: 'Upload Gagal', message: message, success: false);
      }
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  void dispose() {
    _productNameController.dispose();
    super.dispose();
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined),
                  tooltip: 'Galeri',
                  onPressed: () => _pickImage(ImageSource.gallery),
                ),
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined),
                  tooltip: 'Kamera',
                  onPressed: () => _pickImage(ImageSource.camera),
                ),
              ],
            ),
            ..._buildContentChildren(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContentChildren() {
    return [
      _buildModeToggle(),
      const SizedBox(height: 12),
      _buildPreviewCard(),
      const SizedBox(height: 12),
      _buildBgSection(),
      const SizedBox(height: 10),
      _buildLogoSection(),
      if (_mengandungBabi) ...[
        const SizedBox(height: 10),
        _buildLabelSection(),
      ],
      const SizedBox(height: 10),
      _buildTransformSection(),
      const SizedBox(height: 12),
      _buildActionButtons(),
      const SizedBox(height: 12),
      _buildUploadSection(),
      if (_uploadMessage != null) ...[
        const SizedBox(height: 10),
        Text(_uploadMessage!, style: const TextStyle(color: Colors.black87)),
      ],
    ];
  }

  Widget _buildModeToggle() {
    return Row(
      children: [
        Expanded(
          child: _ModeButton(
            label: 'Normal',
            active: !_mengandungBabi,
            activeColor: Colors.white,
            activeTextColor: Colors.black87,
            borderColor: Colors.grey.shade300,
            onTap: () {
              setState(() => _mengandungBabi = false);
              _onPresetChanged();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ModeButton(
            label: 'Mengandung Babi',
            active: _mengandungBabi,
            activeColor: const Color(0xFFE53935),
            activeTextColor: Colors.white,
            borderColor: const Color(0xFFE53935),
            onTap: () {
              setState(() => _mengandungBabi = true);
              _onPresetChanged();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('PREVIEW 1:1', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              Text('Hasil Export', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_pickedImage == null)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.image_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text('Pilih foto produk', style: TextStyle(color: Colors.grey.shade500)),
                        ],
                      ),
                    )
                  else if (_processedImageBytes != null)
                    Image.memory(_processedImageBytes!, fit: BoxFit.contain)
                  else
                    Image.file(_pickedImage!, fit: BoxFit.contain),
                  if (_isProcessing)
                    Container(
                      color: Colors.black26,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: Colors.white),
                            if (_processingStatus != null) ...[
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  _processingStatus!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBgSection() {
    return _SectionBox(
      color: const Color(0xFFE8F5E9),
      borderColor: const Color(0xFFA5D6A7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                value: _autoRemoveBg,
                activeColor: const Color(0xFF43A047),
                onChanged: (v) {
                  setState(() => _autoRemoveBg = v ?? true);
                  _onPresetChanged();
                },
              ),
              const Expanded(
                child: Text('Auto Hapus BG', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ],
          ),
          if (_autoRemoveBg) ...[
            _DropdownField(
              label: 'Metode',
              value: _removeBgMethod,
              items: const [
                DropdownMenuItem(value: 'removebg', child: Text('Remove.bg API')),
                DropdownMenuItem(value: 'iloveapi', child: Text('iLoveAPI Remove BG')),
                DropdownMenuItem(value: 'local', child: Text('Local fallback')),
              ],
              onChanged: (v) {
                setState(() => _removeBgMethod = v ?? 'removebg');
                _onPresetChanged();
              },
            ),
            _PresetSlider(
              label: 'Kekuatan',
              value: _removeBgStrength,
              min: 0,
              max: 100,
              onChanged: (v) => setState(() => _removeBgStrength = v),
              onChangeEnd: (_) => _onPresetChanged(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogoSection() {
    return _SectionBox(
      color: const Color(0xFFFFF3E0),
      borderColor: const Color(0xFFFFCC80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Logo Papaya', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          _DropdownField(
            label: 'Logo Papaya',
            value: _selectedLogo,
            items: const [
              DropdownMenuItem(value: 'blok_m', child: Text('Blok M')),
              DropdownMenuItem(value: 'blok_b', child: Text('Blok B')),
            ],
            onChanged: (v) {
              setState(() => _selectedLogo = v ?? 'blok_m');
              _onPresetChanged();
            },
          ),
          _DropdownField(
            label: 'Layer Watermark',
            value: _logoLayer,
            items: const [
              DropdownMenuItem(value: 'front', child: Text('Depan Produk')),
              DropdownMenuItem(value: 'back', child: Text('Belakang Produk')),
            ],
            onChanged: (v) {
              setState(() => _logoLayer = v ?? 'front');
              _onPresetChanged();
            },
          ),
          _PresetSlider(label: 'Transparansi', value: _logoOpacity, min: 0, max: 100, onChanged: (v) => setState(() => _logoOpacity = v), onChangeEnd: (_) => _onPresetChanged()),
          _PresetSlider(label: 'Ukuran', value: _logoSize, min: 20, max: 100, onChanged: (v) => setState(() => _logoSize = v), onChangeEnd: (_) => _onPresetChanged()),
          _PresetSlider(label: 'Naik/Turun', value: _logoOffsetY, min: 0, max: 50, onChanged: (v) => setState(() => _logoOffsetY = v), onChangeEnd: (_) => _onPresetChanged()),
        ],
      ),
    );
  }

  Widget _buildLabelSection() {
    return _SectionBox(
      color: const Color(0xFFFFEBEE),
      borderColor: const Color(0xFFEF9A9A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Layer Label Babi', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          _DropdownField(
            label: 'Layer Label Babi',
            value: _labelLayer,
            items: const [
              DropdownMenuItem(value: 'front', child: Text('Depan Produk')),
              DropdownMenuItem(value: 'back', child: Text('Belakang Produk')),
            ],
            onChanged: (v) {
              setState(() => _labelLayer = v ?? 'front');
              _onPresetChanged();
            },
          ),
          _PresetSlider(label: 'Transparansi', value: _labelOpacity, min: 0, max: 100, onChanged: (v) => setState(() => _labelOpacity = v), onChangeEnd: (_) => _onPresetChanged()),
          _PresetSlider(label: 'Ukuran', value: _labelSize, min: 0, max: 100, onChanged: (v) => setState(() => _labelSize = v), onChangeEnd: (_) => _onPresetChanged()),
          _PresetSlider(label: 'Geser X', value: _labelOffsetX, min: 0, max: 100, onChanged: (v) => setState(() => _labelOffsetX = v), onChangeEnd: (_) => _onPresetChanged()),
          _PresetSlider(label: 'Geser Y', value: _labelOffsetY, min: 0, max: 100, onChanged: (v) => setState(() => _labelOffsetY = v), onChangeEnd: (_) => _onPresetChanged()),
        ],
      ),
    );
  }

  Widget _buildTransformSection() {
    return _SectionBox(
      color: Colors.white,
      borderColor: Colors.grey.shade300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PresetSlider(label: 'Zoom', value: _productZoom, min: 50, max: 150, onChanged: (v) => setState(() => _productZoom = v), onChangeEnd: (_) => _onPresetChanged()),
          _PresetSlider(label: 'Putar', value: _productRotate, min: -45, max: 45, suffix: '°', onChanged: (v) => setState(() => _productRotate = v), onChangeEnd: (_) => _onPresetChanged()),
          _PresetSlider(label: 'Geser X', value: _productOffsetX, min: -30, max: 30, onChanged: (v) => setState(() => _productOffsetX = v), onChangeEnd: (_) => _onPresetChanged()),
          _PresetSlider(label: 'Geser Y', value: _productOffsetY, min: -30, max: 30, onChanged: (v) => setState(() => _productOffsetY = v), onChangeEnd: (_) => _onPresetChanged()),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _downloadPreset,
                child: const Text('Download Preset', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: null,
                child: Text('Upload Preset', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _resetPosition,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.black87),
                ),
                child: const Text('Reset Posisi', style: TextStyle(fontSize: 12, color: Colors.black87)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _processedImageBytes == null ? null : _downloadJpg,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: const Text('Download JPG', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUploadSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _productNameController,
            decoration: InputDecoration(
              labelText: 'Nama produk',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: (_isUploading || _isProcessing || _processedImageBytes == null)
                    ? null
                    : _uploadGrabMerch,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(_isUploading ? 'Mengunggah...' : 'Unggah ke GrabMerch'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final Color activeTextColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.activeTextColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? activeColor : Colors.white,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? borderColor : Colors.grey.shade300),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: active ? activeTextColor : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionBox extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final Widget child;

  const _SectionBox({required this.color, required this.borderColor, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _PresetSlider extends StatelessWidget {
  final String label;
  final int value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<int> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _PresetSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.suffix = '%',
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              Text('$value$suffix', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: value.toDouble().clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            activeColor: const Color(0xFF2E7D32),
            onChanged: (v) => onChanged(v.round()),
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}
