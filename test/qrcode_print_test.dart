import 'dart:convert';

import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter_test/flutter_test.dart';

// Decode GS ( k packets by their declared length, so payload bytes cannot be
// mistaken for a separate command.
List<List<int>> _qrCommands(List<int> bytes) {
  final commands = <List<int>>[];
  for (var i = 0; i + 4 < bytes.length; i++) {
    if (bytes[i] != 0x1d || bytes[i + 1] != 0x28 || bytes[i + 2] != 0x6b) {
      continue;
    }
    final length = bytes[i + 3] + 256 * bytes[i + 4];
    final end = i + 5 + length;
    expect(
      end,
      lessThanOrEqualTo(bytes.length),
      reason: 'Complete GS ( k packet',
    );
    final body = bytes.sublist(i + 5, end);
    if (body.first == 0x31) commands.add(body);
    i = end - 1;
  }
  return commands;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const jirUrl =
      'https://porezna.gov.hr/rn?jir=00000000-0000-0000-0000-000000000001'
      '&datv=20261106_1441&izn=2200';
  const zkiUrl =
      'https://porezna.gov.hr/rn?zki=0123456789abcdef0123456789abcdef'
      '&datv=20261106_1441&izn=2200';

  test('QR print emits no command requiring a printer response', () {
    final commands = _qrCommands(
      QRCode(jirUrl, QRSize.Size4, QRCorrection.L).bytes,
    );

    // FN182 asks the printer for size information. A print-only caller has no
    // response-handling handshake, so that query must not enter this stream.
    expect(commands.where((body) => body[1] == 0x52), isEmpty);
    expect(commands.where((body) => body[1] == 0x51), hasLength(1));
  });

  final sizes = [
    QRSize.Size1,
    QRSize.Size2,
    QRSize.Size3,
    QRSize.Size4,
    QRSize.Size5,
    QRSize.Size6,
    QRSize.Size7,
    QRSize.Size8,
  ];
  final levels = [
    QRCorrection.L,
    QRCorrection.M,
    QRCorrection.Q,
    QRCorrection.H,
  ];
  for (final size in sizes) {
    for (final level in levels) {
      test(
        'QR preserves payload, module ${size.value}, correction ${level.value}',
        () {
          final commands = _qrCommands(QRCode(zkiUrl, size, level).bytes);

          // Module size, correction, store once, print once; no status query.
          expect(commands.map((body) => body[1]), [0x43, 0x45, 0x50, 0x51]);
          expect(commands[0], [0x31, 0x43, size.value]);
          expect(commands[1], [0x31, 0x45, level.value]);
          expect(commands[2].take(3), [0x31, 0x50, 0x30]);
          expect(latin1.decode(commands[2].sublist(3)), zkiUrl);
          expect(commands[3], [0x31, 0x51, 0x30]);
        },
      );
    }
  }

  for (final paper in [PaperSize.mm58, PaperSize.mm80]) {
    test(
      'consecutive QR prints on ${paper.width} dots keep separate payloads',
      () async {
        final generator = Generator(paper, await CapabilityProfile.load());
        final commands = _qrCommands([
          ...generator.qrcode(jirUrl),
          ...generator.qrcode(zkiUrl, size: QRSize.Size6, cor: QRCorrection.M),
        ]);

        expect(commands.where((body) => body[1] == 0x52), isEmpty);
        expect(commands.where((body) => body[1] == 0x51), hasLength(2));
        final payloads = commands
            .where((body) => body[1] == 0x50)
            .map((body) => latin1.decode(body.sublist(3)));
        expect(payloads, [jirUrl, zkiUrl]);
      },
    );
  }
}
