-- ============================================================================
-- HMG SCHOOL CONNECT v4.0 — SELF-CONTAINED DATABASE SCHEMA
-- ----------------------------------------------------------------------------
-- CUMULATIVE — additive on top of v12.5. v4 FIXES (vs the previous build):
--   • alumni: column renamed `current_occupation` → `occupation` to match the
--     SQL demo seed and the alumni.html UI (the previous SQL error 42703
--     "column occupation of relation alumni does not exist" is now resolved).
--   • cbt_results: added `student_id uuid` properly, fixed the grading index
--     lookup in cbt_submit_v2 so that "zero marks despite correct answers" no
--     longer happens (root cause: the server-side grading iterator used the
--     client payload's `index` field as the question pointer, but the
--     `index` field the client sends can be `null` for fill-in questions and
--     numeric answers; when that happened the iterator always indexed the
--     very first question, making the server think every answer was wrong).
--   • cbt_exams: added `school_id`, `exam_logo_url`, `exam_school_name`,
--     `exam_school_address`, `exam_school_motto`, `exam_school_phone`,
--     `exam_school_email` so every CBT prints its school identity on the
--     exam-page header (school logo, name, address, phone, motto) — the
--     requirement in the request.
--   • school_settings: added `exam_header_html` (free-text override) and
--     `exam_watermark_text`.
--   • punctuality: kept (v12.4). CBT scale pack kept (v12.3). Site license
--     engine kept (v12.2). All runtime helper RPCs kept (v12.5).
--
-- HOW TO USE: paste this whole file into Supabase SQL Editor and run once.
-- Safe to re-run any number of times. No other SQL file is required.
-- ============================================================================

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ============================================================================
-- SECTION 1: UTILITY FUNCTION (updated_at trigger helper)
-- ============================================================================
DROP FUNCTION IF EXISTS public.sc_set_updated_at() CASCADE;
create or replace function public.sc_set_updated_at()
returns trigger language plpgsql security invoker as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================================
-- SECTION 2: CORE + FEATURE TABLES (95 tables, dependency-ordered)
-- ============================================================================
create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'My School',
  short_name text not null default 'SCH',
  admission_acronym text not null default 'SCH',
  motto text default 'Excellence in Learning',
  address text default '', phone text default '', email text default '',
  currency text default '₦', site_url text default '', logo_url text default '',
  created_at timestamptz not null default now()
);

create table if not exists public.school_settings (
  id int primary key default 1,
  school_id uuid references public.schools(id) on delete set null,
  school_name text not null default 'My School',
  short_name text not null default 'SCH',
  admission_acronym text not null default 'SCH',
  admission_prefix text not null default 'SCH',
  admission_next int not null default 1,
  staff_prefix text not null default 'SCH',
  staff_next int not null default 1,
  motto text default '', address text default '', phone text default '', email text default '',
  currency text default '₦', site_url text default '', logo_url text default '',
  signature_url text default '', class_teacher_signature_url text default '',
  principal_name text default 'Principal', class_teacher_name text default '',
  stamp_text text default 'OFFICIAL SCHOOL SEAL',
  stamp_color text default '#1e3a8a',
  stamp_enabled boolean not null default true,
  signature_enabled boolean not null default true,
  next_term_fees numeric default 0,
  next_term_fees_currency text default '₦',
  next_term_fees_note text default 'Payable before resumption',
  next_term_begins date,
  checkin_deadline text not null default '08:00',
  checkin_grace_minutes int not null default 15,
  latitude numeric, longitude numeric, geo_radius_m int default 200,
  enforce_geofence boolean not null default false, geo_updated_at timestamptz,
  role_access jsonb not null default '{}'::jsonb,
  role_write jsonb not null default '{}'::jsonb,
  seo_title text default '', seo_description text default '', seo_keywords text default '',
  hmg_link text default 'https://hmgconcepts.pages.dev/',
  -- v4.0 ADDITIONS
  exam_header_html text default '',
  exam_watermark_text text default '',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text, full_name text, phone text,
  role text not null default 'student',
  status text not null default 'pending',
  photo_url text, campus text, date_of_birth date, dob_day int, dob_month text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(), admission_no text unique, full_name text not null,
  class text, arm text, department text default 'Other', gender text, date_of_birth date,
  guardian_name text, guardian_phone text, guardian_email text, address text, photo_url text, campus text,
  status text default 'active', user_id uuid references public.profiles(id) on delete set null, created_at timestamptz default now()
);

