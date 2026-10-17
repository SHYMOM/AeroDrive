import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodrive/core/constants.dart';
import 'package:aerodrive/domain/infrastructure/channel_description_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AeroDrive 4 Minimum Channels Infrastructure Tests', () {
    late SecretKey masterKey;
    const keySalt = 'TestKeySalt12345';

    setUp(() async {
      final cipher = AesGcm.with256bits();
      masterKey = await cipher.newSecretKey();
    });

    test('ChannelConstants specifies exactly 2 default storage channels (4 channels total with config and shared)', () {
      expect(ChannelConstants.defaultStorageChannelCount, equals(2));
      expect(ChannelConstants.configChannelName, equals('AeroDrive Config'));
      expect(ChannelConstants.sharedChannelName, equals('AeroDrive Shared'));
      expect(ChannelConstants.storageChannelBaseName, equals('AeroDrive Storage'));
    });

    test('ChannelDescriptionCodec encodes and decodes Storage Channel 1', () async {
      final desc = await ChannelDescriptionCodec.encode(
        purpose: ChannelConstants.descriptionPurposeStorage,
        appVersion: '0.1.0',
        keySalt: keySalt,
        channelIndex: 0,
        totalStorageChannels: 2,
        masterKey: masterKey,
      );

      expect(desc.startsWith(ChannelConstants.infraDescriptionPrefix), isTrue);

      final metadata = await ChannelDescriptionCodec.decode(description: desc, masterKey: masterKey);
      expect(metadata, isNotNull);
      expect(metadata!['p'], equals(ChannelConstants.descriptionPurposeStorage));
      expect(metadata['ci'], equals(0));
      expect(metadata['tc'], equals(2));
      expect(metadata['ks'], equals(keySalt));
    });

    test('ChannelDescriptionCodec encodes and decodes Storage Channel 2', () async {
      final desc = await ChannelDescriptionCodec.encode(
        purpose: ChannelConstants.descriptionPurposeStorage,
        appVersion: '0.1.0',
        keySalt: keySalt,
        channelIndex: 1,
        totalStorageChannels: 2,
        masterKey: masterKey,
      );

      final metadata = await ChannelDescriptionCodec.decode(description: desc, masterKey: masterKey);
      expect(metadata, isNotNull);
      expect(metadata!['p'], equals(ChannelConstants.descriptionPurposeStorage));
      expect(metadata['ci'], equals(1));
      expect(metadata['tc'], equals(2));
    });

    test('ChannelDescriptionCodec encodes and decodes Config Channel', () async {
      final desc = await ChannelDescriptionCodec.encode(
        purpose: ChannelConstants.descriptionPurposeConfig,
        appVersion: '0.1.0',
        keySalt: keySalt,
        channelIndex: 0,
        totalStorageChannels: 2,
        masterKey: masterKey,
      );

      final metadata = await ChannelDescriptionCodec.decode(description: desc, masterKey: masterKey);
      expect(metadata, isNotNull);
      expect(metadata!['p'], equals(ChannelConstants.descriptionPurposeConfig));
    });

    test('ChannelDescriptionCodec encodes and decodes Shared Channel', () async {
      final desc = await ChannelDescriptionCodec.encode(
        purpose: ChannelConstants.descriptionPurposeShared,
        appVersion: '0.1.0',
        keySalt: keySalt,
        channelIndex: 0,
        totalStorageChannels: 2,
        masterKey: masterKey,
      );

      final metadata = await ChannelDescriptionCodec.decode(description: desc, masterKey: masterKey);
      expect(metadata, isNotNull);
      expect(metadata!['p'], equals(ChannelConstants.descriptionPurposeShared));
    });

    test('ChannelDescriptionCodec rejects decryption with wrong master key', () async {
      final desc = await ChannelDescriptionCodec.encode(
        purpose: ChannelConstants.descriptionPurposeStorage,
        appVersion: '0.1.0',
        keySalt: keySalt,
        channelIndex: 0,
        totalStorageChannels: 2,
        masterKey: masterKey,
      );

      final wrongKey = await AesGcm.with256bits().newSecretKey();
      final metadata = await ChannelDescriptionCodec.decode(description: desc, masterKey: wrongKey);
      expect(metadata, isNull);
    });

    test('Share Link payload formatting, encryption, and parsing', () async {
      const globalPassphrase = 'AeroDrive_Global_Secure_Sharing_Key_2026!';
      final hash = await Sha256().hash(utf8.encode(globalPassphrase));
      final globalKeyBytes = hash.bytes;

      final cipher = AesGcm.with256bits();
      final secretKey = await cipher.newSecretKeyFromBytes(globalKeyBytes);

      // Create sample payload
      const inviteLink = 'https://t.me/+AbCdEfGhIj';
      const shareChatId = -1001234567890;
      const manifestMsgId = 42;
      const shareId = 'share-uuid-test-999';

      final payloadMap = {
        'invite': inviteLink,
        'channelId': shareChatId,
        'manifest': manifestMsgId,
        'id': shareId,
        'manifestKey': base64Url.encode([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]),
      };

      // Encrypt payload
      final box = await cipher.encrypt(utf8.encode(jsonEncode(payloadMap)), secretKey: secretKey);
      final encryptedB64 = base64Encode(box.concatenation());
      final publicUrl = 'aerodrive://share?p=${Uri.encodeComponent(encryptedB64)}';

      // Parse and decrypt URL
      final parsedUri = Uri.parse(publicUrl);
      expect(parsedUri.scheme, equals('aerodrive'));
      expect(parsedUri.host, equals('share'));

      final pParam = parsedUri.queryParameters['p'];
      expect(pParam, isNotNull);

      final decodedConcatenation = base64Decode(Uri.decodeComponent(pParam!));
      final decryptedBox = SecretBox.fromConcatenation(decodedConcatenation, nonceLength: 12, macLength: 16);
      final decryptedBytes = await cipher.decrypt(decryptedBox, secretKey: secretKey);
      final decryptedMap = jsonDecode(utf8.decode(decryptedBytes)) as Map<String, dynamic>;

      expect(decryptedMap['invite'], equals(inviteLink));
      expect(decryptedMap['channelId'], equals(shareChatId));
      expect(decryptedMap['manifest'], equals(manifestMsgId));
      expect(decryptedMap['id'], equals(shareId));
    });
  });
}
