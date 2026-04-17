-- IHA Care Supabase Schema
-- Run in: Supabase Dashboard > SQL Editor > New Query

-- Centres
CREATE TABLE centres (
  id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  code TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Centre membership
CREATE TABLE centre_members (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  centre_id UUID REFERENCES centres(id)    ON DELETE CASCADE,
  role      TEXT NOT NULL DEFAULT 'staff',
  UNIQUE(user_id, centre_id)
);

-- Device sessions
CREATE TABLE device_sessions (
  id          TEXT PRIMARY KEY,
  user_id     UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  centre_id   UUID REFERENCES centres(id),
  device_name TEXT,
  last_seen   TIMESTAMPTZ DEFAULT now(),
  is_active   BOOLEAN DEFAULT true
);

-- Scan types (global, shared across centres)
CREATE TABLE scan_types (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  price      REAL NOT NULL,
  category   TEXT NOT NULL,
  modality   TEXT NOT NULL DEFAULT 'US',
  is_active  BOOLEAN DEFAULT true,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Bills (per centre)
CREATE TABLE bills (
  id                 TEXT PRIMARY KEY,
  centre_id          UUID REFERENCES centres(id),
  patient_name       TEXT NOT NULL,
  patient_id         TEXT,
  patient_dob        TEXT,
  patient_sex        TEXT,
  patient_phone      TEXT,
  scan_type_id       TEXT,
  referral_doctor_id TEXT,
  scan_fee           REAL NOT NULL,
  discount           REAL NOT NULL DEFAULT 0,
  final_amount       REAL NOT NULL,
  payment_mode       TEXT NOT NULL,
  status             TEXT NOT NULL DEFAULT 'paid',
  accession_number   TEXT,
  worklist_pushed    BOOLEAN DEFAULT false,
  scan_completed     BOOLEAN DEFAULT false,
  notes              TEXT,
  created_at         TEXT NOT NULL,
  updated_at         TIMESTAMPTZ DEFAULT now()
);

-- Referral doctors (per centre)
CREATE TABLE referral_doctors (
  id          TEXT PRIMARY KEY,
  centre_id   UUID REFERENCES centres(id),
  name        TEXT NOT NULL,
  phone       TEXT,
  clinic_name TEXT,
  specialty   TEXT,
  is_active   BOOLEAN DEFAULT true,
  updated_at  TIMESTAMPTZ DEFAULT now()
);

-- Doctor scan incentives (per centre)
CREATE TABLE doctor_scan_incentives (
  id            TEXT PRIMARY KEY,
  centre_id     UUID REFERENCES centres(id),
  doctor_id     TEXT NOT NULL,
  scan_type_id  TEXT NOT NULL,
  rate          REAL NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ DEFAULT now(),
  UNIQUE(doctor_id, scan_type_id)
);

-- Incentive ledger (per centre)
CREATE TABLE incentive_ledger (
  id                 TEXT PRIMARY KEY,
  centre_id          UUID REFERENCES centres(id),
  referral_doctor_id TEXT NOT NULL,
  month              TEXT NOT NULL,
  referral_count     INTEGER NOT NULL DEFAULT 0,
  total_billed       REAL NOT NULL DEFAULT 0,
  incentive_amount   REAL NOT NULL DEFAULT 0,
  payment_status     TEXT NOT NULL DEFAULT 'unpaid',
  paid_date          TEXT,
  updated_at         TIMESTAMPTZ DEFAULT now()
);

-- Row Level Security
ALTER TABLE centres                ENABLE ROW LEVEL SECURITY;
ALTER TABLE centre_members         ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_sessions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE scan_types             ENABLE ROW LEVEL SECURITY;
ALTER TABLE bills                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE referral_doctors       ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctor_scan_incentives ENABLE ROW LEVEL SECURITY;
ALTER TABLE incentive_ledger       ENABLE ROW LEVEL SECURITY;

-- Centres: see only your own
CREATE POLICY "see own centres" ON centres
  FOR SELECT USING (
    id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid())
  );

-- Centre members: see your own rows
CREATE POLICY "see own memberships" ON centre_members
  FOR SELECT USING (user_id = auth.uid());

-- Device sessions: manage your own
CREATE POLICY "manage own sessions" ON device_sessions
  FOR ALL USING (user_id = auth.uid());

-- Scan types: all authenticated users can read and write
CREATE POLICY "read scan types" ON scan_types
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "write scan types" ON scan_types
  FOR ALL TO authenticated USING (true);

-- Bills: per-centre
CREATE POLICY "centre bills" ON bills
  FOR ALL USING (
    centre_id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid())
  );

-- Referral doctors: per-centre
CREATE POLICY "centre doctors" ON referral_doctors
  FOR ALL USING (
    centre_id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid())
  );

-- Doctor scan incentives: per-centre
CREATE POLICY "centre incentive rates" ON doctor_scan_incentives
  FOR ALL USING (
    centre_id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid())
  );

-- Incentive ledger: per-centre
CREATE POLICY "centre ledger" ON incentive_ledger
  FOR ALL USING (
    centre_id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid())
  );

-- Auto-update updated_at on changes
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER t_bills_upd          BEFORE UPDATE ON bills                  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER t_doctors_upd        BEFORE UPDATE ON referral_doctors        FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER t_scan_types_upd     BEFORE UPDATE ON scan_types              FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER t_incentives_upd     BEFORE UPDATE ON doctor_scan_incentives  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER t_ledger_upd         BEFORE UPDATE ON incentive_ledger        FOR EACH ROW EXECUTE FUNCTION update_updated_at();