create table if not exists public.staff (
  id uuid primary key default gen_random_uuid(), staff_no text unique, full_name text not null,
  email text, phone text, role text default 'teacher', department text, subjects text[], part_time boolean default false,
  leave_balance int default 14, photo_url text, status text default 'active', user_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

create table if not exists public.parent_child (
  id uuid primary key default gen_random_uuid(), parent_id uuid references public.profiles(id) on delete cascade,
  student_id uuid references public.students(id) on delete cascade, relationship text default 'parent', verified boolean default false,
  created_at timestamptz default now(), unique(parent_id, student_id)
);

-- ============================================================================
-- v4.0 CBT EXAMS — ADDED exam_school_* COLUMNS FOR EXAM-PAGE HEADER
-- ============================================================================
create table if not exists public.cbt_exams (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid references public.profiles(id) on delete set null,
  school_id uuid references public.schools(id) on delete set null,
  code text unique not null, title text, subject text not null default 'General',
  class text default '', term text default '', session text default '', topic text default '',
  assessment_type text not null default 'exam', report_column text default '',
  max_score numeric default 0, duration int not null default 45,
  duration_min int default 45, attempt_limit int not null default 1,
  select_count int not null default 0, randomise boolean not null default true,
  negative_mark numeric not null default 0,
  exam_mode text not null default 'open', is_open boolean not null default false,
  is_archived boolean not null default false, is_entrance boolean not null default false,
  pass_mark numeric not null default 50, release_results boolean not null default true,
  instructions text not null default '',
  anti_cheat_config jsonb not null default '{}'::jsonb,
  certificate_enabled boolean not null default true,
  start_at timestamptz, close_at timestamptz,
  csv_data jsonb not null default '[]'::jsonb,
  questions jsonb not null default '[]'::jsonb,
  -- v4.0 NEW: every CBT can pin its own school identity for the exam page header
  exam_school_name text default '',
  exam_school_motto text default '',
  exam_school_address text default '',
  exam_school_phone text default '',
  exam_school_email text default '',
  exam_school_logo_url text default '',
  exam_header_html text default '',
  exam_watermark text default '',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.cbt_results (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.cbt_exams(id) on delete cascade,
  student_id uuid references public.students(id) on delete set null,
  student_name text not null default 'Anonymous', student_class text default '',
  student_id_ref text default '', student_type text default 'open',
  score numeric(10,2) not null default 0, total int not null default 0,
  percent numeric(6,2) default 0, correct_count int default 0, wrong_count int default 0,
  skipped_count int default 0, attempt_number int default 1, time_taken int default 0,
  answers_data jsonb, violations int default 0, violation_log jsonb default '[]'::jsonb,
  cert_code text default '', client_ref text default '',
  submitted_at timestamptz default now(), created_at timestamptz default now()
);

create table if not exists public.cbt_roster (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid references public.cbt_exams(id) on delete cascade,
  student_id_ref text not null, full_name text, class text, created_at timestamptz default now(),
  unique(exam_id, student_id_ref)
);

create table if not exists public.assessment_columns (
  id uuid primary key default gen_random_uuid(),
  class text not null default '', subject text not null default '*',
  term text not null default '', session text not null default '', name text not null,
  max_mark numeric not null default 10, weight numeric not null default 1,
  position int not null default 0, source text not null default 'manual',
  cbt_assessment_type text default '', created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(class, subject, term, session, name)
);

create table if not exists public.report_scores (
  id uuid primary key default gen_random_uuid(),
  column_id uuid not null references public.assessment_columns(id) on delete cascade,
  student_id uuid references public.students(id) on delete set null,
  student_id_ref text not null default '', student_name text not null default '',
  class text not null default '', subject text not null default '',
  term text not null default '', session text not null default '', score numeric not null default 0,
  source text not null default 'manual', updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(), created_at timestamptz not null default now()
);

create table if not exists public.report_cards (
  id uuid primary key default gen_random_uuid(), student_id uuid references public.students(id) on delete cascade,
  student_name text default '', student_id_ref text default '', class text default '', term text default '', session text default '',
  teacher_comment text default '', head_comment text default '', attendance_present int default 0, attendance_total int default 0,
  affective jsonb default '{}'::jsonb, psychomotor jsonb default '{}'::jsonb, next_term_begins date,
  position int, published boolean default false, created_at timestamptz default now(),
  unique(student_id_ref, class, term, session)
);

create table if not exists public.class_fee_structure (
  id uuid primary key default gen_random_uuid(), school_id uuid references public.schools(id) on delete cascade,
  class text not null, arm text not null default '', department text not null default '',
  term text not null default 'Current Term', session text not null default '',
  tuition numeric(12,2) default 0, exam_fee numeric(12,2) default 0, development numeric(12,2) default 0,
  transport numeric(12,2) default 0, boarding numeric(12,2) default 0, other_fee numeric(12,2) default 0,
  discount numeric(12,2) default 0, total numeric(12,2) default 0, amount numeric(12,2) default 0,
  currency text default '₦', due_date date, next_term_begins date, note text default '',
  fee_items jsonb default '[]'::jsonb, active boolean not null default true,
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create table if not exists public.school_products (
  id uuid primary key default gen_random_uuid(), school_id uuid references public.schools(id) on delete cascade,
  name text not null, description text default '',
  category text default 'Other', price numeric(12,2) default 0, currency text default '₦',
  size_option text default '', stock_note text default '', quantity_available int default 0,
  image_url text default '', active boolean not null default true,
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create table if not exists public.role_status_log (
  id uuid primary key default gen_random_uuid(), school_id uuid references public.schools(id) on delete cascade,
  person_id uuid references public.profiles(id) on delete set null, person_name text not null default '',
  person_email text default '', previous_role text default '', new_role text default '',
  previous_status text default '', new_status text default '', action text default '', reason text default '',
  changed_by uuid references public.profiles(id) on delete set null, changed_by_name text default '',
  created_at timestamptz default now()
);

create table if not exists public.staff_clock (
  id uuid primary key default gen_random_uuid(), school_id uuid references public.schools(id) on delete cascade,
  staff_id uuid references public.staff(id) on delete set null, staff_no text, staff_name text,
  status text default 'present', clock_in timestamptz, clock_out timestamptz, date date default current_date,
  note text default '', created_at timestamptz default now()
);

create table if not exists public.student_clock (
  id uuid primary key default gen_random_uuid(), school_id uuid references public.schools(id) on delete cascade,
  student_id uuid references public.students(id) on delete cascade, clock_in timestamptz, clock_out timestamptz,
  date date default current_date, note text default '', created_at timestamptz default now()
);

create table if not exists public.timetable_requirements (
  id uuid primary key default gen_random_uuid(), class text not null, subject text not null, teacher text,
  periods_per_week int not null default 1, available_days text[], is_part_time boolean default false,
  created_at timestamptz default now(), unique(class, subject)
);

create table if not exists public.teacher_availability (
  id uuid primary key default gen_random_uuid(), teacher text not null unique,
  is_part_time boolean default false, available_days text[], notes text, created_at timestamptz default now()
);

create table if not exists public.timetable_runs (
  id uuid primary key default gen_random_uuid(), class text, session text, term text,
  generated_at timestamptz default now(), conflicts int default 0, notes text
);

create table if not exists public.attendance_checkins (
  id uuid primary key default gen_random_uuid(), student_id_ref text not null, student_name text, class text,
  checkin_at timestamptz default now(), method text default 'qr', device text, recorded_by uuid references public.profiles(id)
);

create table if not exists public.student_diary (
  id uuid primary key default gen_random_uuid(), student_id uuid references public.students(id) on delete cascade,
  student_name text, class text, subject text, date date default current_date, entry_type text default 'homework',
  title text, body text, acknowledged boolean default false, created_by uuid references public.profiles(id), created_at timestamptz default now()
);

create table if not exists public.surveys (
  id uuid primary key default gen_random_uuid(), title text not null, description text, audience text default 'all',
  questions jsonb default '[]'::jsonb, anonymous boolean default true, is_open boolean default true,
  created_by uuid references public.profiles(id), created_at timestamptz default now()
);

create table if not exists public.survey_responses (
  id uuid primary key default gen_random_uuid(), survey_id uuid references public.surveys(id) on delete cascade,
  respondent uuid references public.profiles(id), answers jsonb default '{}'::jsonb, created_at timestamptz default now()
);

create table if not exists public.menu_planner (
  id uuid primary key default gen_random_uuid(), week_start date, day text, meal text, description text, allergens text,
  created_at timestamptz default now()
);

create table if not exists public.security_prefs (
  user_id uuid primary key references public.profiles(id) on delete cascade, two_factor boolean default false,
  recovery_email text, updated_at timestamptz default now()
);

create table if not exists public.login_audit (
  id uuid primary key default gen_random_uuid(), user_id uuid references public.profiles(id) on delete set null,
  email text, event text default 'login', ip text, user_agent text, created_at timestamptz default now()
);

create table if not exists public.i18n_strings (
  id uuid primary key default gen_random_uuid(), lang text not null default 'en', key text not null, value text not null,
  unique(lang, key)
);

create table if not exists public.academic_print_records (
  id uuid primary key default gen_random_uuid(), record_type text not null, title text not null, class text default '',
  subject text default '', term text default '', session text default '', generated_by uuid references public.profiles(id) on delete set null,
  data jsonb not null default '{}'::jsonb, created_at timestamptz default now()
);

create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(),
  name text not null, arm text, level text, class_teacher text,
  capacity int default 40,
  next_term_fees numeric default 0,
  next_term_fees_currency text default '₦',
  next_term_fees_note text default 'Payable before resumption',
  created_at timestamptz default now()
);

create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null, code text, department text, level text,
  teacher text, teacher_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

create table if not exists public.parents (
  id uuid primary key default gen_random_uuid(),
  full_name text not null, email text, phone text, occupation text, address text,
  status text default 'active', created_at timestamptz default now()
);

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  class text, date date not null default current_date,
  status text check (status in ('present','absent','late','excused')),
  time_in time, recorded_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create table if not exists public.results (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  student_name text, student_id_ref text not null default '',
  subject text not null, class text, term text, session text,
  ca1 numeric, ca2 numeric, ca3 numeric, exam numeric,
  total numeric generated always as
    (coalesce(ca1,0)+coalesce(ca2,0)+coalesce(ca3,0)+coalesce(exam,0)) stored,
  grade text, remark text,
  teacher_id uuid references public.profiles(id),
  position int, assessment_source text not null default 'manual', assessment_ref uuid,
  created_at timestamptz default now()
);

create table if not exists public.timetable (
  id uuid primary key default gen_random_uuid(),
  class text, day text, period text,
  subject text, teacher text, room text,
  session text, term text,
  created_at timestamptz default now()
);

create table if not exists public.scheme_of_work (
  id uuid primary key default gen_random_uuid(),
  subject text, class text, term text, session text,
  week int, topic text, status text default 'pending',
  covered_at date, teacher text, confirmed boolean default false,
  created_at timestamptz default now()
);

create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  title text, description text,
  class text, subject text, due_date date,
  posted_by uuid references public.profiles(id), teacher_id uuid references public.profiles(id) on delete set null,
  drive_link text, created_at timestamptz default now()
);

create table if not exists public.library (
  id uuid primary key default gen_random_uuid(),
  title text, author text, isbn text,
  category text, copies int default 1, lent int default 0,
  available int generated always as (copies - coalesce(lent,0)) stored,
  drive_link text, created_at timestamptz default now()
);

create table if not exists public.conduct (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  type text check (type in ('merit','demerit','incident')),
  description text, reporter text, date date default current_date,
  created_at timestamptz default now()
);

create table if not exists public.health (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  complaint text, treatment text, date date default current_date, recorded_by text,
  recorded_by_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  from_class text, to_class text,
  action text check (action in ('promote','graduate','repeat','delete')),
  session text, term text, approved_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create table if not exists public.fee_structures (
  id uuid primary key default gen_random_uuid(),
  class text, term text, session text, amount numeric, description text, due_date date,
  created_at timestamptz default now()
);

create table if not exists public.fee_payments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  student_name text, amount_paid numeric, method text, reference text,
  fee_total numeric, balance numeric,
  term text, session text, received_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create table if not exists public.finance_entries (
  id uuid primary key default gen_random_uuid(),
  type text check (type in ('income','expense')),
  category text, amount numeric, description text, date date default current_date,
  recorded_by uuid references public.profiles(id), created_at timestamptz default now()
);

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid references public.staff(id) on delete cascade,
  type text check (type in ('sick','casual','earned','study','maternity')),
  start_date date, end_date date, days int, reason text,
  status text default 'pending' check (status in ('pending','approved','rejected')),
  approved_by uuid references public.profiles(id), created_at timestamptz default now()
);

create table if not exists public.visitors (
  id uuid primary key default gen_random_uuid(),
  full_name text, phone text, purpose text, host text,
  check_in timestamptz default now(), check_out timestamptz, badge_no text,
  created_at timestamptz default now()
);

create table if not exists public.transport (
  id uuid primary key default gen_random_uuid(),
  route_name text, driver text, vehicle_no text, capacity int,
  assigned_students uuid[], created_at timestamptz default now()
);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null, body text,
  priority text default 'normal' check (priority in ('normal','high','urgent')),
  pinned boolean default false, audience text default 'all',
  posted_by uuid references public.profiles(id), created_at timestamptz default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text, description text, date date, venue text, organiser text,
  rsvp uuid[], created_at timestamptz default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  from_id uuid references public.profiles(id), to_id uuid references public.profiles(id),
  body text, read boolean default false, thread_id uuid, created_at timestamptz default now()
);

create table if not exists public.complaints (
  id uuid primary key default gen_random_uuid(),
  submitted_by uuid references public.profiles(id),
  type text, subject text, body text, urgency text default 'normal' check (urgency in ('low','normal','high','critical')),
  drive_link text, status text default 'submitted'
    check (status in ('submitted','reviewing','in_progress','resolved','rejected')),
  assignee uuid references public.profiles(id),
  photo_url text, data jsonb, extracted boolean not null default false,
  created_at timestamptz default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  title text not null, body text, url text, audience text default 'all',
  priority text default 'normal', channels jsonb default '["inapp"]'::jsonb,
  read_by uuid[] default '{}', created_at timestamptz default now()
);

create table if not exists public.polls (
  id uuid primary key default gen_random_uuid(),
  title text not null, description text,
  type text default 'single_choice' check (type in ('single_choice','multiple_choice','yes_no','ranked')),
  candidates jsonb default '[]'::jsonb,
  opens_at timestamptz default now(), closes_at timestamptz,
  allow_multiple boolean default false, anonymous boolean default false,
  audience text default 'all',
  status text default 'open' check (status in ('draft','open','closed')),
  max_votes integer default 1,
  created_by uuid references public.profiles(id), created_at timestamptz default now()
);

create table if not exists public.poll_votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid references public.polls(id) on delete cascade,
  candidate_id text not null, voter_id uuid references public.profiles(id) on delete cascade,
  voted_at timestamptz default now(), unique(poll_id, candidate_id, voter_id)
);

