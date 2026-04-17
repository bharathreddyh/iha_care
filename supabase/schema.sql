-- ============================================================
-- IHA Care — Supabase Schema
-- Run this in Supabase Dashboard > SQL Editor
-- ============================================================

-- 1. Centres
CREATE TABLE centres (
  id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  code TEXT UNIQUE NOT NULL,   -- e.g. 'centre_1', 'main_branch'
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Centre membership (which user belongs to which centre)
CREATE TABLE centre_members (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  centre_id UUID REFERENCES centres(id)    ON DELETE CASCADE,
  role      TEXT NOT NULL DEFAULT 'staff',  -- 'staff' or 'owner'
  UNIQUE(user_id, centre_id)
);

-- 3. Device sessions (tracks active logins)
CREATE TABLE device_sessions (
  id          TEXT PRIMARY KEY,  -- device UUID generated on device
  user_id     UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  centre_id   UUID REFERENCES centres(id),
  device_name TEXT,
  last_seen   TIMESTAMPTZ DEFAULT now(),
  is_active   BOOLEAN DEFAULT true
);

-- 4. Scan types (global, shared across all centres)
CREATE TABLE scan_types (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  price      REAL NOT NULL,
  category   TEXT NOT NULL,
  modality   TEXT NOT NULL DEFAULT 'US',
  is_active  BOOLEAN DEFAULT true,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 5. Bills (per centre)
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

-- 6. Referral doctors (per centre)
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

-- 7. Doctor scan incentives (per centre)
CREATE TABLE doctor_scan_incentives (
  id            TEXT PRIMARY KEY,
  centre_id     UUID REFERENCES centres(id),
  doctor_id     TEXT NOT NULL,
  scan_type_id  TEXT NOT NULL,
  rate          REAL NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ DEFAULT now(),
  UNIQUE(doctor_id, scan_type_id)
);

-- 8. Incentive ledger (per centre)
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

-- ============================================================
-- Row Level Security
-- ============================================================

ALTER TABLE centres              ENABLE ROW LEVEL SECURITY;
ALTER TABLE centre_members       ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_sessions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE scan_types           ENABLE ROW LEVEL SECURITY;
ALTER TABLE bills                ENABLE ROW LEVEL SECURITY;
ALTER TABLE referral_doctors     ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctor_scan_incentives ENABLE ROW LEVEL SECURITY;
ALTER TABLE incentive_ledger     ENABLE ROW LEVEL SECURITY;

-- Centres: users can see centres they belong to
CREATE POLICY "see own centres" ON centres
  FOR SELECT USING (
    id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid())
  );

-- Centre members: users see their own memberships
CREATE POLICY "see own memberships" ON centre_members
  FOR SELECT USING (user_id = auth.uid());

-- Device sessions: users manage their own sessions
CREATE POLICY "manage own sessions" ON device_sessions
  FOR ALL USING (user_id = auth.uid());

-- Scan types: all authenticated users can read and write
CREATE POLICY "all can read scan types" ON scan_types
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "all can write scan types" ON scan_types
  FOR ALL TO authenticated USING (true);

-- Bills: per-centre access
CREATE POLICY "centre bills access" ON bills
  FOR ALL USING (
    centre_id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid())
  );

-- Referral doctors: per-centre access
CREATE POLICY "centre doctors access" ON referral_doctors
  FOR ALL USING (
    centre_id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid())
  );

-- Doctor scan incentives: per-centre access
CREATE POLICY "centre incentives access" ON doctor_scan_incentives
  FOR ALL USING (
    centre_id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid())
  );

-- Incentive ledger: per-centre access
CREATE POLICY "centre ledger access" ON incentive_ledger
  FOR ALL USING (
    centre_id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid())
  );

-- ============================================================
-- Updated_at trigger (auto-updates updated_at on any change)
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER t_bills_updated_at
  BEFORE UPDATE ON bills
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER t_referral_doctors_updated_at
  BEFORE UPDATE ON referral_doctors
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER t_scan_types_updated_at
  BEFORE UPDATE ON scan_types
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER t_doctor_scan_incentives_updated_at
  BEFORE UPDATE ON doctor_scan_incentives
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER t_incentive_ledger_updated_at
  BEFORE UPDATE ON incentive_ledger
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
