-- ============================================================================
-- SCHOOL CONNECT v4.0 — DEMO ACCOUNTS (read-only for prospects)
-- ----------------------------------------------------------------------------
-- Create five demo accounts on the Auth → Users screen (Supabase Dashboard):
--   1) admin@scdemo.school  (Admin password)  → role: admin
--   2) teacher@scdemo.school (Teacher password)→ role: teacher
--   3) parent@scdemo.school (Parent password) → role: parent
--   4) student@scdemo.school (Student password)→ role: student
--   5) bursar@scdemo.school  (Bursar password) → role: bursar
--
-- After you create them, run the SQL below to (a) attach the profiles
-- correctly and (b) link the parent to the demo student so that the
-- parent-portal experience is realistic for a prospect.
-- ============================================================================

do $$
declare
  uid_admin uuid; uid_teacher uuid; uid_parent uuid; uid_student uuid; uid_bursar uuid;
  sid uuid;
begin
  select id into uid_admin   from auth.users where email='admin@scdemo.school' limit 1;
  select id into uid_teacher from auth.users where email='teacher@scdemo.school' limit 1;
  select id into uid_parent  from auth.users where email='parent@scdemo.school' limit 1;
  select id into uid_student from auth.users where email='student@scdemo.school' limit 1;
  select id into uid_bursar  from auth.users where email='bursar@scdemo.school' limit 1;

  -- profiles
  if uid_admin is not null then
    insert into public.profiles (id, email, full_name, role, status, phone)
    values (uid_admin, 'admin@scdemo.school', 'Mr. Demo Admin', 'admin', 'approved', '+234 800 000 0001')
    on conflict (id) do update set role='admin', status='approved', full_name='Mr. Demo Admin';
  end if;
  if uid_teacher is not null then
    insert into public.profiles (id, email, full_name, role, status, phone)
    values (uid_teacher, 'teacher@scdemo.school', 'Mrs. Funke Alabi', 'teacher', 'approved', '+234 800 000 0002')
    on conflict (id) do update set role='teacher', status='approved', full_name='Mrs. Funke Alabi';
  end if;
  if uid_parent is not null then
    insert into public.profiles (id, email, full_name, role, status, phone)
    values (uid_parent, 'parent@scdemo.school', 'Mr. Adewale Okafor', 'parent', 'approved', '+234 800 000 0003')
    on conflict (id) do update set role='parent', status='approved', full_name='Mr. Adewale Okafor';
  end if;
  if uid_student is not null then
    insert into public.profiles (id, email, full_name, role, status, phone)
    values (uid_student, 'student@scdemo.school', 'Adanna Okafor', 'student', 'approved', '+234 800 000 0004')
    on conflict (id) do update set role='student', status='approved', full_name='Adanna Okafor';
  end if;
  if uid_bursar is not null then
    insert into public.profiles (id, email, full_name, role, status, phone)
    values (uid_bursar, 'bursar@scdemo.school', 'Mrs. Mariam Danladi', 'bursar', 'approved', '+234 800 000 0005')
    on conflict (id) do update set role='bursar', status='approved', full_name='Mrs. Mariam Danladi';
  end if;

  -- Link parent → demo student (GOSA-00014) and the student record to its profile
  if uid_student is not null then
    update public.students set user_id = uid_student
      where admission_no in ('GOSA-00014') and (user_id is null or user_id <> uid_student);
  end if;
  if uid_parent is not null then
    select id into sid from public.students where admission_no='GOSA-00014' limit 1;
    if sid is not null then
      insert into public.parent_child (parent_id, student_id, relationship, verified)
      values (uid_parent, sid, 'parent', true)
      on conflict do nothing;
    end if;
  end if;
end $$;

-- RLS note: profiles.role + status are the only guards. Anything that requires
-- a different role (e.g. teacher seeing the Teacher Overview page) reads the
-- profile row on every page-load and renders the UI accordingly.
select 'School Connect v4.0 demo accounts linked ✅.' as status;