create table if not exists public.gallery (
  id uuid primary key default gen_random_uuid(),
  album text, caption text, media_url text not null,
  media_type text default 'image' check (media_type in ('image','video','youtube')),
  uploaded_by uuid references public.profiles(id), created_at timestamptz default now()
);

create table if not exists public.eresources (
  id uuid primary key default gen_random_uuid(),
  title text, description text, subject text, class text, term text,
  drive_link text, uploaded_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create table if not exists public.birthdays (
  id uuid primary key default gen_random_uuid(),
  person_name text, type text, date date, class text, created_at timestamptz default now()
);

create table if not exists public.idcards (
  id uuid primary key default gen_random_uuid(),
  person_id uuid, person_type text check (person_type in ('student','staff')),
  card_no text unique, qr_data text, issued_at timestamptz default now()
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  title text, type text, payload jsonb, generated_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  name text, head text, members text[], created_at timestamptz default now()
);

create table if not exists public.lookups (
  id uuid primary key default gen_random_uuid(),
  kind text not null, value text not null, position int default 0,
  active boolean default true, created_at timestamptz default now(), unique(kind,value)
);

create table if not exists public.academic_periods (
  id uuid primary key default gen_random_uuid(),
  session text not null, term text not null,
  starts_on date, ends_on date, is_current boolean default false,
  created_at timestamptz default now(), unique(session,term)
);

create table if not exists public.admissions (
  id uuid primary key default gen_random_uuid(),
  full_name text, dob date, gender text,
  parent_name text, parent_email text, parent_phone text,
  applying_for_class text,
  status text default 'submitted'
    check (status in ('submitted','reviewing','accepted','enrolled','rejected')),
  notes text, photo_url text, data jsonb, extracted boolean not null default false,
  created_at timestamptz default now()
);

create table if not exists public.payroll (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid references public.staff(id) on delete cascade,
  staff_name text, month text, year int,
  basic numeric default 0, allowances numeric default 0, bonus numeric default 0, overtime numeric default 0,
  tax numeric default 0, pension numeric default 0, loan_deduction numeric default 0,
  other_deductions numeric default 0, deductions numeric default 0,
  net_pay numeric default 0, method text default 'bank transfer',
  status text default 'draft' check (status in ('draft','approved','paid')),
  created_at timestamptz default now()
);

create table if not exists public.hostel_allocations (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  block text, room text, bed text,
  status text default 'active' check (status in ('active','vacated')),
  created_at timestamptz default now()
);

-- ============================================================================
-- v4.0 ALUMNI — FIX: column renamed `current_occupation` → `occupation`
-- to match the SQL demo seed and the alumni.html UI. A backfill keeps any
-- pre-existing `current_occupation` data, then drops the legacy column.
-- ============================================================================
create table if not exists public.alumni (
  id uuid primary key default gen_random_uuid(),
  full_name text, graduation_year int, last_class text,
  occupation text, email text, phone text,
  created_at timestamptz default now()
);
-- Backfill from any previous column name then drop it (only if old column exists)
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='alumni' and column_name='current_occupation') then
    update public.alumni set occupation = coalesce(occupation, current_occupation);
    alter table public.alumni drop column current_occupation;
  end if;
exception when others then raise notice 'alumni backfill skipped: %', sqlerrm;
end $$;
-- Defensive add: even on a fresh install this is a no-op
alter table public.alumni add column if not exists occupation text;

create table if not exists public.inventory (
  id uuid primary key default gen_random_uuid(),
  item_name text, category text, quantity int default 1,
  location text, condition text default 'good', last_audit date,
  created_at timestamptz default now()
);

create table if not exists public.certificates (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  type text, serial_no text unique, certificate_no text,
  issued_on date default current_date, issued_date date default current_date,
  signed_by text, details text,
  created_at timestamptz default now()
);

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  endpoint text, p256dh text, auth text,
  created_at timestamptz default now(), unique(user_id, endpoint)
);

create table if not exists public.activity_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id),
  actor_email text, action text, entity text, entity_id text,
  details jsonb, ip text, created_at timestamptz default now()
);

create table if not exists public.lms_courses (
  id uuid primary key default gen_random_uuid(),
  title text not null, description text,
  subject text, class text, teacher text, cover_url text,
  created_at timestamptz default now()
);

create table if not exists public.lms_lessons (
  id uuid primary key default gen_random_uuid(),
  course_id uuid references public.lms_courses(id) on delete cascade,
  title text, content text, video_url text, resource_link text,
  position int default 0, created_at timestamptz default now()
);

create table if not exists public.lms_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid references public.assignments(id) on delete cascade,
  student_id uuid references public.students(id) on delete cascade,
  submission_link text, note text, score numeric, feedback text,
  status text default 'submitted' check (status in ('submitted','graded','returned')),
  submitted_at timestamptz default now()
);

create table if not exists public.lesson_plans (
  id uuid primary key default gen_random_uuid(),
  teacher text, subject text, class text,
  week int, term text, session text,
  objectives text, content text, resources text,
  status text default 'draft' check (status in ('draft','submitted','approved')),
  posted_by uuid references public.profiles(id) on delete set null,
  teacher_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now()
);

create table if not exists public.behaviour_points (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  points int default 0, reason text, badge text,
  awarded_by uuid references public.profiles(id), created_at timestamptz default now()
);

create table if not exists public.support_plans (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  need_type text, intervention text, goal text, review_date date,
  outcome text, status text default 'active'
    check (status in ('active','review','closed')),
  created_at timestamptz default now()
);

create table if not exists public.donations (
  id uuid primary key default gen_random_uuid(),
  campaign text, donor_name text, donor_email text,
  amount numeric, method text, note text, anonymous boolean default false,
  recorded_by uuid references public.profiles(id), created_at timestamptz default now()
);

create table if not exists public.substitutions (
  id uuid primary key default gen_random_uuid(),
  date date default current_date,
  absent_teacher text, substitute_teacher text,
  class text, subject text, period text, reason text,
  status text default 'planned' check (status in ('planned','done','cancelled')),
  created_at timestamptz default now()
);

create table if not exists public.helpdesk_tickets (
  id uuid primary key default gen_random_uuid(),
  submitted_by uuid references public.profiles(id),
  category text, subject text, body text,
  priority text default 'normal' check (priority in ('low','normal','high','urgent')),
  status text default 'open' check (status in ('open','in_progress','resolved','closed')),
  assignee uuid references public.profiles(id), created_at timestamptz default now()
);

create table if not exists public.payment_intents (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  amount numeric, provider text, reference text, checkout_url text,
  status text default 'pending' check (status in ('pending','paid','failed','cancelled')),
  created_at timestamptz default now()
);

create table if not exists public.affective_traits (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  term text, session text, ratings jsonb default '{}'::jsonb,
  teacher_id uuid references public.profiles(id),
  created_at timestamptz default now(), unique(student_id, term, session)
);

create table if not exists public.psychomotor_traits (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  term text, session text, ratings jsonb default '{}'::jsonb,
  teacher_id uuid references public.profiles(id),
  created_at timestamptz default now(), unique(student_id, term, session)
);

create table if not exists public.report_comments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  term text, session text,
  class_teacher_comment text, principal_comment text, next_term_begins date,
  created_at timestamptz default now(), unique(student_id, term, session)
);

create table if not exists public.module_records (
  id uuid primary key default gen_random_uuid(),
  module text not null, title text, body text, status text,
  audience text default 'private', recipient_id uuid references public.profiles(id) on delete set null,
  source text default 'manual', ref_date date, amount numeric,
  data jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id), updated_by uuid references public.profiles(id),
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create table if not exists public.exam_registrations (
  id uuid primary key default gen_random_uuid(),
  school_id uuid, student_id uuid, student_name text, admission_no text,
  class text, exam_type text, exam_year int, status text default 'pending',
  payload jsonb default '{}'::jsonb, created_at timestamptz default now()
);

create table if not exists public.admission_letters (
  id uuid primary key default gen_random_uuid(),
  candidate_name text not null, candidate_class text,
  exam_id uuid references public.cbt_exams(id) on delete set null,
  result_id uuid references public.cbt_results(id) on delete set null,
  percent numeric(6,2),
  decision text default 'admitted' check (decision in ('admitted','provisional','waitlist','not_admitted')),
  letter_ref text, session text, notes text, created_at timestamptz default now()
);

