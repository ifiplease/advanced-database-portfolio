// Seed documents for VanguardPay (run in the Compass mongosh tab)

(function seedVanguardPay() {

  // 1. Burst summaries pasted from pgAdmin
  const burstData = [{"account_id":1,"transfer_count":20,"total_amount":3240000.00,"first_transfer_at":"2026-10-09T00:34:03+01:00","last_transfer_at":"2026-10-09T01:31:03+01:00"}, {"account_id":2,"transfer_count":20,"total_amount":3304000.00,"first_transfer_at":"2026-10-10T00:34:03+01:00","last_transfer_at":"2026-10-10T01:31:03+01:00"}, {"account_id":3,"transfer_count":20,"total_amount":3346000.00,"first_transfer_at":"2026-10-11T00:34:03+01:00","last_transfer_at":"2026-10-11T01:31:03+01:00"}, {"account_id":4,"transfer_count":20,"total_amount":3035000.00,"first_transfer_at":"2026-10-12T00:34:03+01:00","last_transfer_at":"2026-10-12T01:31:03+01:00"}, {"account_id":5,"transfer_count":20,"total_amount":3151000.00,"first_transfer_at":"2026-10-13T00:34:03+01:00","last_transfer_at":"2026-10-13T01:31:03+01:00"}, {"account_id":6,"transfer_count":20,"total_amount":3508000.00,"first_transfer_at":"2026-10-14T00:34:03+01:00","last_transfer_at":"2026-10-14T01:31:03+01:00"}, {"account_id":7,"transfer_count":20,"total_amount":3900000.00,"first_transfer_at":"2026-10-15T00:34:03+01:00","last_transfer_at":"2026-10-15T01:31:03+01:00"}, {"account_id":8,"transfer_count":20,"total_amount":3452000.00,"first_transfer_at":"2026-10-16T00:34:03+01:00","last_transfer_at":"2026-10-16T01:31:03+01:00"}, {"account_id":9,"transfer_count":20,"total_amount":3435000.00,"first_transfer_at":"2026-10-17T00:34:03+01:00","last_transfer_at":"2026-10-17T01:31:03+01:00"}, {"account_id":10,"transfer_count":20,"total_amount":3611000.00,"first_transfer_at":"2026-10-18T00:34:03+01:00","last_transfer_at":"2026-10-18T01:31:03+01:00"}];

  // 2. Helpers
  const vp = db.getSiblingDB('vanguardpay_nosql');
  const now = new Date();
  const MIN = 60 * 1000;
  const HOUR = 60 * MIN;
  const DAY = 24 * HOUR;
  const ago = (ms) => new Date(now.getTime() - ms);
  const randInt = (lo, hi) => lo + Math.floor(Math.random() * (hi - lo + 1));
  const pick = (list) => list[randInt(0, list.length - 1)];
  const pad = (n, width) => String(n).padStart(width, '0');
  const hex = (len) => Array.from({ length: len }, () => '0123456789abcdef'[randInt(0, 15)]).join('');

  // 3. Places and IP addresses
  const lagos = { country: 'NG', city: 'Lagos', lat: 6.5244, lon: 3.3792 };
  const abuja = { country: 'NG', city: 'Abuja', lat: 9.0765, lon: 7.3986 };
  const portHarcourt = { country: 'NG', city: 'Port Harcourt', lat: 4.8156, lon: 7.0498 };
  const ibadan = { country: 'NG', city: 'Ibadan', lat: 7.3775, lon: 3.9470 };
  const kano = { country: 'NG', city: 'Kano', lat: 12.0022, lon: 8.5920 };
  const enugu = { country: 'NG', city: 'Enugu', lat: 6.4584, lon: 7.5464 };
  const london = { country: 'GB', city: 'London', lat: 51.5072, lon: -0.1276 };
  const accra = { country: 'GH', city: 'Accra', lat: 5.6037, lon: -0.1870 };
  const dubai = { country: 'AE', city: 'Dubai', lat: 25.2048, lon: 55.2708 };

  const nigeriaPlaces = [lagos, lagos, lagos, abuja, abuja, portHarcourt, ibadan, kano, enugu];
  const foreignPlaces = [london, accra, dubai];
  const ipPrefixes = {
    NG: ['102.89', '105.112', '197.210'],
    GB: ['81.2'],
    GH: ['154.160'],
    AE: ['94.200']
  };
  const ipFor = (country) =>
    pick(ipPrefixes[country]) + '.' + randInt(0, 255) + '.' + randInt(1, 254);

  // 4. Devices
  const mobileModels = [
    { os: 'Android', os_version: '14', model: 'Samsung Galaxy A54' },
    { os: 'Android', os_version: '13', model: 'Tecno Spark 10' },
    { os: 'Android', os_version: '12', model: 'Infinix Hot 30' },
    { os: 'iOS', os_version: '17.4', model: 'iPhone 13' },
    { os: 'iOS', os_version: '17.2', model: 'iPhone 11' }
  ];
  const webProfiles = [
    { os: 'Windows 11', browser: 'Chrome', browser_version: '126' },
    { os: 'Windows 10', browser: 'Edge', browser_version: '125' },
    { os: 'macOS 14', browser: 'Safari', browser_version: '17' },
    { os: 'Ubuntu 22.04', browser: 'Firefox', browser_version: '127' }
  ];

  const makeDevice = () => Math.random() < 0.7
    ? { type: 'mobile', device_id: 'DEV-' + hex(8), ...pick(mobileModels),
        app_version: pick(['4.8.1', '4.9.0', '5.0.2']) }
    : { type: 'web', device_id: 'DEV-' + hex(8), ...pick(webProfiles) };

  const customerDevices = {};
  const devicesOf = (customerId) => {
    if (!customerDevices[customerId]) {
      customerDevices[customerId] = [makeDevice(), makeDevice()];
    }
    return customerDevices[customerId];
  };

  // 5. Session builder
  let sessionSeq = 0;
  const makeSession = (customerId, loginAt, o) => {
    const outcome = o.outcome || 'success';
    const doc = {
      session_id: 'SES' + pad(++sessionSeq, 6),
      customer_id: customerId,
      ip_address: o.ip || ipFor(o.place.country),
      device: o.device,
      geo: {
        country: o.place.country,
        city: o.place.city,
        latitude: o.place.lat,
        longitude: o.place.lon
      },
      outcome: outcome,
      login_at: loginAt,
      expires_at: new Date(loginAt.getTime() + 90 * DAY)
    };
    if (outcome === 'success') {
      doc.session_token_hash = hex(64);
    } else {
      doc.failure_reason = o.reason || (outcome === 'failed'
        ? pick(['wrong_password', 'otp_expired', 'otp_invalid'])
        : pick(['device_blocked', 'ip_blocklisted']));
    }
    return doc;
  };

  // 6. Alert builder
  let alertSeq = 0;
  const analysts = ['ada.obi', 'tunde.lawal', 'zainab.musa'];
  const noteTexts = [
    'Called the customer, login not recognised.',
    'Customer confirmed the activity, travel was genuine.',
    'Device blocked pending identity verification.',
    'Escalated to compliance for account freeze review.',
    'No further suspicious activity after the alert.'
  ];
  const makeAlert = (a) => {
    let notes = a.review_notes;
    if (!notes) {
      notes = [];
      if (a.status !== 'open') {
        const noteCount = a.status === 'under_review' ? 1 : randInt(1, 2);
        for (let k = 0; k < noteCount; k++) {
          notes.push({
            analyst: pick(analysts),
            note: pick(noteTexts),
            noted_at: new Date(a.created_at.getTime() + (k + 1) * 30 * MIN)
          });
        }
      }
    }
    const doc = {
      alert_id: 'FRD' + pad(++alertSeq, 5),
      customer_id: a.customer_id,
      account_id: a.account_id,
      rule_type: a.rule_type,
      severity: a.severity,
      status: a.status,
      rule_payload: a.rule_payload,
      review_notes: notes,
      created_at: a.created_at
    };
    if (a.session_ids) doc.session_ids = a.session_ids;
    if (a.status === 'confirmed_fraud' || a.status === 'false_positive') {
      doc.resolved_at = new Date(a.created_at.getTime() + DAY);
    }
    return doc;
  };

  // 7. Planted sessions for test accounts A, B and C
  const aPhone = { type: 'mobile', device_id: 'DEV-A54F2B91', os: 'Android', os_version: '14',
                   model: 'Samsung Galaxy A54', app_version: '5.0.2' };
  const aLaptop = { type: 'web', device_id: 'DEV-7E6D5C4B', os: 'Windows 11',
                    browser: 'Chrome', browser_version: '126' };
  const bPhone = { type: 'mobile', device_id: 'DEV-13AB45CD', os: 'iOS', os_version: '17.4',
                   model: 'iPhone 13', app_version: '5.0.2' };
  const bNewPhone = { type: 'mobile', device_id: 'DEV-9F8E7D6C', os: 'Android', os_version: '13',
                      model: 'Tecno Spark 10', app_version: '4.9.0' };
  const cPhone = { type: 'mobile', device_id: 'DEV-30C7E1F2', os: 'Android', os_version: '12',
                   model: 'Infinix Hot 30', app_version: '4.9.0' };

  const sessions = [];

  const a1 = makeSession(1, ago(1 * DAY), { place: lagos, device: aPhone, ip: '102.89.45.120' });
  const a2 = makeSession(1, new Date(a1.login_at.getTime() + 20 * MIN),
                         { place: london, device: aLaptop, ip: '81.2.69.142' });
  sessions.push(a1, a2);

  [5, 3, 2].forEach((days) => {
    sessions.push(makeSession(2, ago(days * DAY), { place: lagos, device: bPhone, ip: '105.112.20.8' }));
  });
  const bNew = makeSession(2, ago(6 * HOUR), { place: abuja, device: bNewPhone, ip: '197.210.77.31' });
  sessions.push(bNew);

  const cStart = ago(3 * DAY);
  for (let k = 0; k < 5; k++) {
    sessions.push(makeSession(3, new Date(cStart.getTime() + k * MIN), {
      place: lagos, device: cPhone, ip: '102.89.34.21', outcome: 'failed', reason: 'wrong_password'
    }));
  }
  const cSuccess = makeSession(3, new Date(cStart.getTime() + 6 * MIN),
                               { place: lagos, device: cPhone, ip: '102.89.34.21' });
  sessions.push(cSuccess);

  // 8. Random sessions for customers 4 to 500
  while (sessions.length < 3000) {
    const customerId = randInt(4, 500);
    const r = Math.random();
    const outcome = r < 0.85 ? 'success' : r < 0.97 ? 'failed' : 'blocked';
    const place = Math.random() < 0.05 ? pick(foreignPlaces) : pick(nigeriaPlaces);
    const device = Math.random() < 0.85 ? devicesOf(customerId)[0] : devicesOf(customerId)[1];
    sessions.push(makeSession(customerId, ago(Math.random() * 30 * DAY),
                              { outcome: outcome, place: place, device: device }));
  }

  // 9. Planted alerts for test accounts A, B and C
  const alerts = [];

  alerts.push(makeAlert({
    customer_id: 1, account_id: 1,
    rule_type: 'impossible_travel', severity: 'critical', status: 'open',
    created_at: new Date(a2.login_at.getTime() + 2 * MIN),
    session_ids: [a1.session_id, a2.session_id],
    rule_payload: {
      from_city: 'Lagos', to_city: 'London', distance_km: 5020, minutes_between: 20,
      implied_speed_kmh: Math.round(5020 / (20 / 60)), max_allowed_kmh: 900
    }
  }));

  alerts.push(makeAlert({
    customer_id: 2, account_id: 2,
    rule_type: 'device_mismatch', severity: 'medium', status: 'under_review',
    created_at: new Date(bNew.login_at.getTime() + 1 * MIN),
    session_ids: [bNew.session_id],
    rule_payload: {
      known_device_id: bPhone.device_id, known_device_model: bPhone.model,
      seen_device_id: bNewPhone.device_id, seen_device_model: bNewPhone.model,
      known_device_logins: 3, new_device_first_seen: true
    },
    review_notes: [{
      analyst: 'ada.obi',
      note: 'Customer contacted, awaiting confirmation of the new phone.',
      noted_at: new Date(bNew.login_at.getTime() + 30 * MIN)
    }]
  }));

  alerts.push(makeAlert({
    customer_id: 3, account_id: 3,
    rule_type: 'failed_login_streak', severity: 'medium', status: 'open',
    created_at: new Date(cSuccess.login_at.getTime() + 1 * MIN),
    session_ids: sessions
      .filter((s) => s.customer_id === 3)
      .map((s) => s.session_id),
    rule_payload: {
      failed_attempts: 5, window_minutes: 6, ended_in: 'success',
      ip_address: '102.89.34.21', ip_address_changed: false
    }
  }));

  // 10. Transfer burst alerts from the pgAdmin results (accounts 1 to 10)
  burstData.forEach((b, i) => {
    const first = new Date(b.first_transfer_at);
    const last = new Date(b.last_transfer_at);
    alerts.push(makeAlert({
      customer_id: b.account_id, account_id: b.account_id,
      rule_type: 'transfer_burst', severity: 'high',
      status: i < 5 ? 'open' : i < 8 ? 'under_review' : 'confirmed_fraud',
      created_at: new Date(last.getTime() + 5 * MIN),
      rule_payload: {
        transfer_count: b.transfer_count,
        total_amount: b.total_amount,
        currency: 'NGN',
        min_amount: 50000,
        first_transfer_at: first,
        last_transfer_at: last,
        window_minutes: Math.round((last - first) / MIN)
      }
    }));
  });

  // 11. Random alerts for customers 4 to 500
  const eligible = sessions.filter(
    (s) => s.outcome === 'success' && s.customer_id > 3 && s.login_at < ago(3 * DAY)
  );
  const randomTypes = ['impossible_travel', 'device_mismatch', 'failed_login_streak'];

  for (let i = 0; i < 140; i++) {
    const s = pick(eligible);
    const ruleType = pick(randomTypes);
    let payload;
    let severity;

    if (ruleType === 'impossible_travel') {
      const minutes = randInt(10, 90);
      const km = randInt(3000, 6000);
      payload = {
        from_city: pick(nigeriaPlaces).city, to_city: pick(foreignPlaces).city,
        distance_km: km, minutes_between: minutes,
        implied_speed_kmh: Math.round(km / (minutes / 60)), max_allowed_kmh: 900
      };
      severity = pick(['high', 'critical']);
    } else if (ruleType === 'device_mismatch') {
      payload = {
        known_device_id: 'DEV-' + hex(8), seen_device_id: s.device.device_id,
        seen_device_type: s.device.type, new_device_first_seen: true
      };
      severity = pick(['low', 'medium']);
    } else {
      payload = {
        failed_attempts: randInt(4, 9), window_minutes: randInt(3, 15),
        ended_in: pick(['success', 'lockout']), ip_address: s.ip_address
      };
      severity = pick(['medium', 'high']);
    }

    const r = Math.random();
    alerts.push(makeAlert({
      customer_id: s.customer_id, account_id: s.customer_id,
      rule_type: ruleType, severity: severity,
      status: r < 0.5 ? 'open' : r < 0.75 ? 'under_review' : r < 0.85 ? 'confirmed_fraud' : 'false_positive',
      created_at: new Date(s.login_at.getTime() + randInt(1, 30) * MIN),
      session_ids: [s.session_id],
      rule_payload: payload
    }));
  }

  // 12. Reload both collections
  vp.login_sessions.drop();
  vp.fraud_alerts.drop();
  vp.login_sessions.insertMany(sessions);
  vp.fraud_alerts.insertMany(alerts);

  // 13. Counts
  print('login_sessions: ' + vp.login_sessions.countDocuments());
  print('fraud_alerts: ' + vp.fraud_alerts.countDocuments());
  printjson(vp.fraud_alerts.aggregate([
    { $group: { _id: '$rule_type', alerts: { $sum: 1 } } },
    { $sort: { _id: 1 } }
  ]).toArray());

})();
