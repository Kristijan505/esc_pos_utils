import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

int _indexOfSubsequence(List<int> source, List<int> pattern) {
  if (pattern.isEmpty) {
    return 0;
  }

  for (var i = 0; i <= source.length - pattern.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (source[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      return i;
    }
  }
  return -1;
}

bool _containsSubsequence(List<int> source, List<int> pattern) =>
    _indexOfSubsequence(source, pattern) >= 0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CapabilityProfile profile;
  late Generator generator;

  setUpAll(() async {
    profile = await CapabilityProfile.load();
  });

  setUp(() {
    generator = Generator(PaperSize.mm80, profile);
  });

  group('CapabilityProfile', () {
    test('loads available profiles', () async {
      final profiles = await CapabilityProfile.getAvailableProfiles();
      expect(profiles, isNotEmpty);
    });

    test('returns a valid code page id for CP1252', () {
      final codePageId = profile.getCodePageId('CP1252');
      expect(codePageId, greaterThanOrEqualTo(0));
    });
  });

  group('Generator text encoding', () {
    test('encodes Croatian characters with CP1250 direct mapping', () {
      final bytes = generator.text(
        'ŽžŠšĐđĆćČč',
        styles: const PosStyles(codeTable: 'CP1250'),
      );

      const expectedEncoded = <int>[
        0x40,
        0x60,
        0x5B,
        0x7B,
        0x5C,
        0x7C,
        0x5D,
        0x7D,
        0x5E,
        0x7E,
      ];
      expect(_containsSubsequence(bytes, expectedEncoded), isTrue);
    });

    test('replaces unsupported CP1250 characters with question mark', () {
      final bytes = generator.text(
        '€',
        styles: const PosStyles(codeTable: 'CP1250'),
      );

      expect(bytes, contains(0x3F));
    });
  });

  group('Generator commands', () {
    test('bitImageRaster contains expected GS v 0 header and payload length', () {
      final image = img.Image(width: 8, height: 1);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      final bytes = generator.imageRaster(
        image,
        imageFn: PosImageFn.bitImageRaster,
      );

      const header = <int>[0x1D, 0x76, 0x30, 0x00, 0x01, 0x00, 0x01, 0x00];
      final headerIndex = _indexOfSubsequence(bytes, header);
      expect(headerIndex, greaterThanOrEqualTo(0));
      expect(bytes.length - (headerIndex + header.length), 1);
    });

    test('barcode function A appends NUL terminator', () {
      final payload = '12345678904'.split('');
      final bytes = generator.barcode(Barcode.upcA(payload));

      final expectedTail = <int>[...'12345678904'.codeUnits, 0x00];
      expect(_containsSubsequence(bytes, expectedTail), isTrue);
    });

    test('qrcode includes print-symbol command', () {
      final bytes = generator.qrcode('example.com');
      const printCommand = <int>[0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30];
      expect(_containsSubsequence(bytes, printCommand), isTrue);
    });

    test('row throws when total column width is not 12', () {
      expect(
        () => generator.row([
          PosColumn(text: 'left', width: 5),
          PosColumn(text: 'right', width: 5),
        ]),
        throwsException,
      );
    });
  });
}