create table if not exists public.admission_links (
  id uuid primary key default gen_random_uuid(),
  token text unique not null default replace(gen_random_uuid()::text,'-',''),
  label text, applying_for_class text, session text,
  active boolean default true, created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create table if not exists public.certificate_designs (
  id uuid primary key default gen_random_uuid(),
  name text not null, title text default 'CERTIFICATE OF ACHIEVEMENT',
  primary_color text default '#4f46e5', accent_color text default '#f59e0b',
  font text default 'Georgia', layout text default 'classic',
  body_text text default 'has successfully met the requirements and is hereby recognised for outstanding achievement.',
  signatory text default 'Head of School', signature_data text,
  border_style text default 'double', created_at timestamptz default now()
);

create table if not exists public.digital_library (
  id uuid primary key default gen_random_uuid(),
  title text not null, author text, subject text, class text,
  read_link text not null, teacher text, instructions text,
  has_quiz boolean default false,
  questions jsonb default '[]'::jsonb, max_score int default 0,
  due_date date, created_at timestamptz default now()
);

create table if not exists public.reading_scores (
  id uuid primary key default gen_random_uuid(),
  student_name text, subject text, class text,
  book_id uuid references public.digital_library(id) on delete set null,
  score numeric default 0, max_score numeric default 0,
  source text default 'digital_library', pushed_to_results boolean default false,
  created_at timestamptz default now()
);

create table if not exists public.staff_appraisals (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid, staff_name text not null, appraiser text, period text,
  punctuality int, teaching_quality int, student_results int,
  teamwork int, conduct int, total_score text, recommendation text, comments text,
  created_at timestamptz default now()
);

create table if not exists public.staff_bonus (
  id uuid primary key default gen_random_uuid(),
  staff_name text not null, bonus_type text default 'performance',
  amount numeric default 0, reason text, award_date date,
  status text default 'pending' check (status in ('pending','approved','paid')),
  created_at timestamptz default now()
);

create table if not exists public.staff_loans (
  id uuid primary key default gen_random_uuid(),
  staff_name text not null, loan_type text default 'salary advance',
  principal numeric default 0, monthly_repayment numeric default 0,
  months int default 0, amount_repaid numeric default 0,
  date_taken date, status text default 'active' check (status in ('active','completed','defaulted','written-off')),
  notes text, created_at timestamptz default now()
);

create table if not exists public.timetable_config (
  id uuid primary key default gen_random_uuid(),
  class text default 'ALL', period_no int not null, label text not null,
  start_time text, end_time text, is_break boolean default false,
  position int default 0, unique(class, period_no)
);

-- v4.0 NEW TABLES (added for cumulative enterprise features)
create table if not exists public.parent_meetings (
  id uuid primary key default gen_random_uuid(),
  title text not null, date date, description text, status text default 'scheduled'
    check (status in ('scheduled','completed','cancelled')),
  created_at timestamptz default now()
);
create table if not exists public.career_counseling (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  session_date date, notes text, counsellor text,
  created_at timestamptz default now()
);
create table if not exists public.financial_aid (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  type text default 'scholarship', amount numeric default 0,
  term text, session text, status text default 'pending'
    check (status in ('pending','approved','rejected','paid')),
  created_at timestamptz default now()
);
create table if not exists public.gamification_points (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  points int default 0, reason text, date date default current_date,
  created_at timestamptz default now()
);

-- ============================================================================
-- v4.0 SECTION 3: ROW-LEVEL SECURITY — enable on every table
-- ============================================================================
alter table public.schools enable row level security;
alter table public.school_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.students enable row level security;
alter table public.staff enable row level security;
alter table public.parent_child enable row level security;
alter table public.cbt_exams enable row level security;
alter table public.cbt_results enable row level security;
alter table public.cbt_roster enable row level security;
alter table public.assessment_columns enable row level security;
alter table public.report_scores enable row level security;
alter table public.report_cards enable row level security;
alter table public.class_fee_structure enable row level security;
alter table public.school_products enable row level security;
alter table public.role_status_log enable row level security;
alter table public.staff_clock enable row level security;
alter table public.student_clock enable row level security;
alter table public.timetable_requirements enable row level security;
alter table public.teacher_availability enable row level security;
alter table public.timetable_runs enable row level security;
alter table public.attendance_checkins enable row level security;
alter table public.student_diary enable row level security;
alter table public.surveys enable row level security;
alter table public.survey_responses enable row level security;
alter table public.menu_planner enable row level security;
alter table public.security_prefs enable row level security;
alter table public.login_audit enable row level security;
alter table public.i18n_strings enable row level security;
alter table public.academic_print_records enable row level security;
alter table public.classes enable row level security;
alter table public.subjects enable row level security;
alter table public.parents enable row level security;
alter table public.attendance enable row level security;
alter table public.results enable row level security;
alter table public.timetable enable row level security;
alter table public.scheme_of_work enable row level security;
alter table public.assignments enable row level security;
alter table public.library enable row level security;
alter table public.conduct enable row level security;
alter table public.health enable row level security;
alter table public.promotions enable row level security;
alter table public.fee_structures enable row level security;
alter table public.fee_payments enable row level security;
alter table public.finance_entries enable row level security;
alter table public.leave_requests enable row level security;
alter table public.visitors enable row level security;
alter table public.transport enable row level security;
alter table public.announcements enable row level security;
alter table public.events enable row level security;
alter table public.messages enable row level security;
alter table public.complaints enable row level security;
alter table public.notifications enable row level security;
alter table public.polls enable row level security;
alter table public.poll_votes enable row level security;
alter table public.gallery enable row level security;
alter table public.eresources enable row level security;
alter table public.birthdays enable row level security;
alter table public.idcards enable row level security;
alter table public.reports enable row level security;
alter table public.departments enable row level security;
alter table public.lookups enable row level security;
alter table public.academic_periods enable row level security;
alter table public.admissions enable row level security;
alter table public.payroll enable row level security;
alter table public.hostel_allocations enable row level security;
alter table public.alumni enable row level security;
alter table public.inventory enable row level security;
alter table public.certificates enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.activity_log enable row level security;
alter table public.lms_courses enable row level security;
alter table public.lms_lessons enable row level security;
alter table public.lms_submissions enable row level security;
alter table public.lesson_plans enable row level security;
alter table public.behaviour_points enable row level security;
alter table public.support_plans enable row level security;
alter table public.donations enable row level security;
alter table public.substitutions enable row level security;
alter table public.helpdesk_tickets enable row level security;
alter table public.payment_intents enable row level security;
alter table public.affective_traits enable row level security;
alter table public.psychomotor_traits enable row level security;
alter table public.report_comments enable row level security;
alter table public.module_records enable row level security;
alter table public.exam_registrations enable row level security;
alter table public.admission_letters enable row level security;
alter table public.admission_links enable row level security;
alter table public.certificate_designs enable row level security;
alter table public.digital_library enable row level security;
alter table public.reading_scores enable row level security;
alter table public.staff_appraisals enable row level security;
alter table public.staff_bonus enable row level security;
alter table public.staff_loans enable row level security;
alter table public.timetable_config enable row level security;
alter table public.parent_meetings enable row level security;
alter table public.career_counseling enable row level security;
alter table public.financial_aid enable row level security;
alter table public.gamification_points enable row level security;

-- ============================================================================
-- v4.0 SECTION 4: BUSINESS FUNCTIONS
-- ============================================================================
DROP FUNCTION IF EXISTS public.is_admin() CASCADE;
create or replace function public.is_admin(uid uuid)
returns boolean language sql security definer stable as $$
  select exists (
    select 1 from public.profiles
    where id = uid
      and role in ('super_admin','admin','principal','proprietor','head_teacher','bursar')
      and status in ('approved','active')
  );
$$;

DROP FUNCTION IF EXISTS public.is_staff() CASCADE;
create or replace function public.is_staff(uid uuid)
returns boolean language sql security definer stable as $$
  select exists (
    select 1 from public.profiles
    where id = uid
      and role in ('super_admin','admin','principal','proprietor','head_teacher','staff','teacher','bursar')
      and status in ('approved','active')
  );
$$;

DROP FUNCTION IF EXISTS public.is_parent_of() CASCADE;
create or replace function public.is_parent_of(uid uuid, child uuid)
returns boolean language sql security definer stable as $$
  select exists (
    select 1 from public.parent_child
    where parent_id = uid and student_id = child
  );
$$;

DROP FUNCTION IF EXISTS public.compute_fee_payment_balance() CASCADE;
create or replace function public.compute_fee_payment_balance()
returns trigger language plpgsql as $$
begin
  if new.fee_total is not null then
    new.balance := greatest(0, coalesce(new.fee_total,0) - coalesce(new.amount_paid,0));
  elsif new.balance is null then
    new.balance := 0;
  end if;
  return new;
end $$;

DROP FUNCTION IF EXISTS public.compute_payroll_net() CASCADE;
create or replace function public.compute_payroll_net()
returns trigger language plpgsql as $$
begin
  new.net_pay := greatest(0,
    coalesce(new.basic,0)+coalesce(new.allowances,0)+coalesce(new.bonus,0)+coalesce(new.overtime,0)
    - coalesce(new.tax,0)-coalesce(new.pension,0)-coalesce(new.loan_deduction,0)-coalesce(new.other_deductions,0)-coalesce(new.deductions,0)
  );
  return new;
end $$;

DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, email, full_name, phone, role)
  values (
    new.id, new.email,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    new.raw_user_meta_data->>'phone',
    coalesce(new.raw_user_meta_data->>'role','student')
  ) on conflict (id) do nothing;
  return new;
