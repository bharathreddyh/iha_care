-- ─────────────────────────────────────────────────────────────────────────────
-- Self-service sign-up: let a newly registered user create their own centre.
--
-- Run this ONCE in: Supabase Dashboard > SQL Editor > New Query.
-- Safe to re-run (uses CREATE OR REPLACE / IF NOT EXISTS).
--
-- The app's centres / centre_members tables have RLS enabled with SELECT-only
-- policies, so a client cannot INSERT into them directly. This SECURITY DEFINER
-- function runs with elevated rights and creates the centre + owner membership
-- atomically for whoever is currently signed in (auth.uid()).
-- ─────────────────────────────────────────────────────────────────────────────

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

  -- Normalise the code (trim + upper) so codes stay tidy and unique checks work.
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


-- ─────────────────────────────────────────────────────────────────────────────
-- Join an existing centre by its code. Adds the current user as 'staff'.
-- SECURITY DEFINER so it can look up a centre the user can't yet SELECT and
-- insert the membership past the SELECT-only RLS.
-- ─────────────────────────────────────────────────────────────────────────────

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


-- ─────────────────────────────────────────────────────────────────────────────
-- List everyone in a centre (email + role). Any member of the centre may call
-- it. SECURITY DEFINER because centre_members RLS only exposes the caller's own
-- row and auth.users is not client-readable.
-- ─────────────────────────────────────────────────────────────────────────────

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
