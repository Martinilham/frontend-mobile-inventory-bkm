import 'package:flutter/material.dart';
import 'package:inventory_bkm_mobile/screens/absensi_cek_screen.dart';
import 'package:inventory_bkm_mobile/screens/baca_data_screen.dart';
import 'package:inventory_bkm_mobile/screens/dokumentasi_pembuangan_screen.dart';
import 'package:inventory_bkm_mobile/screens/form_photo_document_screen.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 92),
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
                        'Papaya Fresh',
                        style: TextStyle(
                          color: Color(0xFF6D7F87),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pilih modul kerja harian',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: const Color(0xFF1D2B38),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8CC63F), Color(0xFFFFB74D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.spa_outlined,
                      color: Colors.white, size: 34),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _MenuTile(
            icon: Icons.document_scanner_outlined,
            title: 'Baca Data',
            subtitle: 'Baca teks dari foto dan kirim hasilnya ke desktop',
            accent: const Color(0xFF8CC63F),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BacaDataScreen()),
              );
            },
          ),
          const SizedBox(height: 14),
          _MenuTile(
            icon: Icons.fact_check_outlined,
            title: 'Absensi Cek',
            subtitle:
                'Dokumentasi izin, sakit, cuti, lemburan, dan pulang cepat',
            accent: const Color(0xFFFFB74D),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AbsensiCekScreen()),
              );
            },
          ),
          const SizedBox(height: 14),
          _MenuTile(
            icon: Icons.photo_camera_back_outlined,
            title: 'Foto Data Form',
            subtitle: 'Dokumentasi form dengan nama, foto, dan tanggal',
            accent: const Color(0xFF6FAF3F),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FormPhotoDocumentScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          _MenuTile(
            icon: Icons.delete_outline,
            title: 'Dokumentasi Pembuangan',
            subtitle: 'Upload dan cek dokumentasi pembuangan per divisi',
            accent: const Color(0xFF2E7D32),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DokumentasiPembuanganScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.92),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7CA7B0).withOpacity(0.10),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Color(0xFF1D2B38),
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                    const SizedBox(height: 5),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Color(0xFF6D7F87), height: 1.25)),
                  ],
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8DE),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.chevron_right,
                    color: Color(0xFF6D7F87), size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