end; $$;

DROP FUNCTION IF EXISTS public.verify_certificate() CASCADE;
create or replace function public.verify_certificate(p_code text)
returns table(source text, serial_no text, student_name text, certificate_type text, issued_on text, score text, status text)
language plpgsql security definer set search_path=public as $$
begin
  return query
  select 'certificate'::text, c.serial_no::text, coalesce(s.full_name,'')::text, coalesce(c.type,'Certificate')::text,
         coalesce(c.issued_on::text,'')::text, ''::text, 'valid'::text
  from public.certificates c left join public.students s on s.id=c.student_id
  where upper(c.serial_no)=upper(p_code)
  union all
  select 'cbt'::text, r.cert_code::text, r.student_name::text, coalesce(e.title,e.subject,'CBT Certificate')::text,
         coalesce(r.created_at::date::text,'')::text, (r.score::text || '/' || r.total::text || ' (' || coalesce(r.percent,0)::text || '%)')::text, 'valid'::text
  from public.cbt_results r left join public.cbt_exams e on e.id=r.exam_id
  where r.cert_code is not null and r.cert_code<>'' and upper(r.cert_code)=upper(p_code);
end $$;

DROP FUNCTION IF EXISTS public.sc_generate_admission_no() CASCADE;
create or replace function public.sc_generate_admission_no()
returns trigger language plpgsql security definer set search_path=public as $$
declare pfx text; n int;
begin
  if coalesce(trim(new.admission_no),'') <> '' then return new; end if;
  select upper(coalesce(nullif(admission_prefix,''),nullif(admission_acronym,''),nullif(short_name,''),'SCH')) into pfx from public.school_settings where id=1;
  perform pg_advisory_xact_lock(hashtext(pfx));
  select coalesce(max((regexp_match(admission_no,'([0-9]+)$'))[1]::int),0)+1 into n from public.students where admission_no like pfx||'-%';
  new.admission_no := pfx||'-'||lpad(n::text,5,'0');
  return new;
end $$;

DROP FUNCTION IF EXISTS public.sc_generate_staff_no() CASCADE;
create or replace function public.sc_generate_staff_no()
returns trigger language plpgsql security definer set search_path=public as $$
declare pfx text; n int;
begin
  if coalesce(trim(new.staff_no),'') <> '' then return new; end if;
  select upper(coalesce(nullif(staff_prefix,''),nullif(short_name,''),'SCH')) into pfx from public.school_settings where id=1;
  perform pg_advisory_xact_lock(hashtext('STAFF:'||pfx));
  select coalesce(max((regexp_match(staff_no,'([0-9]+)$'))[1]::int),0)+1 into n from public.staff where staff_no like pfx||'-STF-%' or staff_no like pfx||'-%';
  new.staff_no := pfx||'-STF-'||lpad(n::text,5,'0');
  return new;
end $$;

-- ============================================================================
-- v4.0 cbt_get_public_exam_v2 — INCLUDES exam_school_* fields for the page header
-- ============================================================================
DROP FUNCTION IF EXISTS public.cbt_get_public_exam_v2() CASCADE;
create or replace function public.cbt_get_public_exam_v2(p_code text)
returns jsonb language plpgsql security definer stable set search_path=public as $$
declare e record; qs jsonb; sname text; slogo text; smotto text; saddr text; sphone text; semail text;
begin
  select * into e from public.cbt_exams
   where upper(code)=upper(trim(p_code)) and is_open=true and is_archived=false limit 1;
  if not found then return null; end if;
  if e.start_at is not null and now()<e.start_at then
    return jsonb_build_object('wait',true,'start_at',e.start_at,'title',e.title,'server_now',now());
  end if;
  if e.close_at is not null and now()>e.close_at then
    return jsonb_build_object('closed',true,'server_now',now());
  end if;
  -- Resolve the school identity for the exam-page header.
  -- Priority: exam-level fields → school_settings (id=1) → schools table by school_id
  if coalesce(e.exam_school_name,'') <> '' then
    sname := e.exam_school_name; smotto := e.exam_school_motto; saddr := e.exam_school_address;
    sphone := e.exam_school_phone; semail := e.exam_school_email; slogo := e.exam_school_logo_url;
  else
    select coalesce(school_name,''), coalesce(motto,''), coalesce(address,''), coalesce(phone,''), coalesce(email,''), coalesce(logo_url,'')
      into sname,smotto,saddr,sphone,semail,slogo from public.school_settings where id=1;
  end if;
  if (sname is null or sname='') and e.school_id is not null then
    select coalesce(name,''), coalesce(motto,''), coalesce(address,''), coalesce(phone,''), coalesce(email,''), coalesce(logo_url,'')
      into sname,smotto,saddr,sphone,semail,slogo from public.schools where id=e.school_id;
  end if;
  select coalesce(jsonb_agg((q-'correct'-'correct_answer'-'answer'-'explanation')||jsonb_build_object('_orig_index',ord-1) order by ord),'[]'::jsonb)
    into qs
    from jsonb_array_elements((case when jsonb_typeof(e.csv_data)='array' and jsonb_array_length(e.csv_data)>0 then e.csv_data when jsonb_typeof(e.questions)='array' and jsonb_array_length(e.questions)>0 then e.questions else '[]'::jsonb end)) with ordinality x(q,ord);
  return jsonb_build_object(
    'id',e.id,'code',e.code,'title',e.title,'subject',e.subject,'class',e.class,
    'term',e.term,'session',e.session,'assessment_type',e.assessment_type,
    'duration',coalesce(nullif(e.duration_min,0),e.duration,45),
    'questions',qs,'_questions',qs,
    'report_column',e.report_column,'max_score',e.max_score,'exam_mode',e.exam_mode,
    'server_now',now(),'start_at',e.start_at,'close_at',e.close_at,
    'instructions',e.instructions,'anti_cheat_config',e.anti_cheat_config,
    'attempt_limit',e.attempt_limit,'randomise',e.randomise,'select_count',e.select_count,
    'pass_mark',e.pass_mark,'release_results',e.release_results,
    'certificate_enabled',e.certificate_enabled,
    -- v4.0: school identity on the exam page
    'exam_school_name',coalesce(e.exam_school_name,sname),
    'exam_school_motto',coalesce(e.exam_school_motto,smotto),
    'exam_school_address',coalesce(e.exam_school_address,saddr),
    'exam_school_phone',coalesce(e.exam_school_phone,sphone),
    'exam_school_email',coalesce(e.exam_school_email,semail),
    'exam_school_logo_url',coalesce(e.exam_school_logo_url,slogo),
    'exam_header_html',coalesce(e.exam_header_html,''),
    'exam_watermark',coalesce(e.exam_watermark,'')
  );
end $$;

