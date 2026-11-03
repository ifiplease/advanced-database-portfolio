// Queries, aggregations and indexes for VanguardPay 

// 0. Session setup (run once per shell session)
db = db.getSiblingDB('vanguardpay_nosql');

function explainSummary(cursor) {
  const e = cursor.explain('executionStats');
  let stage = e.queryPlanner.winningPlan.queryPlan || e.queryPlanner.winningPlan;
  const path = [];
  let indexName = null;
  while (stage) {
    path.push(stage.stage);
    if (stage.indexName) indexName = stage.indexName;
    stage = stage.inputStage;
  }
  return {
    plan: path.join(' > '),
    index_used: indexName,
    docs_examined: e.executionStats.totalDocsExamined,
    keys_examined: e.executionStats.totalKeysExamined,
    docs_returned: e.executionStats.nReturned,
    execution_time_ms: e.executionStats.executionTimeMillis
  };
}

// 1. Create: insert one manual alert
db.fraud_alerts.insertOne({
  alert_id: 'FRD99001',
  customer_id: 2,
  account_id: 2,
  rule_type: 'manual_flag',
  severity: 'low',
  status: 'open',
  rule_payload: {
    raised_by: 'zainab.musa',
    reason: 'Customer reported a suspicious SMS',
    channel: 'support_call'
  },
  review_notes: [],
  created_at: new Date()
});

// 2. Update one
db.fraud_alerts.updateOne(
  { alert_id: 'FRD99001' },
  {
    $set: { status: 'under_review', severity: 'medium' },
    $push: {
      review_notes: {
        analyst: 'tunde.lawal',
        note: 'Customer forwarded the SMS, checking the sender.',
        noted_at: new Date()
      }
    }
  }
);

db.fraud_alerts.findOne(
  { alert_id: 'FRD99001' },
  { _id: 0, alert_id: 1, rule_type: 1, severity: 1, status: 1, review_notes: 1 }
);

// 3. Update many
db.fraud_alerts.updateMany(
  {
    status: 'open',
    severity: 'low',
    created_at: { $lt: new Date(Date.now() - 14 * 24 * 60 * 60 * 1000) }
  },
  {
    $set: { status: 'false_positive' },
    $currentDate: { resolved_at: true }
  }
);

// 4. Delete many
db.fraud_alerts.deleteMany({ rule_type: 'manual_flag' });
db.fraud_alerts.countDocuments();

// 5a. Nested query: successful mobile logins from outside Nigeria
db.login_sessions.find(
  { outcome: 'success', 'device.type': 'mobile', 'geo.country': { $ne: 'NG' } },
  { _id: 0, session_id: 1, customer_id: 1, 'device.model': 1, 'geo.city': 1, login_at: 1 }
).sort({ login_at: -1 }).limit(3);

// 5b. Nested query: alerts with a note by one analyst that mentions the customer
db.fraud_alerts.find(
  { review_notes: { $elemMatch: { analyst: 'ada.obi', note: /customer/i } } },
  { _id: 0, alert_id: 1, rule_type: 1, status: 1, review_notes: 1 }
).limit(2);

// 5c. Nested query: alerts whose payload has an implied speed field above 15,000 km/h
db.fraud_alerts.find(
  { 'rule_payload.implied_speed_kmh': { $exists: true, $gte: 15000 } },
  {
    _id: 0, alert_id: 1, account_id: 1,
    'rule_payload.from_city': 1, 'rule_payload.to_city': 1, 'rule_payload.implied_speed_kmh': 1
  }
).sort({ 'rule_payload.implied_speed_kmh': -1 }).limit(3);

// 6a. Aggregation: failed logins per country
db.login_sessions.aggregate([
  { $match: { outcome: 'failed' } },
  { $group: { _id: '$geo.country', failed_logins: { $sum: 1 } } },
  { $sort: { failed_logins: -1 } }
]);

