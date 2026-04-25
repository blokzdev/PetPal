import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/sync/cloud_sync_adapter.dart';

void main() {
  test('NoopCloudSyncAdapter starts idle and stays idle through push/pull',
      () async {
    final sync = NoopCloudSyncAdapter();
    expect(sync.status.state, SyncState.idle);
    expect(sync.status.lastSyncAt, isNull);

    final pushed = await sync.push(petId: 1);
    expect(pushed.changedPaths, isEmpty);
    expect(sync.status.state, SyncState.idle);
    expect(sync.status.lastSyncAt, isNotNull);

    final pulled = await sync.pull(petId: 1);
    expect(pulled.changedPaths, isEmpty);
    expect(sync.status.state, SyncState.idle);
  });
}
