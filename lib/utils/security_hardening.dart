import 'dart:io';
import 'package:flutter/foundation.dart';

class SecurityHardening {
  static final RegExp _linkPattern = RegExp(
    '(vless|vmess|trojan|ss|ssr):\\/\\/[^\\s"\\\'<>]+',
    caseSensitive: false,
  );

  static String sanitizeSensitiveText(String input) {
    if (input.isEmpty) return input;
    return input.replaceAllMapped(_linkPattern, (match) {
      final raw = match.group(0) ?? '';
      final parsed = Uri.tryParse(raw);
      if (parsed == null) {
        return _maskRawUrl(raw);
      }

      final scheme = parsed.scheme;
      final host = parsed.host;
      final port = parsed.hasPort ? ':${parsed.port}' : '';
      final path = parsed.path.isNotEmpty ? parsed.path : '';
      final query = parsed.query.isNotEmpty ? '?${parsed.query}' : '';
      final fragment = parsed.fragment.isNotEmpty ? '#${parsed.fragment}' : '';

      if (host.isEmpty) {
        return '$scheme://***';
      }

      return '$scheme://***@$host$port$path$query$fragment';
    });
  }

  static String _maskRawUrl(String raw) {
    final schemeIdx = raw.indexOf('://');
    if (schemeIdx <= 0) return '***';
    final scheme = raw.substring(0, schemeIdx);
    final remainder = raw.substring(schemeIdx + 3);
    final atIdx = remainder.indexOf('@');
    if (atIdx > 0) {
      return '$scheme://***${remainder.substring(atIdx)}';
    }
    return '$scheme://***';
  }

  static Future<void> writeStringAtomically(
    String filePath,
    String content, {
    bool flush = true,
  }) async {
    final target = File(filePath);
    final temp = File('$filePath.tmp');

    await temp.writeAsString(content, flush: flush);

    try {
      if (await target.exists()) {
        await target.delete();
      }
      await temp.rename(filePath);
    } catch (_) {
      await target.writeAsString(content, flush: flush);
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  static bool get allowInsecureTlsForDiagnostics => !kReleaseMode;
}