// 6b. Aggregation: alerts by rule type and severity
db.fraud_alerts.aggregate([
  { $group: { _id: { rule_type: '$rule_type', severity: '$severity' }, alerts: { $sum: 1 } } },
  { $sort: { '_id.rule_type': 1, '_id.severity': 1 } }
]);

// 6c. Aggregation: transfer burst totals (cross-checked against pgAdmin)
db.fraud_alerts.aggregate([
  { $match: { rule_type: 'transfer_burst' } },
  {
    $group: {
      _id: '$rule_payload.currency',
      bursts: { $sum: 1 },
      transfers: { $sum: '$rule_payload.transfer_count' },
      total_amount: { $sum: '$rule_payload.total_amount' }
    }
  }
]);

// 6d. Aggregation: join an alert to its login sessions with $lookup
db.fraud_alerts.aggregate([
  { $match: { rule_type: 'impossible_travel', account_id: 1 } },
  {
    $lookup: {
      from: 'login_sessions',
      localField: 'session_ids',
      foreignField: 'session_id',
      as: 'sessions'
    }
  },
  {
    $project: {
      _id: 0, alert_id: 1, severity: 1,
      'sessions.session_id': 1, 'sessions.geo.city': 1,
      'sessions.device.model': 1, 'sessions.device.browser': 1, 'sessions.login_at': 1
    }
  }
]);

// 7. Explain before indexing
print('Sessions for one customer, newest first');
printjson(explainSummary(db.login_sessions.find({ customer_id: 120 }).sort({ login_at: -1 })));
print('Open high-severity alerts, newest first');
printjson(explainSummary(db.fraud_alerts.find({ status: 'open', severity: 'high' }).sort({ created_at: -1 })));

// 8. Create indexes
db.login_sessions.createIndex({ customer_id: 1, login_at: -1 }, { name: 'idx_sessions_customer_login_at' });
db.login_sessions.createIndex({ session_id: 1 }, { name: 'uq_sessions_session_id', unique: true });
db.login_sessions.createIndex({ expires_at: 1 }, { name: 'ttl_sessions_expires_at', expireAfterSeconds: 0 });
db.fraud_alerts.createIndex({ alert_id: 1 }, { name: 'uq_alerts_alert_id', unique: true });
db.fraud_alerts.createIndex(
  { severity: 1, created_at: -1 },
  { name: 'idx_alerts_open_severity_created', partialFilterExpression: { status: 'open' } }
);

db.login_sessions.getIndexes().map((i) => ({ name: i.name, key: i.key, unique: i.unique, ttl_seconds: i.expireAfterSeconds }));
db.fraud_alerts.getIndexes().map((i) => ({ name: i.name, key: i.key, unique: i.unique, partial: i.partialFilterExpression }));

// 9. Explain after indexing
print('Sessions for one customer, newest first');
printjson(explainSummary(db.login_sessions.find({ customer_id: 120 }).sort({ login_at: -1 })));
print('Open high-severity alerts, newest first');
printjson(explainSummary(db.fraud_alerts.find({ status: 'open', severity: 'high' }).sort({ created_at: -1 })));

// 10. TTL demonstration
(function ttlDemo() {
  db.login_sessions.insertOne({
    session_id: 'SES_TTL_TEST',
    customer_id: 4,
    outcome: 'success',
    login_at: new Date(Date.now() - 2 * 60 * 60 * 1000),
    expires_at: new Date(Date.now() - 60 * 1000)
  });
  print('Right after insert: ' + db.login_sessions.countDocuments({ session_id: 'SES_TTL_TEST' }));

  for (let waited = 15; waited <= 180; waited += 15) {
    sleep(15000);
    if (db.login_sessions.countDocuments({ session_id: 'SES_TTL_TEST' }) === 0) {
      print('Removed by the TTL index after about ' + waited + ' seconds');
      print('Total login_sessions now: ' + db.login_sessions.countDocuments());
      return;
    }
  }
  print('Still present after 180 seconds, run the count again in a minute');
})();
