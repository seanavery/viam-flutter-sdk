import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class MimeType {
  final String _type;
  final String _name;
  static final Map<String, MimeType> _map = {
    'image/vnd.viam.rgba': MimeType.viamRgba,
    'image/jpeg': MimeType.jpeg,
    'image/png': MimeType.png,
    'pointcloud/pcd': MimeType.pcd,
  };

  /// The name of the MimeType, e.g. 'image/jpeg'
  /// If the MimeType is not supported, then this [name] is the string of the unsupported MimeType.
  String get name => _name;

  const MimeType._(this._type, this._name);

  static MimeType get viamRgba => MimeType._('viamRgba', 'image/vnd.viam.rgba');
  static MimeType get jpeg => MimeType._('jpeg', 'image/jpeg');
  static MimeType get png => MimeType._('png', 'image/png');
  static MimeType get pcd => MimeType._('pcd', 'pointcloud/pcd');

  /// An unsupported MimeType takes in the String representation of the mimetype that is not supported.
  const MimeType.unsupported(this._name) : this._type = 'unsupported';

  static MimeType fromString(String mimeType) => _map[mimeType] ?? MimeType.unsupported(mimeType);

  static bool isSupported(String mimeType) {
    return _map.containsKey(mimeType);
  }

  bool operator ==(covariant MimeType other) {
    return _name == other._name;
  }

  int get hashCode => Object.hash(_type, _name);

  img.Image? decode(List<int> bytes) {
    img.Decoder? decoder;
    switch (_type) {
      case 'viamRgba':
        decoder = _ViamRGBADecoder();
        break;
      case 'jpeg':
        decoder = img.JpegDecoder();
        break;
      case 'png':
        decoder = img.PngDecoder();
        break;
      case 'pcd':
        decoder = null;
        break;
      case 'unsupported':
        decoder = null;
        break;
    }
    if (decoder == null) {
      return null;
    }
    return decoder.decode(Uint8List.fromList(bytes));
  }
}

class ViamImage {
  /// The mimetype of the image
  final MimeType mimeType;

  /// The raw bytes of the image
  final List<int> raw;

  bool _imageDecoded = false;
  img.Image? _image;

  /// The decoded image, if available. If the [MimeType] is not supported, this will be null.
  img.Image? get image {
    if (_imageDecoded) {
      return _image;
    }
    _image = this.mimeType.decode(this.raw);
    _imageDecoded = true;
    return _image;
  }

  ViamImage(this.raw, this.mimeType);
}

class _ViamRGBAInfo extends img.DecodeInfo {
  @override
  img.Color? get backgroundColor => null;

  @override
  int height = 0;

  @override
  int get numFrames => 1;

  @override
  int width = 0;
}

class _ViamRGBADecoder extends img.Decoder {
  final _info = _ViamRGBAInfo();
  late img.InputBuffer _input;

  _ViamRGBAInfo get info => _info;

  @override
  img.Image? decode(Uint8List bytes, {int? frame}) {
    if (startDecode(bytes) == null) {
      return null;
    }
    return decodeFrame(0);
  }

  @override
  img.Image? decodeFrame(int frame) {
    Uint8List imageData;

    final image = img.Image(
      width: info.width,
      height: info.height,
      numChannels: 4,
    );
    int bitsPerPixel = 32;
    final rowStride = ((_info.width * bitsPerPixel + 31) ~/ 32) * 4;

    for (var y = image.height - 1; y >= 0; --y) {
      final line = image.height - 1 - y;
      final row = _input.readBytes(rowStride);
      final w = image.width;
      var x = 0;
      final p = image.getPixel(0, line);
      while (x < w) {
        num r = row.readByte();
        num g = row.readByte();
        num b = row.readByte();
        num a = row.readByte();
        p.setRgba(r, g, b, a);
        p.moveNext();
        x++;
      }
    }

    return image;
  }

  @override
  bool isValidFile(Uint8List bytes) {
    final input = img.InputBuffer(bytes, bigEndian: true);
    final data = input.readBytes(4);
    final rgbaHeader = utf8.encode('RGBA');
    for (var i = 0; i < 4; ++i) {
      if (data[i] != rgbaHeader[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int numFrames() {
    return 1;
  }

  @override
  img.DecodeInfo? startDecode(Uint8List bytes) {
    final input = img.InputBuffer(bytes, bigEndian: true);

    final rgbaHeader = 'RGBA';
    final header = input.readBytes(4).readStringUtf8();
    if (header != rgbaHeader) {
      return null;
    }

    final width = input.readUint32();
    final height = input.readUint32();

    _input = input;

    return _info
      ..width = width
      ..height = height;
  }
}
