import test from 'node:test';
import assert from 'node:assert/strict';
import {
  RoomRegistryUnavailableError,
  isRoomRegistryUnavailableError,
} from '../services/RoomRegistryService';

test('isRoomRegistryUnavailableError detects registry-unavailable errors', () => {
  assert.equal(
    isRoomRegistryUnavailableError(new RoomRegistryUnavailableError()),
    true
  );
  assert.equal(
    isRoomRegistryUnavailableError({ code: 'BACKEND_UNAVAILABLE_FIREBASE' }),
    true
  );
  assert.equal(
    isRoomRegistryUnavailableError({ code: 'unavailable' }),
    true
  );
  assert.equal(
    isRoomRegistryUnavailableError({ code: 'deadline-exceeded' }),
    true
  );
  assert.equal(isRoomRegistryUnavailableError({ code: 'unknown' }), false);
});
