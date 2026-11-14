-- RECOVERY-ONLY compatibility repair for migration #34.
-- NOT historical SQL. NOT an active migration. NOT deployable without a separate review.
-- Apply only after all 38 migrations in a fresh disposable local Supabase stack.
-- Keeps the existing RPC signature and transactional behavior while aligning department
-- allowlists and permission validation with the owner-approved seven-department model.

CREATE OR REPLACE FUNCTION private.manage_nexora_officer(
  p_email text,
  p_action text,
  p_department_key text DEFAULT NULL,
  p_position_key text DEFAULT NULL,
  p_permissions jsonb DEFAULT '[]'::jsonb,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_actor_code text;
  v_target uuid;
  v_staff public.admin_staff%ROWTYPE;
  v_code text;
  v_permission text;
  v_permissions text[] := ARRAY[]::text[];
  v_sensitive boolean := false;
  v_permission_sensitive boolean;
  v_reports_to uuid;
  v_details jsonb;
  v_email text := lower(trim(coalesce(p_email,''));
BEGIN
  IF v_actor IS NULL
     OR (SELECT auth.jwt()->>'aal') IS DISTINCT FROM 'aal2'
     OR NOT private.is_nexora_super_admin() THEN
    RAISE EXCEPTION 'শুধু MFA-যাচাইকৃত Director এই কাজ করতে পারবেন।'
      USING errcode='42501';
  END IF;

  IF p_action IS NULL OR p_action NOT IN ('create','update','deactivate') THEN
    RAISE EXCEPTION 'অবৈধ action।' USING errcode='22023';
  END IF;
  IF v_email !~* '^[A-Z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' THEN
    RAISE EXCEPTION 'সঠিক ইমেইল দিন।' USING errcode='22023';
  END IF;

  SELECT admin_code INTO v_actor_code
  FROM public.admin_staff
  WHERE user_id=v_actor AND admin_level='super_admin' AND is_active=true
    AND position_key='director';

  SELECT id INTO v_target
  FROM auth.users
  WHERE lower(email)=v_email
  LIMIT 1;

  IF v_target IS NULL THEN
    RAISE EXCEPTION 'এই ইমেইলে Auth account পাওয়া যায়নি। প্রথমে নিরাপদ Invite পাঠাতে হবে।'
      USING errcode='P0002';
  END IF;
  IF v_target=v_actor THEN
    RAISE EXCEPTION 'Director নিজের অ্যাকাউন্টকে কর্মকর্তা হিসেবে পরিবর্তন করতে পারবেন না।'
      USING errcode='42501';
  END IF;

  IF p_action IN ('create','update') THEN
    IF p_position_key NOT IN ('managing_director','department_head','department_officer') THEN
      RAISE EXCEPTION 'সঠিক পদ নির্বাচন করুন।' USING errcode='22023';
    END IF;
    IF p_position_key='managing_director' THEN
      IF p_department_key IS DISTINCT FROM 'managing_director' THEN
        RAISE EXCEPTION 'MD-কে Managing Director Office-এ নিয়োগ করতে হবে।' USING errcode='22023';
      END IF;
    ELSIF p_department_key NOT IN (
      'marketing','transport','logistics','product_business','trust_safety','accounts'
    ) THEN
      RAISE EXCEPTION 'নির্বাচিত পদে অনুমোদিত operational department নির্বাচন করুন।'
        USING errcode='22023';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.admin_departments
      WHERE department_key=p_department_key AND is_assignable=true
    ) THEN
      RAISE EXCEPTION 'নির্বাচিত বিভাগ সক্রিয় বা assignable নয়।' USING errcode='22023';
    END IF;
    IF jsonb_typeof(coalesce(p_permissions,'[]'::jsonb)) IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'Permission তালিকা array হতে হবে।' USING errcode='22023';
    END IF;

    FOR v_permission IN
      SELECT DISTINCT jsonb_array_elements_text(coalesce(p_permissions,'[]'::jsonb))
    LOOP
      SELECT c.is_sensitive INTO v_permission_sensitive
      FROM public.admin_permission_catalog AS c
      WHERE c.permission_key=v_permission
        AND c.is_active=true
        AND (p_position_key='managing_director' OR c.department_key=p_department_key);
      IF NOT FOUND THEN
        RAISE EXCEPTION 'এই পদ ও বিভাগের জন্য সক্রিয় Permission বৈধ নয়: %',v_permission
          USING errcode='22023';
      END IF;
      v_sensitive := v_sensitive OR coalesce(v_permission_sensitive,false);
      v_permissions := array_append(v_permissions,v_permission);
    END LOOP;

    IF v_sensitive AND length(btrim(coalesce(p_reason,'')))<5 THEN
      RAISE EXCEPTION 'সংবেদনশীল Permission দেওয়ার কারণ অন্তত ৫ অক্ষরে লিখুন।'
        USING errcode='22023';
    END IF;
  END IF;

  SELECT * INTO v_staff
  FROM public.admin_staff
  WHERE user_id=v_target
  FOR UPDATE;

  IF p_action='create' THEN
    IF FOUND THEN
      RAISE EXCEPTION 'এই অ্যাকাউন্টে Admin record আগে থেকেই আছে; Update ব্যবহার করুন।'
        USING errcode='23505';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id=v_target AND role='buyer' AND account_status='active'
    ) THEN
      RAISE EXCEPTION 'নতুন Invite account-এর সক্রিয় Buyer profile তৈরি হয়নি; নিয়োগ বন্ধ রাখা হয়েছে।'
        USING errcode='23514';
    END IF;
    IF p_position_key='managing_director' AND EXISTS (
      SELECT 1 FROM public.admin_staff
      WHERE position_key='managing_director' AND is_active=true
    ) THEN
      RAISE EXCEPTION 'একজন সক্রিয় Managing Director ইতোমধ্যে নিয়োগপ্রাপ্ত।'
        USING errcode='23505';
    END IF;
    IF p_position_key='department_head' AND EXISTS (
      SELECT 1 FROM public.admin_staff
      WHERE department_key=p_department_key AND position_key='department_head' AND is_active=true
    ) THEN
      RAISE EXCEPTION 'এই বিভাগের একজন সক্রিয় বিভাগীয় প্রধান ইতোমধ্যে আছেন।'
        USING errcode='23505';
    END IF;

    IF p_position_key='department_head' THEN
      SELECT user_id INTO v_reports_to FROM public.admin_staff
      WHERE position_key='managing_director' AND is_active=true LIMIT 1;
    ELSIF p_position_key='department_officer' THEN
      SELECT user_id INTO v_reports_to FROM public.admin_staff
      WHERE department_key=p_department_key AND position_key='department_head' AND is_active=true LIMIT 1;
      IF v_reports_to IS NULL THEN
        SELECT user_id INTO v_reports_to FROM public.admin_staff
        WHERE position_key='managing_director' AND is_active=true LIMIT 1;
      END IF;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('nexora-officer-admin-code'));
    SELECT 'NEX-ADM-' || lpad((coalesce(max(substring(admin_code from '[0-9]+$')::bigint),0)+1)::text,5,'0')
      INTO v_code
    FROM public.admin_staff
    WHERE admin_code LIKE 'NEX-ADM-%';

    UPDATE public.profiles SET role='admin',updated_at=now() WHERE id=v_target;
    INSERT INTO public.admin_staff(
      user_id,admin_code,admin_level,department_key,is_active,created_by,
      staff_email,position_key,reports_to_user_id
    ) VALUES (
      v_target,v_code,'assistant_admin',p_department_key,true,v_actor,
      v_email,p_position_key,v_reports_to
    );
    INSERT INTO public.admin_permission_grants(admin_user_id,permission_key,is_allowed,granted_by)
    SELECT v_target,unnest(v_permissions),true,v_actor;
    v_details:=jsonb_build_object(
      'email',v_email,'admin_code',v_code,'department_key',p_department_key,
      'position_key',p_position_key,'permissions',to_jsonb(v_permissions)
    );

  ELSIF p_action='update' THEN
    IF NOT FOUND OR v_staff.admin_level<>'assistant_admin' THEN
      RAISE EXCEPTION 'এই অ্যাকাউন্টটি পরিচালনাযোগ্য কর্মকর্তা নয়।' USING errcode='42501';
    END IF;
    IF p_position_key='managing_director' AND EXISTS (
      SELECT 1 FROM public.admin_staff
      WHERE position_key='managing_director' AND is_active=true AND user_id<>v_target
    ) THEN
      RAISE EXCEPTION 'একজন সক্রিয় Managing Director ইতোমধ্যে নিয়োগপ্রাপ্ত।'
        USING errcode='23505';
    END IF;
    IF p_position_key='department_head' AND EXISTS (
      SELECT 1 FROM public.admin_staff
      WHERE department_key=p_department_key AND position_key='department_head'
        AND is_active=true AND user_id<>v_target
    ) THEN
      RAISE EXCEPTION 'এই বিভাগের একজন সক্রিয় বিভাগীয় প্রধান ইতোমধ্যে আছেন।'
        USING errcode='23505';
    END IF;
    IF length(btrim(coalesce(p_reason,'')))<5 THEN
      RAISE EXCEPTION 'পরিবর্তনের কারণ অন্তত ৫ অক্ষরে লিখুন।' USING errcode='22023';
    END IF;

    IF p_position_key='department_head' THEN
      SELECT user_id INTO v_reports_to FROM public.admin_staff
      WHERE position_key='managing_director' AND is_active=true LIMIT 1;
    ELSIF p_position_key='department_officer' THEN
      SELECT user_id INTO v_reports_to FROM public.admin_staff
      WHERE department_key=p_department_key AND position_key='department_head' AND is_active=true LIMIT 1;
      IF v_reports_to IS NULL THEN
        SELECT user_id INTO v_reports_to FROM public.admin_staff
        WHERE position_key='managing_director' AND is_active=true LIMIT 1;
      END IF;
    END IF;

    UPDATE public.admin_staff
    SET department_key=p_department_key,position_key=p_position_key,
        staff_email=v_email,reports_to_user_id=v_reports_to,
        is_active=true,updated_at=now()
    WHERE user_id=v_target;
    DELETE FROM public.admin_permission_grants WHERE admin_user_id=v_target;
    INSERT INTO public.admin_permission_grants(admin_user_id,permission_key,is_allowed,granted_by)
    SELECT v_target,unnest(v_permissions),true,v_actor;
    v_code:=v_staff.admin_code;
    v_details:=jsonb_build_object(
      'email',v_email,'admin_code',v_code,'department_key',p_department_key,
      'position_key',p_position_key,'permissions',to_jsonb(v_permissions),
      'previous_department',v_staff.department_key,'previous_position',v_staff.position_key
    );

  ELSE
    IF NOT FOUND OR v_staff.admin_level<>'assistant_admin' THEN
      RAISE EXCEPTION 'এই অ্যাকাউন্টটি পরিচালনাযোগ্য কর্মকর্তা নয়।' USING errcode='42501';
    END IF;
    IF length(btrim(coalesce(p_reason,'')))<5 THEN
      RAISE EXCEPTION 'অ্যাকাউন্ট নিষ্ক্রিয় করার কারণ অন্তত ৫ অক্ষরে লিখুন।' USING errcode='22023';
    END IF;
    UPDATE public.admin_staff SET is_active=false,updated_at=now() WHERE user_id=v_target;
    DELETE FROM public.admin_permission_grants WHERE admin_user_id=v_target;
    v_code:=v_staff.admin_code;
    v_details:=jsonb_build_object('email',v_email,'admin_code',v_code,'is_active',false);
  END IF;

  INSERT INTO public.admin_audit_logs(
    actor_user_id,actor_admin_code,action_key,target_type,target_id,reason,details
  ) VALUES (
    v_actor,v_actor_code,'officer.'||p_action,'admin_staff',v_target::text,
    p_reason,v_details
  );

  RETURN jsonb_build_object('success',true,'admin_code',v_code,'action',p_action);
END;
$function$;

ALTER FUNCTION private.manage_nexora_officer(text,text,text,text,jsonb,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.manage_nexora_officer(text,text,text,text,jsonb,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.manage_nexora_officer(text,text,text,text,jsonb,text) TO authenticated;
