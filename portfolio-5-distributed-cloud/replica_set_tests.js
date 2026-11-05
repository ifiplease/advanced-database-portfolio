// 1. Replica set topology
(function replicaSetTopology() {
  const vp = db.getSiblingDB('vanguardpay_nosql');
  const h = vp.hello();
  printjson({
    replica_set: h.setName,
    connected_to: h.me,
    primary: h.primary,
    secondaries: h.hosts.filter((x) => x !== h.primary),
    members: h.hosts.length,
    is_writable_primary: h.isWritablePrimary
  });
  try {
    printjson(rs.status().members.map((m) => ({ name: m.name, state: m.stateStr })));
  } catch (e) {
    print('rs.status() is not available on this cluster tier: ' + e.message);
  }
})();

// 2. Write concern tests
(function writeConcernTests() {
  const tests = db.getSiblingDB('vanguardpay_nosql').replication_tests;
  tests.drop();

  const timed = (label, concern, n) => {
    const start = Date.now();
    let acknowledged = 0;
    for (let i = 0; i < n; i++) {
      const r = tests.insertOne(
        { test: label, seq: i, written_at: new Date() },
        { writeConcern: concern }
      );
      if (r.acknowledged) acknowledged++;
    }
    const ms = Date.now() - start;
    return {
      test: label,
      write_concern: concern,
      inserts: n,
      acknowledged: acknowledged,
      total_ms: ms,
      avg_ms_per_insert: Math.round((ms / n) * 10) / 10
    };
  };

  printjson(timed('w_1', { w: 1 }, 20));
  printjson(timed('w_majority', { w: 'majority', wtimeout: 5000 }, 20));
  printjson(timed('w_3_all_nodes', { w: 3, wtimeout: 5000 }, 20));

  try {
    tests.insertOne(
      { test: 'w_4_impossible', written_at: new Date() },
      { writeConcern: { w: 4, wtimeout: 5000 } }
    );
    print('w: 4 was accepted, which should not happen on a 3-node cluster');
  } catch (e) {
    printjson({
      test: 'w_4_impossible',
      outcome: 'error returned to the client',
      error: e.name,
      code: e.code,
      code_name: e.codeName,
      message: e.message
    });
  }
  print('w_4_impossible documents stored: ' + tests.countDocuments({ test: 'w_4_impossible' }));

  printjson(tests.aggregate([
    { $group: { _id: '$test', documents: { $sum: 1 } } },
    { $sort: { _id: 1 } }
  ]).toArray());
})();

// 3. Read preference tests
(function readPreferenceTests() {
  const vp = db.getSiblingDB('vanguardpay_nosql');
  const tests = vp.replication_tests;

  const nodeFor = (pref) => {
    const e = vp.fraud_alerts.find({ status: 'open' }).readPref(pref).explain('executionStats');
    const s = e.serverInfo || {};
    return s.host + ':' + s.port;
  };

  const answeredBy = {};
  ['primary', 'secondaryPreferred', 'secondary'].forEach((pref) => {
    answeredBy[pref] = nodeFor(pref);
  });
  printjson({
    primary_node: vp.hello().primary,
    answered_by: answeredBy,
    secondary_read_left_the_primary: answeredBy.secondary !== answeredBy.primary
  });

  const spread = {};
  for (let i = 0; i < 10; i++) {
    const node = nodeFor('secondaryPreferred');
    spread[node] = (spread[node] || 0) + 1;
  }
  printjson({ secondaryPreferred_10_reads: spread });

  const probes = 20;
  let missed = 0;
  for (let i = 0; i < probes; i++) {
    tests.insertOne({ test: 'stale_probe', probe: i }, { writeConcern: { w: 1 } });
    const seen = tests.find({ test: 'stale_probe', probe: i }).readPref('secondary').toArray().length;
    if (seen === 0) missed++;
  }
  printjson({ stale_probe: { writes: probes, immediate_secondary_reads_missing_the_write: missed } });

  tests.drop();
})();

// 4. Backup and restore check
(function backupRestoreCheck() {
  const vp = db.getSiblingDB('vanguardpay_nosql');

  const summary = (name) => ({
    collection: name,
    documents: vp[name].countDocuments(),
    created_at_stored_as_date: vp[name].countDocuments({ created_at: { $type: 'date' } }),
    by_rule_type: vp[name].aggregate([
      { $group: { _id: '$rule_type', alerts: { $sum: 1 } } },
      { $sort: { _id: 1 } }
    ]).toArray()
  });

  const original = summary('fraud_alerts');
  const restored = summary('fraud_alerts_restore_test');
  printjson(original);
  printjson(restored);
  print('Restored copy matches the original: ' +
        (JSON.stringify(original.by_rule_type) === JSON.stringify(restored.by_rule_type) &&
         original.documents === restored.documents &&
         original.created_at_stored_as_date === restored.created_at_stored_as_date));
})();
