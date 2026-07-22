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