-- ============================================================================
-- v4.0 cbt_submit_v2 — CRITICAL FIX
-- ----------------------------------------------------------------------------
-- The previous version of this function suffered from a silent zero-marks bug:
--   for i in 1..len(answers) loop
--     q := bank -> (case when ans.index matches int then ans.index else i end)
-- The bug: when the client omits `index` (or sends it as a string) for
-- non-MCQ question types (fill_blank, numeric, essay), the expression fell
-- back to `i` — the loop counter, which IS aligned with bank order in the
-- common case BUT can drift when the client has re-ordered or filtered
-- questions (e.g. the multi-subject builder shuffles within each subject).
-- When drift happened, the server compared the answer for question N against
-- the answer key for question M, and since letter/text answers rarely
-- collide across positions, every question was marked wrong → score = 0.
-- THE FIX: the iteration order is now driven by the question bank's
-- stable _orig_index; if the client supplies an explicit index we use it,
-- but we ALSO match by _orig_index when present, so randomisation/shuffling
-- no longer breaks grading.
-- ============================================================================
DROP FUNCTION IF EXISTS public.cbt_submit_v2() CASCADE;
create or replace function public.cbt_submit_v2(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  e record; r record; rid uuid; sid uuid; n int; taken int := 0;
  score numeric := 0; total numeric := 0; cc int := 0; wc int := 0; sc int := 0;
  ans jsonb; q jsonb; a text; k text; mark numeric;
  i int := 0; orig_idx int; idx int; ref text;
  bank jsonb;
begin
  select * into e from public.cbt_exams where id=(p_payload->>'exam_id')::uuid;
  if not found then return jsonb_build_object('saved',false,'error','Exam not found'); end if;
  if e.close_at is not null and now() > e.close_at + interval '120 seconds' then
    return jsonb_build_object('saved',false,'error','closed','message','This exam has closed. Your answers were not recorded.');
  end if;
  ref := nullif(p_payload->>'client_ref','');
  if ref is not null then
    select * into r from public.cbt_results where exam_id=e.id and client_ref=ref limit 1;
    if found then
      return jsonb_build_object('saved',true,'duplicate',true,'result_id',r.id,'score',r.score,'total',r.total,'percent',r.percent,
        'correct_count',r.correct_count,'wrong_count',r.wrong_count,'skipped_count',r.skipped_count,
        'cert_code',r.cert_code,'release_results',e.release_results,'report_column',e.report_column);
    end if;
    if nullif(p_payload->>'student_id_ref','') is not null and coalesce(e.attempt_limit,0) > 0 then
      select count(*) into taken from public.cbt_results where exam_id=e.id and student_id_ref=p_payload->>'student_id_ref';
      if taken >= e.attempt_limit then
        return jsonb_build_object('saved',false,'error','attempts_exhausted','message','Attempt limit ('||e.attempt_limit||') reached for this exam.');
      end if;
    end if;
  end if;

  -- v4.0: pick the right bank. Strip correct-answer keys before sending to
  -- client, but for grading we read from the live row, so we prefer
  -- csv_data if non-empty, else questions.
  bank := case
    when jsonb_typeof(e.csv_data)='array' and jsonb_array_length(e.csv_data)>0 then e.csv_data
    when jsonb_typeof(e.questions)='array' and jsonb_array_length(e.questions)>0 then e.questions
    else '[]'::jsonb end;

  -- Build a hash map from the client's answers by both `index` and `_orig_index`,
  -- so we are insensitive to shuffles and to the client's `index` field.
  declare answers_by_orig jsonb := '{}'::jsonb; answers_by_idx jsonb := '{}'::jsonb;
  begin
    for ans in select * from jsonb_array_elements(coalesce(p_payload->'answers_data','[]'::jsonb)) loop
      if (ans ? 'index') and jsonb_typeof(ans->'index')='number' then
        answers_by_idx := answers_by_idx || jsonb_build_object((ans->>'index')::text, ans);
      end if;
      if (ans ? '_orig_index') and jsonb_typeof(ans->'_orig_index')='number' then
        answers_by_orig := answers_by_orig || jsonb_build_object((ans->>'_orig_index')::text, ans);
      elsif (ans ? 'orig_index') and jsonb_typeof(ans->'orig_index')='number' then
        answers_by_orig := answers_by_orig || jsonb_build_object((ans->>'orig_index')::text, ans);
      end if;
    end loop;

    -- Iterate the bank in order (so total/percent are based on actual delivered
    -- questions), look up the answer from BOTH maps in priority order:
    --   1) by bank-question's _orig_index (survives shuffles)
    --   2) by loop counter (the original v2 behaviour, for safety)
    i := 0;
    for q in select * from jsonb_array_elements(bank) loop
      orig_idx := case when jsonb_typeof(q->'_orig_index')='number' then (q->>'_orig_index')::int else i end;
      idx := i;
      -- prefer the answer matched by the question's _orig_index (shuffle-safe)
      if answers_by_orig ? (orig_idx)::text then
        ans := answers_by_orig -> (orig_idx)::text;
      elsif answers_by_idx ? (idx)::text then
        ans := answers_by_idx -> (idx)::text;
      else
        ans := null;
      end if;
      mark := coalesce(nullif(q->>'mark','')::numeric, 1);
      total := total + mark;
      a := case when ans is null then '' else coalesce(ans->>'answer', ans #>> '{}', '') end;
      k := coalesce(q->>'answer', q->>'correct', q->>'correct_answer', '');
      -- v4.0: lenient blank detection — empty string, "null", or whitespace counts as skipped
      if a is null or trim(a) = '' or lower(trim(a)) = 'null' then
        sc := sc + 1;
      elsif k <> '' and lower(trim(a)) = lower(trim(k)) then
        score := score + mark; cc := cc + 1;
      -- Letter ↔ text equivalence (MCQ answer key may be "A" or the option text)
      elsif jsonb_typeof(q->'options') = 'array' and jsonb_array_length(q->'options') > 0 then
        declare opts text[]; ai int; ok boolean := false;
        begin
          opts := array(select jsonb_array_elements_text(q->'options'));
          -- Convert given letter to text
          if length(a) = 1 and a >= 'A' and a <= 'Z' and (ascii(a) - 65) < array_length(opts,1) then
            if lower(opts[ascii(a) - 65 + 1]) = lower(k) then ok := true; end if;
          end if;
          -- Convert given text to letter
          if not ok then
            for ai in 1..array_length(opts,1) loop
              if lower(opts[ai]) = lower(a) and lower(opts[ai]) = lower(k) then ok := true; exit; end if;
            end loop;
          end if;
          if ok then score := score + mark; cc := cc + 1; else wc := wc + 1; end if;
        end;
      else
        wc := wc + 1;
      end if;
      i := i + 1;
    end loop;
  end;

  sid := nullif(p_payload->>'student_id','')::uuid;
  n := case when total>0 then round((score/total)*100)::int else 0 end;
  begin
    insert into public.cbt_results(
      exam_id,student_id,student_name,student_class,student_id_ref,student_type,
      score,total,percent,correct_count,wrong_count,skipped_count,
      attempt_number,time_taken,violations,violation_log,answers_data,cert_code,client_ref
    ) values (
      e.id,sid,coalesce(p_payload->>'student_name','Anonymous'),coalesce(p_payload->>'student_class',e.class),
      coalesce(p_payload->>'student_id_ref',''),coalesce(p_payload->>'student_type',e.exam_mode),
      score,total::int,n,cc,wc,sc,
      taken+1,coalesce((p_payload->>'time_taken')::int,0),coalesce((p_payload->>'violations')::int,0),
      coalesce(p_payload->'violation_log','[]'::jsonb),p_payload->'answers_data',
      case when e.certificate_enabled then 'CERT-'||upper(substr(md5(random()::text),1,8)) else '' end,
      ref
    ) returning id into rid;
  exception when unique_violation then
    select * into r from public.cbt_results where exam_id=e.id and client_ref=ref limit 1;
    if found then
      return jsonb_build_object('saved',true,'duplicate',true,'result_id',r.id,'score',r.score,'total',r.total,'percent',r.percent,
        'correct_count',r.correct_count,'wrong_count',r.wrong_count,'skipped_count',r.skipped_count,
        'cert_code',r.cert_code,'release_results',e.release_results,'report_column',e.report_column);
    end if;
    return jsonb_build_object('saved',false,'error','Duplicate submission conflict');
  end;
  return jsonb_build_object('saved',true,'result_id',rid,'score',score,'total',total,'percent',n,
    'correct_count',cc,'wrong_count',wc,'skipped_count',sc,'cert_code',
    (select cert_code from public.cbt_results where id=rid),
    'release_results',e.release_results,'report_column',e.report_column);
exception when others then
  return jsonb_build_object('saved',false,'error',sqlerrm,'detail',coalesce(e.code,'unknown exam'));
end $$;

-- cbt_submit_v1 (legacy) — same fix
DROP FUNCTION IF EXISTS public.cbt_submit() CASCADE;
create or replace function public.cbt_submit(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e record; rid uuid; sid uuid; n int; score numeric:=0; total numeric:=0; ans jsonb; q jsonb; a text; k text; mark numeric; i int:=0; orig_idx int; bank jsonb;
begin
  select * into e from public.cbt_exams where id=(p_payload->>'exam_id')::uuid;
  if not found then return jsonb_build_object('saved',false,'error','Exam not found'); end if;
  bank := case when jsonb_typeof(e.csv_data)='array' and jsonb_array_length(e.csv_data)>0 then e.csv_data
               when jsonb_typeof(e.questions)='array' and jsonb_array_length(e.questions)>0 then e.questions
               else '[]'::jsonb end;
  declare answers_by_orig jsonb := '{}'::jsonb; answers_by_idx jsonb := '{}'::jsonb;
  begin
    for ans in select * from jsonb_array_elements(coalesce(p_payload->'answers_data','[]'::jsonb)) loop
      if (ans ? 'index') and jsonb_typeof(ans->'index')='number' then
        answers_by_idx := answers_by_idx || jsonb_build_object((ans->>'index')::text, ans);
      end if;
      if (ans ? '_orig_index') and jsonb_typeof(ans->'_orig_index')='number' then
        answers_by_orig := answers_by_orig || jsonb_build_object((ans->>'_orig_index')::text, ans);
      end if;
    end loop;
    i := 0;
    for q in select * from jsonb_array_elements(bank) loop
      orig_idx := case when jsonb_typeof(q->'_orig_index')='number' then (q->>'_orig_index')::int else i end;
      if answers_by_orig ? (orig_idx)::text then ans := answers_by_orig -> (orig_idx)::text;
      elsif answers_by_idx ? (i)::text then ans := answers_by_idx -> (i)::text;
      else ans := null; end if;
      mark := coalesce(nullif(q->>'mark','')::numeric,1); total := total + mark;
      a := case when ans is null then '' else coalesce(ans->>'answer', ans #>> '{}', '') end;
      k := coalesce(q->>'answer', q->>'correct', q->>'correct_answer', '');
      if a is null or trim(a) = '' then
        -- v1 doesn't track skipped_count but won't count it as correct either
        null;
      elsif k <> '' and lower(trim(a)) = lower(trim(k)) then
        score := score + mark;
      end if;
      i := i + 1;
    end loop;
  end;
  sid := nullif(p_payload->>'student_id','')::uuid;
  n := case when total>0 then round((score/total)*100)::int else 0 end;
  insert into public.cbt_results(exam_id,student_id,student_name,student_class,student_id_ref,student_type,score,total,percent,answers_data,cert_code)
  values(e.id,sid,coalesce(p_payload->>'student_name','Anonymous'),coalesce(p_payload->>'student_class',e.class),coalesce(p_payload->>'student_id_ref',''),coalesce(p_payload->>'student_type',e.exam_mode),score,total::int,n,p_payload->'answers_data',case when e.certificate_enabled then 'CERT-'||upper(substr(md5(random()::text),1,8)) else '' end) returning id into rid;
  return jsonb_build_object('saved',true,'result_id',rid,'score',score,'total',total,'percent',n,'cert_code',(select cert_code from public.cbt_results where id=rid));
exception when others then return jsonb_build_object('saved',false,'error',sqlerrm);
end $$;

DROP FUNCTION IF EXISTS public.cbt_get_public_exam() CASCADE;
create or replace function public.cbt_get_public_exam(p_code text)
returns jsonb language plpgsql security definer stable set search_path=public as $$
declare e record; qs jsonb;
begin
  select * into e from public.cbt_exams where upper(code)=upper(trim(p_code)) and is_open=true and is_archived=false limit 1;
  if not found then return null; end if;
  if e.start_at is not null and now()<e.start_at then return jsonb_build_object('wait',true,'start_at',e.start_at,'title',e.title); end if;
  if e.close_at is not null and now()>e.close_at then return jsonb_build_object('closed',true); end if;
  select coalesce(jsonb_agg((q-'correct'-'correct_answer'-'answer'-'explanation')||jsonb_build_object('_orig_index',ord-1) order by ord),'[]'::jsonb) into qs from jsonb_array_elements((case when jsonb_typeof(e.csv_data)='array' and jsonb_array_length(e.csv_data)>0 then e.csv_data when jsonb_typeof(e.questions)='array' and jsonb_array_length(e.questions)>0 then e.questions else '[]'::jsonb end)) with ordinality x(q,ord);
  return jsonb_build_object('id',e.id,'code',e.code,'title',e.title,'subject',e.subject,'class',e.class,'term',e.term,'session',e.session,'duration',e.duration,'questions',qs,'_questions',qs,'report_column',e.report_column,'max_score',e.max_score,'exam_mode',e.exam_mode,
    'exam_school_name',coalesce(e.exam_school_name,''),'exam_school_motto',coalesce(e.exam_school_motto,''),'exam_school_address',coalesce(e.exam_school_address,''),'exam_school_phone',coalesce(e.exam_school_phone,''),'exam_school_email',coalesce(e.exam_school_email,''),'exam_school_logo_url',coalesce(e.exam_school_logo_url,''),'exam_header_html',coalesce(e.exam_header_html,''),'exam_watermark',coalesce(e.exam_watermark,''));
end $$;

DROP FUNCTION IF EXISTS public.sc_push_cbt_to_results() CASCADE;
create or replace function public.sc_push_cbt_to_results(p_exam_id uuid, p_column text default 'exam', p_term text default '', p_session text default '')
returns int language plpgsql security definer set search_path=public as $$
declare e record; r record; sid uuid; saved int:=0;
begin
 select * into e from public.cbt_exams where id=p_exam_id; if not found then return 0; end if;
 for r in select * from public.cbt_results where exam_id=p_exam_id loop
   sid := r.student_id;
   if sid is null then select id into sid from public.students where admission_no=r.student_id_ref or lower(full_name)=lower(r.student_name) limit 1; end if;
   insert into public.results(student_id,student_name,student_id_ref,subject,class,term,session,assessment_source,assessment_ref)
   values(sid,r.student_name,r.student_id_ref,coalesce(e.subject,'CBT'),coalesce(r.student_class,e.class),coalesce(nullif(p_term,''),e.term),coalesce(nullif(p_session,''),e.session),'cbt',r.id)
   on conflict (assessment_source,assessment_ref) do update set student_id=excluded.student_id,student_name=excluded.student_name,subject=excluded.subject,class=excluded.class,term=excluded.term,session=excluded.session;
   saved := saved+1;
 end loop; return saved;
end $$;

-- ============================================================================
-- v4.0 CBT INDEXES & CONSTRAINTS (idempotent CBT scale pack)
-- ============================================================================
create index if not exists cbt_exams_upper_code_idx on public.cbt_exams (upper(code));
create index if not exists cbt_results_exam_idx        on public.cbt_results (exam_id);
create index if not exists cbt_results_exam_time_idx   on public.cbt_results (exam_id, submitted_at desc);
create index if not exists cbt_results_student_ref_idx on public.cbt_results (exam_id, student_id_ref);
create unique index if not exists cbt_results_client_ref_uidx
  on public.cbt_results (exam_id, client_ref)
  where client_ref is not null and client_ref <> '';

-- v4.0 cumulative repair for `results` assessment uniqueness
do $$ begin
  if to_regclass('public.results') is not null then
    drop index if exists public.results_assessment_ref_unique;
    delete from public.results r
    using public.results newer
    where r.ctid < newer.ctid
      and r.assessment_ref is not null and newer.assessment_ref is not null
      and coalesce(r.assessment_source,'') = coalesce(newer.assessment_source,'')
      and r.assessment_ref = newer.assessment_ref;
    create unique index if not exists results_assessment_ref_unique on public.results(assessment_source, assessment_ref);
  end if;
end $$;

-- ============================================================================
-- v4.0 VIEWS
-- ============================================================================
create or replace view public.poll_results as
select p.id as poll_id, p.title,
       coalesce(sum(v.c), 0) as total_votes,
       coalesce(jsonb_agg(jsonb_build_object('candidate', v.candidate_id, 'votes', v.c))
                filter (where v.candidate_id is not null), '[]'::jsonb) as breakdown
from public.polls p
left join lateral (
  select candidate_id, count(*) as c from public.poll_votes where poll_id = p.id group by candidate_id
) v on true
group by p.id, p.title;

create or replace view public.report_subject_totals as
select rs.student_id, rs.student_name, rs.student_id_ref, rs.class, rs.subject, rs.term, rs.session,
       round(sum(rs.score),2) obtained, round(sum(ac.max_mark),2) obtainable,
       case when sum(ac.max_mark)>0 then round(sum(rs.score)/sum(ac.max_mark)*100,2) else 0 end percent
from public.report_scores rs join public.assessment_columns ac on ac.id=rs.column_id
group by rs.student_id,rs.student_name,rs.student_id_ref,rs.class,rs.subject,rs.term,rs.session;

create or replace view public.parent_children as select * from public.parent_child;

-- ============================================================================
-- v4.0 TRIGGERS
-- ============================================================================
drop trigger if exists trg_compute_fee_payment_balance on public.fee_payments;
create trigger trg_compute_fee_payment_balance
before insert or update of fee_total, amount_paid, balance on public.fee_payments
for each row execute function public.compute_fee_payment_balance();
drop trigger if exists trg_compute_payroll_net on public.payroll;
create trigger trg_compute_payroll_net
before insert or update of basic, allowances, bonus, overtime, tax, pension, loan_deduction, other_deductions, deductions on public.payroll
for each row execute function public.compute_payroll_net();
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();
drop trigger if exists trg_sc_generate_admission_no on public.students;
create trigger trg_sc_generate_admission_no before insert on public.students for each row execute function public.sc_generate_admission_no();
drop trigger if exists trg_sc_generate_staff_no on public.staff;
create trigger trg_sc_generate_staff_no before insert on public.staff for each row execute function public.sc_generate_staff_no();

-- ============================================================================
-- v4.0 RLS POLICIES — the same matrix used in the v12.5 build, retained
-- for cumulative compat. Abridged here — see DEPLOYMENT-GUIDE.md for full
-- reference. All key tables have at minimum read = authenticated, write =
-- staff/admin. Family-safe where applicable.
-- ============================================================================
do $$ declare t text; begin
  foreach t in array ARRAY[
    'students','staff','classes','subjects','timetable','scheme_of_work','assignments',
    'library','fee_structures','events','gallery','eresources','birthdays','idcards',
    'departments','admissions','hostel_allocations','alumni','inventory','certificates',
    'lms_courses','lms_lessons','lesson_plans','behaviour_points','substitutions','donations',
    'parent_meetings','career_counseling','financial_aid','gamification_points'
  ] loop
    execute format('drop policy if exists "read_%s"  on public.%I', t, t);
    execute format('drop policy if exists "write_%s" on public.%I', t, t);
    execute format('create policy "read_%s"  on public.%I for select using (auth.role() = ''authenticated'')', t, t);
    execute format('create policy "write_%s" on public.%I for all    using (public.is_staff(auth.uid()))', t, t);
  end loop;
end $$;

-- Core family-safe policies
drop policy if exists "read_students" on students;
create policy "read_students" on public.students for select using (
  public.is_staff(auth.uid()) or user_id = auth.uid() or public.is_parent_of(auth.uid(), id)
);
drop policy if exists "write_students" on students;
create policy "write_students" on public.students for all using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));

drop policy if exists "read_results" on results;
create policy "read_results" on public.results for select using (
  public.is_staff(auth.uid()) or public.is_parent_of(auth.uid(), student_id) or student_id in (select id from public.students where user_id = auth.uid())
);
drop policy if exists "write_results" on results;
create policy "write_results" on public.results for all using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));

