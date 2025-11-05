/*
 * esc_pos_utils
 * Created by Andrey U.
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:convert';
import 'dart:typed_data' show Uint8List;
import 'package:hex/hex.dart';
import 'package:image/image.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'commands.dart';

class Generator {
  Generator(this._paperSize, this._profile, {this.spaceBetweenRows = 5});

  // Ticket config
  final PaperSize _paperSize;
  CapabilityProfile _profile;
  int? _maxCharsPerLine;
  // Global styles
  String? _codeTable;
  PosFontType? _font;
  // Current styles
  PosStyles _styles = PosStyles();
  int spaceBetweenRows;

  // ************************ Internal helpers ************************
  int _getMaxCharsPerLine(PosFontType? font) {
    if (_paperSize == PaperSize.mm58) {
      return (font == null || font == PosFontType.fontA) ? 32 : 42;
    } else {
      return (font == null || font == PosFontType.fontA) ? 48 : 64;
    }
  }

  // charWidth = default width * text size multiplier
  double _getCharWidth(PosStyles styles, {int? maxCharsPerLine}) {
    int charsPerLine = _getCharsPerLine(styles, maxCharsPerLine);
    double charWidth = (_paperSize.width / charsPerLine) * styles.width.value;
    return charWidth;
  }

  double _colIndToPosition(int colInd) {
    final int width = _paperSize.width;
    return colInd == 0 ? 0 : (width * colInd / 12 - 1);
  }

  int _getCharsPerLine(PosStyles styles, int? maxCharsPerLine) {
    int charsPerLine;
    if (maxCharsPerLine != null) {
      charsPerLine = maxCharsPerLine;
    } else {
      if (styles.fontType != null) {
        charsPerLine = _getMaxCharsPerLine(styles.fontType);
      } else {
        charsPerLine =
            _maxCharsPerLine ?? _getMaxCharsPerLine(_styles.fontType);
      }
    }
    return charsPerLine;
  }

  Uint8List _encode(String text, {bool isKanji = false, String? codeTable}) {
    // replace some non-ascii characters
    text = text
        .replaceAll("'", "'")
        .replaceAll("´", "'")
        .replaceAll("»", '"')
        .replaceAll(" ", ' ')
        .replaceAll("•", '.');
    if (!isKanji) {
      // Check if CP1250 code table is being used
      // Use provided codeTable, or fall back to styles/codeTable state
      final activeCodeTable = codeTable ?? _styles.codeTable ?? _codeTable;
      if (activeCodeTable == 'CP1250') {
        return _encodeCP1250(text);
      }
      return latin1.encode(text);
    } else {
      return Uint8List.fromList(gbk_bytes.encode(text));
    }
  }

  /// Encode string to CP1250 (Windows-1250) encoding
  /// Updated for SEWOO SLK-TS500 printer - uses direct byte mapping
  Uint8List _encodeCP1250(String text) {
    // Direct byte mapping for Croatian characters (SEWOO SLK-TS500)
    // These are the printer's built-in character positions
    final Map<int, int> cp1250Map = {
      // Croatian uppercase
      0x017D: 0x40, // Ž
      0x0160: 0x5B, // Š
      0x0110: 0x5C, // Đ
      0x0106: 0x5D, // Ć
      0x010C: 0x5E, // Č
      // Croatian lowercase
      0x017E: 0x60, // ž
      0x0161: 0x7B, // š
      0x0111: 0x7C, // đ
      0x0107: 0x7D, // ć
      0x010D: 0x7E, // č
      // Other Central European characters in CP1250
      0x00E1: 0xE1, // á
      0x00E9: 0xE9, // é
      0x00ED: 0xED, // í
      0x00F3: 0xF3, // ó
      0x00FA: 0xFA, // ú
      0x00FD: 0xFD, // ý
      0x00E4: 0xE4, // ä
      0x00F6: 0xF6, // ö
      0x00FC: 0xFC, // ü
      0x010F: 0xEF, // ď
      0x0148: 0xF5, // ň
      0x0159: 0xF8, // ř
      0x0165: 0xFE, // ť
      0x016F: 0xF9, // ů
      0x015F: 0x9F, // ş
      0x00E0: 0xE0, // à
      0x00EC: 0xEC, // ì
      0x00F2: 0xF2, // ò
      0x00C1: 0xC1, // Á
      0x00C9: 0xC9, // É
      0x00CD: 0xCD, // Í
      0x00D3: 0xD3, // Ó
      0x00DA: 0xDA, // Ú
      0x00DD: 0xDD, // Ý
      0x00C4: 0xC4, // Ä
      0x00D6: 0xD6, // Ö
      0x00DC: 0xDC, // Ü
      // Add more CP1250 characters as needed
    };

    final List<int> result = [];
    final runes = text.runes;

    for (final rune in runes) {
      if (rune < 0x80) {
        // ASCII characters (0-127) - same in CP1250
        result.add(rune);
      } else if (cp1250Map.containsKey(rune)) {
        // Mapped characters (Croatian and Central European)
        result.add(cp1250Map[rune]!);
      } else if (rune >= 0x80 && rune <= 0xFF) {
        // For characters in range 0x80-0xFF, check if they map directly
        // Many CP1250 characters at 0x80-0xFF have the same byte value
        // as their Unicode code point, but we need to be careful
        // For now, we'll check if it's a common overlap
        if (_isCP1250DirectMapping(rune)) {
          result.add(rune);
        } else {
          // Character not in CP1250 - replace with question mark
          result.add(0x3F); // '?'
        }
      } else {
        // Character outside CP1250 range - replace with question mark
        result.add(0x3F); // '?'
      }
    }

    return Uint8List.fromList(result);
  }

  /// Check if a Unicode code point in range 0x80-0xFF maps directly to CP1250
  /// This is true for many characters that are common between Unicode and CP1250
  bool _isCP1250DirectMapping(int codePoint) {
    // Characters that DON'T map directly in CP1250 (exceptions)
    // These byte positions are used by special characters in CP1250
    final Set<int> exceptions = {
      0x80,
      0x81,
      0x82,
      0x83,
      0x84,
      0x85,
      0x86,
      0x87,
      0x88,
      0x89, // Control chars
      0x8A,
      0x8C,
      0x8D,
      0x8E,
      0x8F, // Used by Croatian uppercase (Š, Ć, Č, Ž, Đ)
      0x90,
      0x9A,
      0x9C,
      0x9D,
      0x9E,
      0x9F, // Used by Croatian lowercase and others (š, ć, č, ž, ş)
      0xA0, // Used by đ
      0xAD, // Soft hyphen
      0xF9, // Used by ů
      0xFE, // Used by ť
    };
    return !exceptions.contains(codePoint);
  }

  List _getLexemes(String text) {
    final List<String> lexemes = [];
    final List<bool> isLexemeChinese = [];
    int start = 0;
    int end = 0;
    bool curLexemeChinese = _isChinese(text[0]);
    for (var i = 1; i < text.length; ++i) {
      if (curLexemeChinese == _isChinese(text[i])) {
        end += 1;
      } else {
        lexemes.add(text.substring(start, end + 1));
        isLexemeChinese.add(curLexemeChinese);
        start = i;
        end = i;
        curLexemeChinese = !curLexemeChinese;
      }
    }
    lexemes.add(text.substring(start, end + 1));
    isLexemeChinese.add(curLexemeChinese);

    return <dynamic>[lexemes, isLexemeChinese];
  }

  /// Break text into chinese/non-chinese lexemes
  bool _isChinese(String ch) {
    return ch.codeUnitAt(0) > 255;
  }

  /// Generate multiple bytes for a number: In lower and higher parts, or more parts as needed.
  ///
  /// [value] Input number
  /// [bytesNb] The number of bytes to output (1 - 4)
  List<int> _intLowHigh(int value, int bytesNb) {
    final dynamic maxInput = 256 << (bytesNb * 8) - 1;

    if (bytesNb < 1 || bytesNb > 4) {
      throw Exception('Can only output 1-4 bytes');
    }
    if (value < 0 || value > maxInput) {
      throw Exception(
        'Number is too large. Can only output up to $maxInput in $bytesNb bytes',
      );
    }

    final List<int> res = <int>[];
    int buf = value;
    for (int i = 0; i < bytesNb; ++i) {
      res.add(buf % 256);
      buf = buf ~/ 256;
    }
    return res;
  }

  /// Extract slices of an image as equal-sized blobs of column-format data.
  ///
  /// [image] Image to extract from
  /// [lineHeight] Printed line height in dots
  List<List<int>> _toColumnFormat(Image imgSrc, int lineHeight) {
    final Image image = Image.from(imgSrc); // make a copy

    // Determine new width: closest integer that is divisible by lineHeight
    final int widthPx = (image.width + lineHeight) - (image.width % lineHeight);
    final int heightPx = image.height;

    // Create a black bottom layer
    final biggerImage = copyResize(image, width: widthPx, height: heightPx);
    fill(biggerImage, color: ColorRgba8(0, 0, 0, 0));
    // Insert source image into bigger one
    compositeImage(biggerImage, image, dstX: 0, dstY: 0);

    int left = 0;
    final List<List<int>> blobs = [];

    while (left < widthPx) {
      final Image slice = copyCrop(
        biggerImage,
        x: left,
        y: 0,
        width: lineHeight,
        height: heightPx,
      );
      grayscale(slice);
      final imgBinary = slice.convert(numChannels: 1);
      final bytes = imgBinary.getBytes();
      blobs.add(bytes);
      left += lineHeight;
    }

    return blobs;
  }

  /// Image rasterization
  List<int> _toRasterFormat(Image imgSrc) {
    final Image image = Image.from(imgSrc); // make a copy
    final int widthPx = image.width;
    final int heightPx = image.height;

    grayscale(image);
    invert(image);

    // R/G/B channels are same -> keep only one channel
    final List<int> oneChannelBytes = [];
    final List<int> buffer = image.getBytes(order: ChannelOrder.rgba);
    for (int i = 0; i < buffer.length; i += 4) {
      oneChannelBytes.add(buffer[i]);
    }

    // Add some empty pixels at the end of each line (to make the width divisible by 8)
    if (widthPx % 8 != 0) {
      final targetWidth = (widthPx + 8) - (widthPx % 8);
      final missingPx = targetWidth - widthPx;
      final extra = Uint8List(missingPx);
      for (int i = 0; i < heightPx; i++) {
        final pos = (i * widthPx + widthPx) + i * missingPx;
        oneChannelBytes.insertAll(pos, extra);
      }
    }

    // Pack bits into bytes
    return _packBitsIntoBytes(oneChannelBytes);
  }

  /// Merges each 8 values (bits) into one byte
  List<int> _packBitsIntoBytes(List<int> bytes) {
    const pxPerLine = 8;
    final List<int> res = <int>[];
    const threshold = 127; // set the greyscale -> b/w threshold here
    for (int i = 0; i < bytes.length; i += pxPerLine) {
      int newVal = 0;
      for (int j = 0; j < pxPerLine; j++) {
        newVal = _transformUint32Bool(
          newVal,
          pxPerLine - j,
          bytes[i + j] > threshold,
        );
      }
      res.add(newVal ~/ 2);
    }
    return res;
  }

  /// Replaces a single bit in a 32-bit unsigned integer.
  int _transformUint32Bool(int uint32, int shift, bool newValue) {
    return ((0xFFFFFFFF ^ (0x1 << shift)) & uint32) |
        ((newValue ? 1 : 0) << shift);
  }
  // ************************ (end) Internal helpers  ************************

  //**************************** Public command generators ************************
  /// Clear the buffer and reset text styles
  List<int> reset() {
    List<int> bytes = [];
    bytes += cInit.codeUnits;
    _styles = PosStyles();
    bytes += setGlobalCodeTable(_codeTable);
    bytes += setGlobalFont(_font);
    return bytes;
  }

  /// Set global code table which will be used instead of the default printer's code table
  /// (even after resetting)
  List<int> setGlobalCodeTable(String? codeTable) {
    List<int> bytes = [];
    _codeTable = codeTable;

    // CP1250 uses direct byte mapping (no code table command needed)
    if (codeTable == 'CP1250') {
      // Just turn Kanji OFF and use default printer character set
      bytes += cKanjiOff.codeUnits;
      _styles = _styles.copyWith(codeTable: codeTable);
      return bytes;
    }

    // For other code tables, use standard ESC/POS commands
    // Always turn Kanji OFF before setting code table
    bytes += cKanjiOff.codeUnits;
    if (codeTable != null) {
      bytes += Uint8List.fromList(
        List.from(cCodeTable.codeUnits)..add(_profile.getCodePageId(codeTable)),
      );
      _styles = _styles.copyWith(codeTable: codeTable);
    }
    return bytes;
  }

  /// Set global font which will be used instead of the default printer's font
  /// (even after resetting)
  List<int> setGlobalFont(PosFontType? font, {int? maxCharsPerLine}) {
    List<int> bytes = [];
    _font = font;
    if (font != null) {
      _maxCharsPerLine = maxCharsPerLine ?? _getMaxCharsPerLine(font);
      bytes += font == PosFontType.fontB ? cFontB.codeUnits : cFontA.codeUnits;
      _styles = _styles.copyWith(fontType: font);
    }
    return bytes;
  }

  List<int> setStyles(PosStyles styles, {bool isKanji = false}) {
    List<int> bytes = [];

    // Always turn Kanji OFF first (before setting code table)
    // This ensures the printer is in the correct mode for code page encoding
    bytes += cKanjiOff.codeUnits;

    if (styles.align != _styles.align) {
      bytes +=
          (styles.align == PosAlign.left
                  ? cAlignLeft
                  : (styles.align == PosAlign.center
                        ? cAlignCenter
                        : cAlignRight))
              .codeUnits;
      _styles = _styles.copyWith(align: styles.align);
    }

    if (styles.bold != _styles.bold) {
      bytes += styles.bold ? cBoldOn.codeUnits : cBoldOff.codeUnits;
      _styles = _styles.copyWith(bold: styles.bold);
    }
    if (styles.turn90 != _styles.turn90) {
      bytes += styles.turn90 ? cTurn90On.codeUnits : cTurn90Off.codeUnits;
      _styles = _styles.copyWith(turn90: styles.turn90);
    }
    if (styles.reverse != _styles.reverse) {
      bytes += styles.reverse ? cReverseOn.codeUnits : cReverseOff.codeUnits;
      _styles = _styles.copyWith(reverse: styles.reverse);
    }
    if (styles.underline != _styles.underline) {
      bytes += styles.underline
          ? cUnderline1dot.codeUnits
          : cUnderlineOff.codeUnits;
      _styles = _styles.copyWith(underline: styles.underline);
    }

    // Set font
    if (styles.fontType != null && styles.fontType != _styles.fontType) {
      bytes += styles.fontType == PosFontType.fontB
          ? cFontB.codeUnits
          : cFontA.codeUnits;
      _styles = _styles.copyWith(fontType: styles.fontType);
    } else if (_font != null && _font != _styles.fontType) {
      bytes += _font == PosFontType.fontB ? cFontB.codeUnits : cFontA.codeUnits;
      _styles = _styles.copyWith(fontType: _font);
    }

    // Characters size
    if (styles.height.value != _styles.height.value ||
        styles.width.value != _styles.width.value) {
      bytes += Uint8List.fromList(
        List.from(cSizeGSn.codeUnits)
          ..add(PosTextSize.decSize(styles.height, styles.width)),
      );
      _styles = _styles.copyWith(height: styles.height, width: styles.width);
    }

    // Set code table (after Kanji OFF, before text)
    // CP1250 uses direct byte mapping (no code table command needed)
    final codeTableToUse = styles.codeTable ?? _codeTable;
    if (codeTableToUse != null && codeTableToUse != 'CP1250') {
      // Send code table command for non-CP1250 code tables
      bytes += Uint8List.fromList(
        List.from(cCodeTable.codeUnits)
          ..add(_profile.getCodePageId(codeTableToUse)),
      );
      _styles = _styles.copyWith(
        align: styles.align,
        codeTable: codeTableToUse,
      );
    } else if (codeTableToUse == 'CP1250') {
      // CP1250: Just update styles, no command needed
      _styles = _styles.copyWith(
        align: styles.align,
        codeTable: codeTableToUse,
      );
    }

    return bytes;
  }

  /// Sens raw command(s)
  List<int> rawBytes(List<int> cmd, {bool isKanji = false}) {
    List<int> bytes = [];
    // Always turn Kanji OFF - we don't need Chinese characters in Croatia!
    bytes += cKanjiOff.codeUnits;
    bytes += Uint8List.fromList(cmd);
    return bytes;
  }

  List<int> text(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    bool containsChinese = false,
    int? maxCharsPerLine,
  }) {
    List<int> bytes = [];
    if (!containsChinese) {
      // Use code table from styles or fall back to global code table
      final codeTableToUse = styles.codeTable ?? _codeTable;
      bytes += _text(
        _encode(text, isKanji: containsChinese, codeTable: codeTableToUse),
        styles: styles,
        isKanji: containsChinese,
        maxCharsPerLine: maxCharsPerLine,
      );
      // Ensure at least one line break after the text
      bytes += emptyLines(linesAfter + 1);
    } else {
      bytes += _mixedKanji(text, styles: styles, linesAfter: linesAfter);
    }
    return bytes;
  }

  /// Skips [n] lines
  ///
  /// Similar to [feed] but uses an alternative command
  List<int> emptyLines(int n) {
    List<int> bytes = [];
    if (n > 0) {
      bytes += List.filled(n, '\n').join().codeUnits;
    }
    return bytes;
  }

  /// Skips [n] lines
  ///
  /// Similar to [emptyLines] but uses an alternative command
  List<int> feed(int n) {
    List<int> bytes = [];
    if (n >= 0 && n <= 255) {
      bytes += Uint8List.fromList(List.from(cFeedN.codeUnits)..add(n));
    }
    return bytes;
  }

  /// Cut the paper
  ///
  /// [mode] is used to define the full or partial cut (if supported by the priner)
  List<int> cut({PosCutMode mode = PosCutMode.full}) {
    List<int> bytes = [];
    bytes += emptyLines(5);
    if (mode == PosCutMode.partial) {
      bytes += cCutPart.codeUnits;
    } else {
      bytes += cCutFull.codeUnits;
    }
    return bytes;
  }

  /// Print selected code table.
  ///
  /// If [codeTable] is null, global code table is used.
  /// If global code table is null, default printer code table is used.
  List<int> printCodeTable({String? codeTable}) {
    List<int> bytes = [];
    bytes += cKanjiOff.codeUnits;

    if (codeTable != null) {
      bytes += Uint8List.fromList(
        List.from(cCodeTable.codeUnits)..add(_profile.getCodePageId(codeTable)),
      );
    }

    bytes += Uint8List.fromList(List<int>.generate(256, (i) => i));

    // Back to initial code table
    setGlobalCodeTable(_codeTable);
    return bytes;
  }

  /// Beeps [n] times
  ///
  /// Beep [duration] could be between 50 and 450 ms.
  List<int> beep({
    int n = 3,
    PosBeepDuration duration = PosBeepDuration.beep450ms,
  }) {
    List<int> bytes = [];
    if (n <= 0) {
      return [];
    }

    int beepCount = n;
    if (beepCount > 9) {
      beepCount = 9;
    }

    bytes += Uint8List.fromList(
      List.from(cBeep.codeUnits)..addAll([beepCount, duration.value]),
    );

    beep(n: n - 9, duration: duration);
    return bytes;
  }

  /// Reverse feed for [n] lines (if supported by the priner)
  List<int> reverseFeed(int n) {
    List<int> bytes = [];
    bytes += Uint8List.fromList(List.from(cReverseFeedN.codeUnits)..add(n));
    return bytes;
  }

  /// Print a row.
  ///
  /// A row contains up to 12 columns. A column has a width between 1 and 12.
  /// Total width of columns in one row must be equal 12.
  List<int> row(List<PosColumn> cols) {
    List<int> bytes = [];
    final isSumValid = cols.fold(0, (int sum, col) => sum + col.width) == 12;
    if (!isSumValid) {
      throw Exception('Total columns width must be equal to 12');
    }
    bool isNextRow = false;
    List<PosColumn> nextRow = <PosColumn>[];

    for (int i = 0; i < cols.length; ++i) {
      int colInd = cols
          .sublist(0, i)
          .fold(0, (int sum, col) => sum + col.width);
      double charWidth = _getCharWidth(cols[i].styles);
      double fromPos = _colIndToPosition(colInd);
      final double toPos =
          _colIndToPosition(colInd + cols[i].width) - spaceBetweenRows;
      int maxCharactersNb = ((toPos - fromPos) / charWidth).floor();

      if (!cols[i].containsChinese) {
        // CASE 1: containsChinese = false
        Uint8List encodedToPrint = cols[i].textEncoded != null
            ? cols[i].textEncoded!
            : _encode(cols[i].text, codeTable: cols[i].styles.codeTable);

        // If the col's content is too long, split it to the next row
        int realCharactersNb = encodedToPrint.length;
        if (realCharactersNb > maxCharactersNb) {
          // Print max possible and split to the next row
          Uint8List encodedToPrintNextRow = encodedToPrint.sublist(
            maxCharactersNb,
          );
          encodedToPrint = encodedToPrint.sublist(0, maxCharactersNb);
          isNextRow = true;
          nextRow.add(
            PosColumn(
              textEncoded: encodedToPrintNextRow,
              width: cols[i].width,
              styles: cols[i].styles,
            ),
          );
        } else {
          // Insert an empty col
          nextRow.add(
            PosColumn(text: '', width: cols[i].width, styles: cols[i].styles),
          );
        }
        // end rows splitting
        bytes += _text(
          encodedToPrint,
          styles: cols[i].styles,
          colInd: colInd,
          colWidth: cols[i].width,
        );
      } else {
        // CASE 1: containsChinese = true
        // Split text into multiple lines if it too long
        int counter = 0;
        int splitPos = 0;
        for (int p = 0; p < cols[i].text.length; ++p) {
          final int w = _isChinese(cols[i].text[p]) ? 2 : 1;
          if (counter + w >= maxCharactersNb) {
            break;
          }
          counter += w;
          splitPos += 1;
        }
        String toPrintNextRow = cols[i].text.substring(splitPos);
        String toPrint = cols[i].text.substring(0, splitPos);

        if (toPrintNextRow.isNotEmpty) {
          isNextRow = true;
          nextRow.add(
            PosColumn(
              text: toPrintNextRow,
              containsChinese: true,
              width: cols[i].width,
              styles: cols[i].styles,
            ),
          );
        } else {
          // Insert an empty col
          nextRow.add(
            PosColumn(text: '', width: cols[i].width, styles: cols[i].styles),
          );
        }

        // Print current row
        final list = _getLexemes(toPrint);
        final List<String> lexemes = list[0];
        final List<bool> isLexemeChinese = list[1];

        // Print each lexeme using codetable OR kanji
        for (var j = 0; j < lexemes.length; ++j) {
          bytes += _text(
            _encode(
              lexemes[j],
              isKanji: isLexemeChinese[j],
              codeTable: cols[i].styles.codeTable,
            ),
            styles: cols[i].styles,
            colInd: colInd,
            colWidth: cols[i].width,
            isKanji: isLexemeChinese[j],
          );
          // Define the absolute position only once (we print one line only)
          // colInd = null;
        }
      }
    }

    bytes += emptyLines(1);

    if (isNextRow) {
      row(nextRow);
    }
    return bytes;
  }

  /// Print an image using (ESC *) command
  ///
  /// [image] is an instanse of class from [Image library](https://pub.dev/packages/image)
  List<int> image(Image imgSrc, {PosAlign align = PosAlign.center}) {
    List<int> bytes = [];
    // Image alignment
    bytes += setStyles(PosStyles().copyWith(align: align));

    final Image image = Image.from(imgSrc); // make a copy

    invert(image);
    flip(image, direction: FlipDirection.horizontal);
    final Image imageRotated = copyRotate(image, angle: 270);

    const int lineHeight = 3;
    final List<List<int>> blobs = _toColumnFormat(imageRotated, lineHeight * 8);

    // Compress according to line density
    // Line height contains 8 or 24 pixels of src image
    // Each blobs[i] contains greyscale bytes [0-255]
    // const int pxPerLine = 24 ~/ lineHeight;
    for (int blobInd = 0; blobInd < blobs.length; blobInd++) {
      blobs[blobInd] = _packBitsIntoBytes(blobs[blobInd]);
    }

    final int heightPx = imageRotated.height;
    const int densityByte = 33;

    final List<int> header = List.from(cBitImg.codeUnits);
    header.add(densityByte);
    header.addAll(_intLowHigh(heightPx, 2));

    // Adjust line spacing (for 16-unit line feeds): ESC 3 0x10 (HEX: 0x1b 0x33 0x10)
    bytes += [27, 51, 16];
    for (int i = 0; i < blobs.length; ++i) {
      bytes += List.from(header)
        ..addAll(blobs[i])
        ..addAll('\n'.codeUnits);
    }
    // Reset line spacing: ESC 2 (HEX: 0x1b 0x32)
    bytes += [27, 50];
    return bytes;
  }

  /// Print an image using (GS v 0) obsolete command
  ///
  /// [image] is an instanse of class from [Image library](https://pub.dev/packages/image)
  List<int> imageRaster(
    Image image, {
    PosAlign align = PosAlign.center,
    bool highDensityHorizontal = true,
    bool highDensityVertical = true,
    PosImageFn imageFn = PosImageFn.bitImageRaster,
  }) {
    List<int> bytes = [];
    // Image alignment
    bytes += setStyles(PosStyles().copyWith(align: align));

    final int widthPx = image.width;
    final int heightPx = image.height;
    final int widthBytes = (widthPx + 7) ~/ 8;
    final List<int> resterizedData = _toRasterFormat(image);

    if (imageFn == PosImageFn.bitImageRaster) {
      // GS v 0
      final int densityByte =
          (highDensityVertical ? 0 : 1) + (highDensityHorizontal ? 0 : 2);

      final List<int> header = List.from(cRasterImg2.codeUnits);
      header.add(densityByte); // m
      header.addAll(_intLowHigh(widthBytes, 2)); // xL xH
      header.addAll(_intLowHigh(heightPx, 2)); // yL yH
      bytes += List.from(header)..addAll(resterizedData);
    } else if (imageFn == PosImageFn.graphics) {
      // 'GS ( L' - FN_112 (Image data)
      final List<int> header1 = List.from(cRasterImg.codeUnits);
      header1.addAll(_intLowHigh(widthBytes * heightPx + 10, 2)); // pL pH
      header1.addAll([48, 112, 48]); // m=48, fn=112, a=48
      header1.addAll([1, 1]); // bx=1, by=1
      header1.addAll([49]); // c=49
      header1.addAll(_intLowHigh(widthBytes, 2)); // xL xH
      header1.addAll(_intLowHigh(heightPx, 2)); // yL yH
      bytes += List.from(header1)..addAll(resterizedData);

      // 'GS ( L' - FN_50 (Run print)
      final List<int> header2 = List.from(cRasterImg.codeUnits);
      header2.addAll([2, 0]); // pL pH
      header2.addAll([48, 50]); // m fn[2,50]
      bytes += List.from(header2);
    }
    return bytes;
  }

  /// Print a barcode
  ///
  /// [width] range and units are different depending on the printer model (some printers use 1..5).
  /// [height] range: 1 - 255. The units depend on the printer model.
  /// Width, height, font, text position settings are effective until performing of ESC @, reset or power-off.
  List<int> barcode(
    Barcode barcode, {
    int? width,
    int? height,
    BarcodeFont? font,
    BarcodeText textPos = BarcodeText.below,
    PosAlign align = PosAlign.center,
  }) {
    List<int> bytes = [];
    // Set alignment
    bytes += setStyles(PosStyles().copyWith(align: align));

    // Set text position
    bytes += cBarcodeSelectPos.codeUnits + [textPos.value];

    // Set font
    if (font != null) {
      bytes += cBarcodeSelectFont.codeUnits + [font.value];
    }

    // Set width
    if (width != null && width >= 0) {
      bytes += cBarcodeSetW.codeUnits + [width];
    }
    // Set height
    if (height != null && height >= 1 && height <= 255) {
      bytes += cBarcodeSetH.codeUnits + [height];
    }

    // Print barcode
    final header = cBarcodePrint.codeUnits + [barcode.type!.value];
    if (barcode.type!.value <= 6) {
      // Function A
      bytes += header + barcode.data! + [0];
    } else {
      // Function B
      bytes += header + [barcode.data!.length] + barcode.data!;
    }
    return bytes;
  }

  /// Print a QR Code
  List<int> qrcode(
    String text, {
    PosAlign align = PosAlign.center,
    QRSize size = QRSize.Size4,
    QRCorrection cor = QRCorrection.L,
  }) {
    List<int> bytes = [];
    // Set alignment
    bytes += setStyles(PosStyles().copyWith(align: align));
    QRCode qr = QRCode(text, size, cor);
    bytes += qr.bytes;
    return bytes;
  }

  /// Open cash drawer
  List<int> drawer({PosDrawer pin = PosDrawer.pin2}) {
    List<int> bytes = [];
    if (pin == PosDrawer.pin2) {
      bytes += cCashDrawerPin2.codeUnits;
    } else {
      bytes += cCashDrawerPin5.codeUnits;
    }
    return bytes;
  }

  /// Print horizontal full width separator
  /// If [len] is null, then it will be defined according to the paper width
  List<int> hr({String ch = '-', int? len, int linesAfter = 0}) {
    List<int> bytes = [];
    int n = len ?? _maxCharsPerLine ?? _getMaxCharsPerLine(_styles.fontType);
    String ch1 = ch.length == 1 ? ch : ch[0];
    bytes += text(List.filled(n, ch1).join(), linesAfter: linesAfter);
    return bytes;
  }

  List<int> textEncoded(
    Uint8List textBytes, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    List<int> bytes = [];
    bytes += _text(textBytes, styles: styles, maxCharsPerLine: maxCharsPerLine);
    // Ensure at least one line break after the text
    bytes += emptyLines(linesAfter + 1);
    return bytes;
  }
  // ************************ (end) Public command generators ************************

  // ************************ (end) Internal command generators ************************
  /// Generic print for internal use
  ///
  /// [colInd] range: 0..11. If null: do not define the position
  List<int> _text(
    Uint8List textBytes, {
    PosStyles styles = const PosStyles(),
    int? colInd = 0,
    bool isKanji = false,
    int colWidth = 12,
    int? maxCharsPerLine,
  }) {
    List<int> bytes = [];
    if (colInd != null) {
      double charWidth = _getCharWidth(
        styles,
        maxCharsPerLine: maxCharsPerLine,
      );
      double fromPos = _colIndToPosition(colInd);

      // Align
      if (colWidth != 12) {
        // Update fromPos
        final double toPos =
            _colIndToPosition(colInd + colWidth) - spaceBetweenRows;
        final double textLen = textBytes.length * charWidth;

        if (styles.align == PosAlign.right) {
          fromPos = toPos - textLen;
        } else if (styles.align == PosAlign.center) {
          fromPos = fromPos + (toPos - fromPos) / 2 - textLen / 2;
        }
        if (fromPos < 0) {
          fromPos = 0;
        }
      }

      final hexStr = fromPos.round().toRadixString(16).padLeft(3, '0');
      final hexPair = HEX.decode(hexStr);

      // Position
      bytes += Uint8List.fromList(
        List.from(cPos.codeUnits)..addAll([hexPair[1], hexPair[0]]),
      );
    }

    bytes += setStyles(styles, isKanji: isKanji);

    // CP1250 uses direct byte mapping - no additional commands needed
    // Text bytes are already encoded with the correct Croatian character mappings

    bytes += textBytes;
    return bytes;
  }

  /// Prints one line of styled mixed (chinese and latin symbols) text
  List<int> _mixedKanji(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    List<int> bytes = [];
    final list = _getLexemes(text);
    final List<String> lexemes = list[0];
    final List<bool> isLexemeChinese = list[1];

    // Print each lexeme using codetable OR kanji
    int? colInd = 0;
    for (var i = 0; i < lexemes.length; ++i) {
      bytes += _text(
        _encode(
          lexemes[i],
          isKanji: isLexemeChinese[i],
          codeTable: styles.codeTable,
        ),
        styles: styles,
        colInd: colInd,
        isKanji: isLexemeChinese[i],
        maxCharsPerLine: maxCharsPerLine,
      );
      // Define the absolute position only once (we print one line only)
      colInd = null;
    }

    bytes += emptyLines(linesAfter + 1);
    return bytes;
  }

  // ************************ (end) Internal command generators ************************
}
