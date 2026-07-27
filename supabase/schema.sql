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

-- ── Inventory ─────────────────────────────────────────────────────────────────

CREATE TABLE inventory_items (
  id               TEXT        PRIMARY KEY,
  centre_id        UUID        NOT NULL REFERENCES centres(id),
  name             TEXT        NOT NULL,
  unit             TEXT        NOT NULL DEFAULT 'pcs',
  current_quantity REAL        NOT NULL DEFAULT 0,
  min_quantity     REAL        NOT NULL DEFAULT 0,
  price_per_unit   REAL,
  is_active        BOOLEAN     NOT NULL DEFAULT true,
  updated_at       TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE inventory_scan_usage (
  id           TEXT PRIMARY KEY,
  centre_id    UUID NOT NULL REFERENCES centres(id),
  scan_type_id TEXT NOT NULL,
  item_id      TEXT NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
  quantity     REAL NOT NULL DEFAULT 1,
  updated_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE(centre_id, scan_type_id, item_id)
);

CREATE TABLE inventory_transactions (
  id         TEXT        PRIMARY KEY,
  centre_id  UUID        NOT NULL REFERENCES centres(id),
  item_id    TEXT        NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
  type       TEXT        NOT NULL,
  quantity   REAL        NOT NULL,
  bill_id    TEXT,
  cost       REAL,
  notes      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- RLS
ALTER TABLE inventory_items         ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_scan_usage    ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_transactions  ENABLE ROW LEVEL SECURITY;

CREATE POLICY inv_items_centre ON inventory_items
  USING (centre_id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid()));
CREATE POLICY inv_usage_centre ON inventory_scan_usage
  USING (centre_id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid()));
CREATE POLICY inv_txn_centre ON inventory_transactions
  USING (centre_id IN (SELECT centre_id FROM centre_members WHERE user_id = auth.uid()));

CREATE TRIGGER t_inv_items_upd BEFORE UPDATE ON inventory_items         FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER t_inv_usage_upd BEFORE UPDATE ON inventory_scan_usage    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER t_inv_txn_upd   BEFORE UPDATE ON inventory_transactions  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── Migration: cancel support + later-added bill columns ──────────────────────
-- Safe to re-run; uses IF NOT EXISTS.

ALTER TABLE bills ADD COLUMN IF NOT EXISTS amount_paid    REAL;
ALTER TABLE bills ADD COLUMN IF NOT EXISTS report_created BOOLEAN DEFAULT false;
ALTER TABLE bills ADD COLUMN IF NOT EXISTS dispatched     BOOLEAN DEFAULT false;
ALTER TABLE bills ADD COLUMN IF NOT EXISTS cancelled_at   TIMESTAMPTZ;
ALTER TABLE bills ADD COLUMN IF NOT EXISTS cancel_reason    TEXT;
ALTER TABLE bills ADD COLUMN IF NOT EXISTS report_excluded  BOOLEAN DEFAULT false;

-- ── Self-service sign-up ──────────────────────────────────────────────────────
-- Lets a newly registered user create their own centre + owner membership.
-- SECURITY DEFINER so it can insert past the SELECT-only RLS on these tables.

CREATE OR REPLACE FUNCTION public.create_centre_for_current_user(
  p_name text,
  p_code text
)
RETURNS TABLE (id uuid, name text, code text, role text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_centre_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  p_code := upper(trim(p_code));
  p_name := trim(p_name);

  IF p_name = '' OR p_code = '' THEN
    RAISE EXCEPTION 'Centre name and code are required';
  END IF;

  IF EXISTS (SELECT 1 FROM centres c WHERE c.code = p_code) THEN
    RAISE EXCEPTION 'CENTRE_CODE_TAKEN';
  END IF;

  INSERT INTO centres (name, code)
  VALUES (p_name, p_code)
  RETURNING centres.id INTO v_centre_id;

  INSERT INTO centre_members (user_id, centre_id, role)
  VALUES (auth.uid(), v_centre_id, 'owner');

  RETURN QUERY
    SELECT c.id, c.name, c.code, 'owner'::text
    FROM centres c
    WHERE c.id = v_centre_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_centre_for_current_user(text, text) TO authenticated;

-- Join an existing centre by its code (adds current user as 'staff').
CREATE OR REPLACE FUNCTION public.join_centre_by_code(p_code text)
RETURNS TABLE (id uuid, name text, code text, role text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_centre centres%ROWTYPE;
  v_role   text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  p_code := upper(trim(p_code));
  IF p_code = '' THEN
    RAISE EXCEPTION 'Centre code is required';
  END IF;

  SELECT * INTO v_centre FROM centres c WHERE c.code = p_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CENTRE_NOT_FOUND';
  END IF;

  INSERT INTO centre_members (user_id, centre_id, role)
  VALUES (auth.uid(), v_centre.id, 'staff')
  ON CONFLICT (user_id, centre_id) DO NOTHING;

  SELECT cm.role INTO v_role
  FROM centre_members cm
  WHERE cm.user_id = auth.uid() AND cm.centre_id = v_centre.id;

  RETURN QUERY SELECT v_centre.id, v_centre.name, v_centre.code, v_role;
END;
$$;

GRANT EXECUTE ON FUNCTION public.join_centre_by_code(text) TO authenticated;

-- List everyone in a centre (email + role); any member may call it.
CREATE OR REPLACE FUNCTION public.list_centre_members(p_centre_id uuid)
RETURNS TABLE (user_id uuid, email text, role text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM centre_members cm
    WHERE cm.centre_id = p_centre_id AND cm.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'NOT_A_MEMBER';
  END IF;

  RETURN QUERY
    SELECT cm.user_id, u.email::text, cm.role
    FROM centre_members cm
    JOIN auth.users u ON u.id = cm.user_id
    WHERE cm.centre_id = p_centre_id
    ORDER BY (cm.role = 'owner') DESC, u.email;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_centre_members(uuid) TO authenticated;
