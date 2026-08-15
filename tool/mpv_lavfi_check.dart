// Diagnostic: verifies that a libmpv build accepts the app's lavfi audio
// filter chains. Useful to test any libmpv (bundled media_kit build, full
// third-party builds, etc.). Loads the library, initializes it, optionally
// plays a file, sets the exact filter chains the app uses and reports mpv
// log errors/warnings.
// Run:
//   dart run tool/mpv_lavfi_check.dart <libmpv-2.dll> [wav-to-play]
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// mpv_event_id values (client.h).
const mpvEventLogMessage = 5;

final class _EventLog extends Struct {
  external Pointer<Utf8> prefix;
  external Pointer<Utf8> level;
  external Pointer<Utf8> text;
  external Pointer<Utf8> logLevel;
}

final class _Event extends Struct {
  @Int32()
  external int eventId;
  @Int32()
  external int error;
  @Uint64()
  external int replyUserdata;
  external Pointer<Void> data;
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/mpv_lavfi_check.dart <libmpv-2.dll> [wav]',
    );
    exit(2);
  }
  final path = args.first;
  final wav = args.length > 1 ? args[1] : null;
  if (!File(path).existsSync()) {
    stderr.writeln('not found: $path');
    exit(2);
  }

  final lib = DynamicLibrary.open(path);
  final mpvCreate = lib
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'mpv_create',
      );
  final mpvInit = lib
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('mpv_initialize');
  final mpvCommand = lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>),
        int Function(Pointer<Void>, Pointer<Pointer<Utf8>>)
      >('mpv_command');
  final mpvRequestLog = lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Utf8>),
        void Function(Pointer<Void>, Pointer<Utf8>)
      >('mpv_request_log_messages');
  final mpvWaitEvent = lib
      .lookupFunction<
        Pointer<_Event> Function(Pointer<Void>, Double),
        Pointer<_Event> Function(Pointer<Void>, double)
      >('mpv_wait_event');
  final mpvDestroy = lib
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('mpv_terminate_destroy');
  final mpvErrStr = lib
      .lookupFunction<
        Pointer<Utf8> Function(Int32),
        Pointer<Utf8> Function(int)
      >('mpv_error_string');

  final ctx = mpvCreate();
  final rc = mpvInit(ctx);
  stdout.writeln(
    '[${path.split(Platform.pathSeparator).last}] init rc=$rc ${mpvErrStr(rc).toDartString()}',
  );
  if (rc != 0) {
    mpvDestroy(ctx);
    exit(1);
  }
  final v = 'v'.toNativeUtf8();
  mpvRequestLog(ctx, v);
  calloc.free(v);

  if (wav != null && File(wav).existsSync()) {
    _cmd(mpvCommand, ctx, ['loadfile', wav, 'replace']);
    sleep(const Duration(milliseconds: 800));
    _cmd(mpvCommand, ctx, [
      'set',
      'af',
      'lavfi=[alimiter=limit=0.85:level=false:attack=5:release=50],lavfi=[lowpass=f=3000:poles=2]',
    ]);
    sleep(const Duration(milliseconds: 1200));
  } else {
    _cmd(mpvCommand, ctx, ['set', 'af', 'lavfi=[lowpass=f=3000:poles=2]']);
  }

  // Drain log events.
  final errors = <String>[];
  for (var i = 0; i < 400; i++) {
    final e = mpvWaitEvent(ctx, 0.01);
    if (e.address == 0) continue;
    if (e.ref.eventId == 0) break; // MPV_EVENT_NONE
    if (e.ref.eventId == mpvEventLogMessage) {
      final msg = e.ref.data.cast<_EventLog>().ref;
      final text = msg.text.toDartString();
      final level = msg.level.toDartString();
      if (level == 'error' || level == 'warn') {
        errors.add('[$level] ${msg.prefix.toDartString()}: $text');
      }
    }
  }
  stdout.writeln('--- mpv log errors/warnings (${errors.length}):');
  for (final e in errors.take(20)) {
    stdout.writeln(e.trimRight());
  }
  if (errors.isEmpty) {
    stdout.writeln('(none)');
  }
  mpvDestroy(ctx);
}

void _cmd(
  int Function(Pointer<Void>, Pointer<Pointer<Utf8>>) cmd,
  Pointer<Void> ctx,
  List<String> args,
) {
  final argv = calloc<Pointer<Utf8>>(args.length + 1);
  for (var i = 0; i < args.length; i++) {
    argv[i] = args[i].toNativeUtf8();
  }
  argv[args.length] = nullptr;
  final rc = cmd(ctx, argv);
  stdout.writeln('  mpv_command ${args.first}... -> rc=$rc');
  for (var i = 0; i < args.length; i++) {
    calloc.free(argv[i]);
  }
  calloc.free(argv);
}