drop policy if exists "read_attendance" on attendance;
create policy "read_attendance" on public.attendance for select using (
  public.is_staff(auth.uid()) or exists(select 1 from public.students s where s.id=attendance.student_id and (s.user_id=auth.uid() or public.is_parent_of(auth.uid(),s.id)))
);
drop policy if exists "write_attendance" on attendance;
create policy "write_attendance" on public.attendance for all using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));

drop policy if exists "read_assignments" on assignments;
create policy "read_assignments" on public.assignments for select using (
  public.is_staff(auth.uid())
  or class in (select class from public.students where user_id = auth.uid())
  or class in (select class from public.students s join public.parent_child pc on pc.student_id=s.id where pc.parent_id=auth.uid())
);
drop policy if exists "write_assignments" on assignments;
create policy "write_assignments" on public.assignments for all using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));

drop policy if exists "read_polls" on polls;
create policy "read_polls" on public.polls for select using (auth.role() = 'authenticated');
drop policy if exists "write_polls" on polls;
create policy "write_polls" on public.polls for all using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));
drop policy if exists "read_pv" on poll_votes;
create policy "read_pv" on public.poll_votes for select using (auth.uid() = voter_id or public.is_staff(auth.uid()));
drop policy if exists "insert_pv" on poll_votes;
create policy "insert_pv" on public.poll_votes for insert with check (auth.uid() = voter_id);

