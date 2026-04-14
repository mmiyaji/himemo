import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_flavor.dart';
import 'play_integrity_service.dart';

class PlayIntegrityVerificationResult {
  const PlayIntegrityVerificationResult({
    required this.allowed,
    required this.message,
    this.challenge,
    this.deviceVerdicts = const <String>[],
  });

  final bool allowed;
  final String message;
  final String? challenge;
  final List<String> deviceVerdicts;
}

class PlayIntegrityVerifier {
  const PlayIntegrityVerifier({
    required PlayIntegrityService playIntegrityService,
    http.Client? httpClient,
  }) : _playIntegrityService = playIntegrityService,
       _httpClient = httpClient;

  static const _challengeEndpoint =
      'https://asia-northeast1-himemo-app-2026.cloudfunctions.net/issuePlayIntegrityChallengeV2';
  static const _verifyEndpoint =
      'https://verifyplayintegrityv2-4yz7jselhq-an.a.run.app';

  final PlayIntegrityService _playIntegrityService;
  final http.Client? _httpClient;

  Future<PlayIntegrityVerificationResult> verifyOperation({
    required AppFlavor flavor,
    required String operation,
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const PlayIntegrityVerificationResult(
        allowed: true,
        message: 'Play Integrity is only enforced on Android.',
      );
    }

    final availability = await _playIntegrityService.checkAvailability();
    if (!availability.isAvailable) {
      return PlayIntegrityVerificationResult(
        allowed: flavor == AppFlavor.development,
        message: flavor == AppFlavor.development
            ? 'Play Integrity is unavailable in this development runtime.'
            : availability.message,
      );
    }

    final packageName = switch (flavor) {
      AppFlavor.development => 'org.ruhenheim.himemo.dev',
      AppFlavor.production => 'org.ruhenheim.himemo',
    };

    final client = _httpClient ?? http.Client();
    try {
      final challengeResult = await _requestChallenge(
        client: client,
        flavor: flavor,
        packageName: packageName,
        operation: operation,
      );
      if (!challengeResult.allowed || challengeResult.challenge == null) {
        return challengeResult;
      }

      final integrityToken = await _playIntegrityService.requestClassicToken(
        requestHash: challengeResult.challenge!,
      );

      final response = await client.post(
        Uri.parse(_verifyEndpoint),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'packageName': packageName,
          'operation': operation,
          'challenge': challengeResult.challenge,
          'integrityToken': integrityToken,
          'payload': payload,
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return PlayIntegrityVerificationResult(
          allowed: flavor == AppFlavor.development,
          message: flavor == AppFlavor.development
              ? 'Play Integrity backend verification is unavailable in development.'
              : 'Play Integrity backend returned ${response.statusCode}.',
          challenge: challengeResult.challenge,
        );
      }

      final body = Map<String, dynamic>.from(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      final verdictOk = body['verdictOk'] as bool? ?? false;
      final verdicts = ((body['deviceIntegrity'] as Map?)?['verdicts'] as List?)
              ?.map((entry) => '$entry')
              .toList(growable: false) ??
          const <String>[];
      return PlayIntegrityVerificationResult(
        allowed: verdictOk,
        message: verdictOk
            ? 'Play Integrity verification passed.'
            : 'Play Integrity verification did not pass.',
        challenge: challengeResult.challenge,
        deviceVerdicts: verdicts,
      );
    } catch (error) {
      if (flavor == AppFlavor.development) {
        return PlayIntegrityVerificationResult(
          allowed: true,
          message: 'Play Integrity verification was skipped in development: $error',
        );
      }
      return PlayIntegrityVerificationResult(
        allowed: false,
        message: 'Play Integrity verification failed: $error',
      );
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }

  Future<PlayIntegrityVerificationResult> _requestChallenge({
    required http.Client client,
    required AppFlavor flavor,
    required String packageName,
    required String operation,
  }) async {
    final response = await client.post(
      Uri.parse(_challengeEndpoint),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'packageName': packageName,
        'operation': operation,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return PlayIntegrityVerificationResult(
        allowed: flavor == AppFlavor.development,
        message: flavor == AppFlavor.development
            ? 'Challenge endpoint is unavailable in development.'
            : 'Challenge endpoint returned ${response.statusCode}.',
      );
    }

    final body = Map<String, dynamic>.from(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    final challenge = body['challenge'] as String?;
    if (challenge == null || challenge.isEmpty) {
      return PlayIntegrityVerificationResult(
        allowed: flavor == AppFlavor.development,
        message: flavor == AppFlavor.development
            ? 'Challenge was missing in development.'
            : 'Challenge endpoint returned an empty challenge.',
      );
    }
    return PlayIntegrityVerificationResult(
      allowed: true,
      message: 'Challenge issued.',
      challenge: challenge,
    );
  }
}
