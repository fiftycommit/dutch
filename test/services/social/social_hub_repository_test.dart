import 'package:dutch_game/services/social/social_hub_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SocialHubRepository', () {
    late SocialHubRepository repository;
    late DateTime fixedNow;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      repository = SocialHubRepository();
      fixedNow = DateTime.utc(2026, 2, 11, 12, 0, 0);
    });

    group('username helpers', () {
      test('normalizes username with trim + lowercase', () {
        expect(
          SocialHubRepository.normalizeUsername('  PeGga.PIG  '),
          'pegga.pig',
        );
      });

      test('allows only expected username characters', () {
        expect(
          SocialHubRepository.containsOnlyAllowedUsernameChars('pegga.pig_1'),
          isTrue,
        );
        expect(
          SocialHubRepository.containsOnlyAllowedUsernameChars('PEGGA.PIG'),
          isTrue,
        );
        expect(
          SocialHubRepository.containsOnlyAllowedUsernameChars('pegga-pig'),
          isTrue,
        );
        expect(
          SocialHubRepository.containsOnlyAllowedUsernameChars('pegga-étoile'),
          isTrue,
        );
        expect(
          SocialHubRepository.containsOnlyAllowedUsernameChars('pegga pig'),
          isFalse,
        );
        expect(
          SocialHubRepository.containsOnlyAllowedUsernameChars('pegga@pig'),
          isFalse,
        );
      });

      test('validates full username format', () {
        expect(SocialHubRepository.isValidUsernameFormat('pegga.pig'), isTrue);
        expect(
          SocialHubRepository.isValidUsernameFormat('pegga-étoile'),
          isTrue,
        );
        expect(SocialHubRepository.isValidUsernameFormat('ab'), isFalse);
        expect(
            SocialHubRepository.isValidUsernameFormat('bad username'), isFalse);
      });
    });

    group('reserved usernames', () {
      test('builds hashed reserved set from all local social sources',
          () async {
        await repository.saveProfile(
          SocialProfile(
            displayName: 'Pegga',
            username: 'pegga.pig',
            roomInviteNotificationsEnabled: true,
            createdAt: fixedNow,
            updatedAt: fixedNow,
          ),
        );
        await repository.addFriendRequest(
          username: 'friend_01',
          displayName: 'Friend',
          direction: FriendRequestDirection.incoming,
        );
        await repository.acceptIncomingRequest('friend_01');
        await repository.addFriendRequest(
          username: 'pending.one',
          displayName: 'Pending',
          direction: FriendRequestDirection.incoming,
        );
        await repository.addFriendRequest(
          username: 'pending.one',
          displayName: 'Pending',
          direction: FriendRequestDirection.outgoing,
        );
        await repository.blockUser('blocked.user');

        final reserved = await repository.getReservedUsernames();

        expect(
          reserved,
          containsAll(<String>[
            'pegga.pig',
            'friend_01',
            'pending.one',
            'blocked.user',
          ]),
        );
        // pending.one appears twice (incoming/outgoing) but should be deduped.
        expect(reserved.length, 4);
      });

      test('supports exceptUsername while checking reserved set', () async {
        await repository.saveProfile(
          SocialProfile(
            displayName: 'Pegga',
            username: 'pegga.pig',
            roomInviteNotificationsEnabled: false,
            createdAt: fixedNow,
            updatedAt: fixedNow,
          ),
        );

        final withoutExcept = await repository.getReservedUsernames();
        final withExcept = await repository.getReservedUsernames(
          exceptUsername: 'pegga.pig',
        );

        expect(withoutExcept, contains('pegga.pig'));
        expect(withExcept, isNot(contains('pegga.pig')));
      });
    });

    group('isUsernameAvailableLocally', () {
      test('rejects invalid format and occupied usernames', () async {
        await repository.saveProfile(
          SocialProfile(
            displayName: 'Pegga',
            username: 'pegga.pig',
            roomInviteNotificationsEnabled: true,
            createdAt: fixedNow,
            updatedAt: fixedNow,
          ),
        );

        expect(
          await repository.isUsernameAvailableLocally('bad username'),
          isFalse,
        );
        expect(
          await repository.isUsernameAvailableLocally('pegga.pig'),
          isFalse,
        );
      });

      test('accepts own username via exceptUsername and allows free username',
          () async {
        await repository.saveProfile(
          SocialProfile(
            displayName: 'Pegga',
            username: 'pegga.pig',
            roomInviteNotificationsEnabled: true,
            createdAt: fixedNow,
            updatedAt: fixedNow,
          ),
        );

        expect(
          await repository.isUsernameAvailableLocally(
            'pegga.pig',
            exceptUsername: 'pegga.pig',
          ),
          isTrue,
        );
        expect(
          await repository.isUsernameAvailableLocally('new.friend'),
          isTrue,
        );
      });
    });
  });
}
