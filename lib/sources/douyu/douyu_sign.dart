import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Douyu (斗鱼) live stream request signing.
///
/// Douyu returns an obfuscated JS script from
/// `https://www.douyu.com/swf_api/homeH5Enc?rids={roomId}`. The script is a
/// fixed TEA-decryption template with per-request randomized constants
/// (variable names, keys, operation sequences). The outermost `ub98484234`
/// function decrypts a payload array into the actual signing function, which
/// computes:
///
///   sign = f( md5(roomId + did + time + v) )  (TEA + bit-mixing)
///
/// This class re-implements the whole chain in pure Dart so no JavaScript
/// engine is required. It is structurally based on the reverse-engineered
/// template (same algorithm as used by yt-dlp / dart_simple_live).
class DouyuSign {
  static const String _did = '10000000000000000000000000001501';
  static const int _delta = 0x9E3779B9;

  /// Generate the `v=..&did=..&tt=..&sign=..` query string for getH5Play.
  static String getSign(String obfJs, String roomId) {
    final inner = _decryptInner(obfJs);
    final v = _extractV(inner);
    final k2 = _extractK2(inner);
    final ops = _parseOps(inner, 're');

    final did = _did;
    final time = (DateTime.now().millisecondsSinceEpoch / 1000).round();

    // md5(room + did + time + v)
    final md5Hex = md5.convert(utf8.encode('$roomId$did$time$v')).toString();

    // Parse md5 hex into 4 little-endian 32-bit words.
    final re = <int>[];
    for (var i = 0; i < md5Hex.length ~/ 8; i++) {
      final b0 = int.parse(md5Hex.substring(i * 8, i * 8 + 2), radix: 16);
      final b1 = int.parse(md5Hex.substring(i * 8 + 2, i * 8 + 4), radix: 16);
      final b2 = int.parse(md5Hex.substring(i * 8 + 4, i * 8 + 6), radix: 16);
      final b3 = int.parse(md5Hex.substring(i * 8 + 6, i * 8 + 8), radix: 16);
      re.add(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24));
    }

    // TEA encrypt: 2 blocks x 32 rounds
    for (var i = 0; i < 2; i++) {
      var v0 = re[i * 2];
      var v1 = re[i * 2 + 1];
      var sum = 0;
      for (var r = 0; r < 32; r++) {
        sum = (sum + _delta) & 0xFFFFFFFF;
        v0 =
            (v0 + (((v1 << 4) + k2[0]) ^ (v1 + sum) ^ ((v1 >>> 5) + k2[1]))) &
            0xFFFFFFFF;
        v1 =
            (v1 + (((v0 << 4) + k2[2]) ^ (v0 + sum) ^ ((v0 >>> 5) + k2[3]))) &
            0xFFFFFFFF;
      }
      re[i * 2] = v0;
      re[i * 2 + 1] = v1;
    }

    // Bit-mixing operation sequence
    for (final op in ops) {
      _applyOp(re, op, k2);
    }

    // Words -> hex (little-endian byte order)
    const hc = '0123456789abcdef';
    final sb = StringBuffer();
    for (final word in re) {
      for (var j = 0; j < 4; j++) {
        sb.write(hc[(word >> (j * 8 + 4)) & 15]);
        sb.write(hc[(word >> (j * 8)) & 15]);
      }
    }