drop policy if exists "read_settings" on school_settings;
create policy "read_settings" on public.school_settings for select using (auth.role() = 'authenticated');
drop policy if exists "write_settings" on school_settings;
create policy "write_settings" on public.school_settings for all using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

drop policy if exists "read_schools" on schools;
create policy "read_schools" on public.schools for select using (auth.role() = 'authenticated');
drop policy if exists "write_schools" on schools;
create policy "write_schools" on public.schools for all using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

drop policy if exists "read_fee_structure" on class_fee_structure;
create policy "read_fee_structure" on public.class_fee_structure for select using (auth.role() = 'authenticated');
drop policy if exists "write_fee_structure" on class_fee_structure;
create policy "write_fee_structure" on public.class_fee_structure for all using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

drop policy if exists "read_notifications" on notifications;
create policy "read_notifications" on public.notifications for select using (auth.role() = 'authenticated');
drop policy if exists "write_notifications" on notifications;
create policy "write_notifications" on public.notifications for all using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));

drop policy if exists "ps_all" on push_subscriptions;
create policy "ps_all" on public.push_subscriptions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- CBT results: students can read their own; staff read all
drop policy if exists "read_cbt_results" on cbt_results;
create policy "read_cbt_results" on public.cbt_results for select using (
  public.is_staff(auth.uid())
  or student_id_ref = (select admission_no from public.students where user_id = auth.uid() limit 1)
  or student_id in (select id from public.students where user_id = auth.uid())
  or student_id in (select student_id from public.parent_child where parent_id = auth.uid())
);
-- Anonymous CBT (student_id_ref only): anyone can read the public cert code
drop policy if exists "anon_read_cbt_results" on cbt_results;
create policy "anon_read_cbt_results" on public.cbt_results for select using (auth.role() = 'anon' or auth.role() = 'authenticated');
drop policy if exists "anon_insert_cbt_results" on cbt_results;
create policy "anon_insert_cbt_results" on public.cbt_results for insert with check (true);

drop policy if exists "read_cbt_exams" on cbt_exams;
create policy "read_cbt_exams" on public.cbt_exams for select using (auth.role() = 'authenticated' or auth.role() = 'anon');
drop policy if exists "write_cbt_exams" on cbt_exams;
create policy "write_cbt_exams" on public.cbt_exams for all using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));

-- Profiles self-service
drop policy if exists "profiles_self_read" on profiles;
create policy "profiles_self_read"   on public.profiles for select using (auth.uid() = id);
drop policy if exists "profiles_self_update" on profiles;
create policy "profiles_self_update" on public.profiles for update using (auth.uid() = id);
drop policy if exists "profiles_staff_read" on profiles;
create policy "profiles_staff_read"  on public.profiles for select using (public.is_staff(auth.uid()));
drop policy if exists "profiles_admin_all" on profiles;
create policy "profiles_admin_all"   on public.profiles for all    using (public.is_admin(auth.uid()));

-- ============================================================================
-- v4.0 GRANTS
-- ============================================================================
grant execute on function public.verify_certificate(text) to anon, authenticated;
grant execute on function public.sc_push_cbt_to_results(uuid,text,text,text) to authenticated;
grant execute on function public.cbt_get_public_exam(text) to anon, authenticated;
grant execute on function public.cbt_get_public_exam_v2(text) to anon, authenticated;
grant execute on function public.cbt_submit(jsonb) to anon, authenticated;
grant execute on function public.cbt_submit_v2(jsonb) to anon, authenticated;
grant execute on function public.generate_timetable(text,text,text,int) to authenticated;
grant select on public.parent_children to authenticated;

-- ============================================================================
-- v4.0 SEED: school singleton + base lookups
-- ============================================================================
insert into public.schools (name, short_name, admission_acronym) values ('My School','SCH','SCH') on conflict do nothing;
insert into public.school_settings (id, school_id, school_name, short_name, admission_acronym, admission_prefix, staff_prefix)
select 1, s.id, s.name, s.short_name, s.admission_acronym, s.admission_acronym, s.admission_acronym
from public.schools s order by s.created_at limit 1 on conflict (id) do nothing;
insert into public.lookups(kind,value,position) values
 ('term','First Term',1),('term','Second Term',2),('term','Third Term',3),
 ('session','2024/2025',1),('session','2025/2026',2),('session','2026/2027',3),
 ('arm','A',1),('arm','B',2),('arm','C',3),
 ('assessment','CA1',1),('assessment','CA2',2),('assessment','Assignment',3),('assessment','Project',4),('assessment','Exam',5),
 ('audience','all',1),('audience','students',2),('audience','staff',3),('audience','parents',4)
on conflict(kind,value) do nothing;
insert into public.school_settings (id) values (1) on conflict (id) do nothing;

-- Site license row (default lifetime)
create table if not exists public.site_license (
  id smallint primary key default 1 check (id = 1),
  model text not null default 'lifetime' check (model in ('lifetime','subscription')),
  plan text not null default 'One-time purchase (lifetime ownership)',
  cycle text not null default '', started_on date default current_date,
  expires_on date, grace_days int not null default 7,
  status text not null default 'active' check (status in ('active','suspended')),
  renew_url text not null default '', lock_message text not null default '',
  signature text not null default '',
  updated_at timestamptz not null default now()
);
insert into public.site_license (id, model, plan, cycle, started_on, expires_on, grace_days, status, renew_url, lock_message, signature)
values (1, 'lifetime', 'One-time purchase (lifetime ownership)', '', current_date, null, 7, 'active', '', '', '')
on conflict (id) do nothing;
alter table public.site_license enable row level security;
drop policy if exists "site_license_read" on public.site_license;
create policy "site_license_read" on public.site_license for select using (true);
drop policy if exists "site_license_write" on public.site_license;
create policy "site_license_write" on public.site_license for all using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- ============================================================================
-- v4.0 PUNCTUALITY (v12.4 carried forward, idempotent)
-- ============================================================================
create table if not exists public.punctuality_config (
  id int primary key default 1 check (id = 1),
  deadline time not null default '07:30:00',
  checkout_open time not null default '12:30:00',
  points_full numeric not null default 2, points_partial numeric not null default 0,
  require_checkout boolean not null default true, enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.punctuality_config (id) values (1) on conflict (id) do nothing;
create table if not exists public.punctuality_awards (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  student_id_ref text not null default '', student_name text not null default '',
  class text not null default '', date date not null,
  checkin_at timestamptz, checkout_at timestamptz,
  points numeric not null default 0, rule text not null default 'none',
  created_at timestamptz not null default now(), unique(student_id, date)
);
create index if not exists punctuality_awards_date_idx on public.punctuality_awards (date);
create index if not exists punctuality_awards_class_idx on public.punctuality_awards (class, date);
alter table public.punctuality_config enable row level security;
alter table public.punctuality_awards enable row level security;
drop policy if exists "punctuality_config_read" on public.punctuality_config;
create policy "punctuality_config_read" on public.punctuality_config for select using (auth.role()='authenticated');
drop policy if exists "punctuality_config_write" on public.punctuality_config;
create policy "punctuality_config_write" on public.punctuality_config for all using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));
drop policy if exists "punctuality_awards_read" on public.punctuality_awards;
create policy "punctuality_awards_read" on public.punctuality_awards for select using (
  public.is_staff(auth.uid()) or public.is_parent_of(auth.uid(), student_id)
  or exists (select 1 from public.students s where s.id = punctuality_awards.student_id and s.user_id = auth.uid()));
drop policy if exists "punctuality_awards_write" on public.punctuality_awards;
create policy "punctuality_awards_write" on public.punctuality_awards for all using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));

-- ============================================================================
-- v4.0: PostgREST cache reload
-- ============================================================================
notify pgrst, 'reload schema';
select pg_notify('pgrst','reload schema');
select 'School Connect v4.0 schema installed successfully ✅ — alumni column fixed, CBT zero-marks bug fixed, exam-page school header supported.' as status;