    return 'v=$v&did=$did&tt=$time&sign=$sb';
  }

  // ---------------------------------------------------------------- decryption

  /// Decrypt the `ub98484234` payload into the inner signing function source.
  static String _decryptInner(String obfJs) {
    final fnBody = _extractFunctionBody(obfJs, 'ub98484234');

    // Source payload array name (var v = NAME.slice(0);)
    final srcNameMatch = RegExp(
      r'var\s+v\s*=\s*(\w+)\.slice\(0\)',
    ).firstMatch(fnBody);
    if (srcNameMatch == null) {
      throw StateError('payload array reference not found');
    }
    final srcName = srcNameMatch.group(1)!;
    final srcArr = _extractArray(obfJs, srcName);
    if (srcArr == null) {
      throw StateError('payload array $srcName not found');
    }

    return _teaDecryptLayer(fnBody, srcArr);
  }

  /// Execute one TEA-decryption layer (the fixed obfuscation template).
  static String _teaDecryptLayer(String fnBody, List<int> src) {
    final rk = _extractIntArray(fnBody, 'rk');
    final k2 = _extractIntArray(fnBody, 'k2');
    final lk = _extractIntArray(fnBody, 'lk');
    final k = _extractIntArray(fnBody, 'k');
    if (rk == null || k2 == null || lk == null || k == null) {
      throw StateError('missing TEA arrays in decryption layer');
    }

    // for(var O=0;O<N;O++){v[O]^=X0;}
    final initMatch = RegExp(
      r'for\(var O=0;O<(\d+);O\+\+\)\{v\[O\]\^=0x([0-9a-fA-F]+);\}',
    ).firstMatch(fnBody);
    if (initMatch == null) {
      throw StateError('decryption layer init loop not found');
    }
    final n = int.parse(initMatch.group(1)!);
    final x0 = int.parse(initMatch.group(2)!, radix: 16);

    final v = List<int>.generate(n, (i) => i < src.length ? src[i] : 0);
    for (var o = 0; o < n; o++) {
      v[o] = (v[o] ^ x0) & 0xFFFFFFFF;
    }

    // Bit-mixing operation sequence (uses lk)
    final ops = _parseOps(fnBody, 'v');
    for (final op in ops) {
      _applyOp(v, op, lk);
    }

    // TEA decryption of each 2-word block
    for (var i = 0; i < n; i += 2) {
      var v0 = (v[i] ^ k2[0]) & 0xFFFFFFFF;
      var v1 = (v[i + 1] ^ k2[1]) & 0xFFFFFFFF;
      final rounds = rk[i ~/ 2];
      var sum = (_delta * rounds) & 0xFFFFFFFF;
      for (var r = 0; r < rounds; r++) {
        v1 =
            (v1 -
                ((((v0 << 4) ^ (v0 >>> 5)) + v0) ^
                    (sum + k[((sum >>> 11) & 3)]))) &
            0xFFFFFFFF;
        sum = (sum - _delta) & 0xFFFFFFFF;
        v0 =
            (v0 - ((((v1 << 4) ^ (v1 >>> 5)) + v1) ^ (sum + k[sum & 3]))) &
            0xFFFFFFFF;
      }
      v[i] = (v0 ^ k2[1]) & 0xFFFFFFFF;
      v[i + 1] = (v1 ^ k2[0]) & 0xFFFFFFFF;
    }

    // Avalanche XOR
    for (var o = n - 1; o > 0; o--) {
      v[o] = (v[o] ^ v[o - 1]) & 0xFFFFFFFF;
    }
    v[0] = (v[0] ^ x0) & 0xFFFFFFFF;

    // 4 bytes per word (little-endian) -> string
    final bytes = <int>[];
    for (final word in v) {
      bytes.add(word & 0xFF);
      bytes.add((word >>> 8) & 0xFF);
      bytes.add((word >>> 16) & 0xFF);
      bytes.add((word >>> 24) & 0xFF);
    }
    return String.fromCharCodes(bytes);
  }

  // ------------------------------------------------------------- helpers

  /// Extract `var name = [0x..,0x..,...]` array (decimal or hex values).
  static List<int>? _extractIntArray(String code, String name) {
    final match = RegExp(
      'var\\s+$name\\s*=\\s*\\[([^\\]]*)\\]',
    ).firstMatch(code);
    if (match == null) return null;
    return match.group(1)!.split(',').where((s) => s.trim().isNotEmpty).map((
      s,
    ) {
      final t = s.trim();
      return t.startsWith('0x')
          ? int.parse(t.substring(2), radix: 16)
          : int.parse(t);
    }).toList();
  }

  /// Extract a payload array defined at script top level: `var NAME=[...]`.
  static List<int>? _extractArray(String code, String name) {
    return _extractIntArray(code, name);
  }

  /// Extract a function body by name using brace matching.
  static String _extractFunctionBody(String code, String name) {
    final start = RegExp('function\\s+$name\\s*\\(').firstMatch(code);
    if (start == null) throw StateError('function $name not found');

    // Match parameter parentheses.
    var i = start.end;
    var depth = 1;
    while (i < code.length) {
      if (code[i] == '(') {
        depth++;
      } else if (code[i] == ')') {
        depth--;
        if (depth == 0) break;
      }
      i++;
    }
    final brace = code.indexOf('{', i);
    if (brace < 0) throw StateError('function $name has no body');

    // Match body braces (skip string literals).
    i = brace + 1;
    depth = 1;
    var inStr = false;
    var quote = '';
    while (i < code.length) {
      final c = code[i];
      if (inStr) {
        if (c == r'\') {
          i += 2;
          continue;
        }
        if (c == quote) inStr = false;
      } else {
        if (c == '"' || c == "'" || c == '`') {
          inStr = true;
          quote = c;
        } else if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
          if (depth == 0) return code.substring(brace + 1, i);
        }
      }
      i++;
    }
    throw StateError('unbalanced braces in function $name');
  }

  /// Extract the `v` constant from the inner signing function.
  static String _extractV(String inner) {
    final match = RegExp(
      r'"v=(\d+)"|var\s+cb\s*=[^;]*"(\d+)"',
    ).firstMatch(inner);
    if (match == null) {
      throw StateError('v constant not found in signing function');
    }
    return (match.group(1) ?? match.group(2))!;
  }

  /// Extract the k2 key array from the inner signing function.
  static List<int> _extractK2(String inner) {
    final k2 = _extractIntArray(inner, 'k2');
    if (k2 == null || k2.length < 4) {
      throw StateError('k2 key not found in signing function');
    }
    return k2;
  }

  /// Parse the bit-mixing operation sequence, preserving source order.
  ///
  /// Supports: `arr[K]^=k[I]; arr[K]+=k[I]; arr[K]-=k[I];` and
  /// left/right rotates `arr[K]=(arr[K]<<(k[I]%16))|(arr[K]>>>(32-(k[I]%16)));`
  static List<_Op> _parseOps(String code, String arrName) {
    final ops = <_Op>[];
    // Key arrays are referenced as k2[...] (inner) or lk[...] (decrypt layers)
    final keyIdxPattern = '(?:lk|k\\d?)\\[(\\d+)\\]';
    // Simple ops
    for (final m in RegExp(
      '$arrName\\[(\\d+)\\]\\s*(\\^=|\\+=|-=)\\s*$keyIdxPattern;',
    ).allMatches(code)) {
      ops.add(
        _Op(
          index: int.parse(m.group(1)!),
          keyIndex: int.parse(m.group(3)!),
          kind: m.group(2)!,
          rotate: 0,
          sourceOffset: m.start,
        ),
      );
    }
    // Rotate ops
    for (final m in RegExp(
      '$arrName\\[(\\d+)\\]=\\($arrName\\[\\d+\\]<<\\($keyIdxPattern%16\\)\\)\\|'
      '\\($arrName\\[\\d+\\]>>>\\(32-\\($keyIdxPattern%16\\)\\)\\);',
    ).allMatches(code)) {
      ops.add(
        _Op(
          index: int.parse(m.group(1)!),
          keyIndex: int.parse(m.group(2)!),
          rotate: 1,
          sourceOffset: m.start,
        ),
      );
    }
    for (final m in RegExp(
      '$arrName\\[(\\d+)\\]=\\($arrName\\[\\d+\\]>>>\\($keyIdxPattern%16\\)\\)\\|'
      '\\($arrName\\[\\d+\\]<<\\(32-\\($keyIdxPattern%16\\)\\)\\);',
    ).allMatches(code)) {
      ops.add(
        _Op(
          index: int.parse(m.group(1)!),
          keyIndex: int.parse(m.group(2)!),
          rotate: -1,
          sourceOffset: m.start,
        ),
      );
    }
    // Preserve the original execution order.
    ops.sort((a, b) => a.sourceOffset.compareTo(b.sourceOffset));
    return ops;
  }

  static void _applyOp(List<int> arr, _Op op, List<int> keys) {
    final k = keys[op.keyIndex];
    final shift = k % 16;
    final i = op.index;
    switch (op.rotate) {
      case 0:
        final value = arr[i];
        arr[i] = switch (op.kind) {
          '^=' => (value ^ k) & 0xFFFFFFFF,
          '+=' => (value + k) & 0xFFFFFFFF,
          '-=' => (value - k) & 0xFFFFFFFF,
          _ => value,
        };
      case 1:
        // Left rotate
        arr[i] = ((arr[i] << shift) | (arr[i] >>> (32 - shift))) & 0xFFFFFFFF;
      case -1:
        // Right rotate
        arr[i] = ((arr[i] >>> shift) | (arr[i] << (32 - shift))) & 0xFFFFFFFF;
    }
  }
}

class _Op {
  final int index;
  final int keyIndex;
  final String kind;
  final int rotate; // 0: arithmetic/xor, 1: left rotate, -1: right rotate
  final int sourceOffset;

  _Op({
    required this.index,
    required this.keyIndex,
    this.kind = '^=',
    this.rotate = 0,
    this.sourceOffset = 0,
  });
}
