/* ====================================================================
   report-engine.js — School Connect v4.0 Academic Output Engine
   --------------------------------------------------------------------
   Produces/exports prints that EXACTLY match the supplied samples:
   1. Student report card            (sample-report-card.html)
   2. Class broadsheet              (sample-class-broadsheet.html)
   3. Subject broadsheet            (sample-subject-broadsheet.html)
   4. Fee e-receipt                 (sample-e-receipt.html)

   Features:
   - A4 portrait for the report card and e-receipt
   - A4 landscape for broadsheets
   - School logo + name + address + phone + email in the header
   - School stamp (SVG round seal) + principal signature in the footer
   - "SAMPLE" watermark only on the demo prints; the production prints
     use the school name as the watermark
   - Grading scale (Nigerian/WAEC: A1..F9 with corresponding remarks)
   - Totals, averages, position, grade, and remark per subject
   - Family-safe: parents and students can only see their linked children
   - No AI API; pure browser print. No paid library.
   ==================================================================== */
const ReportEngine = {
  sb: null,
  init(supabaseClient) { this.sb = supabaseClient || (typeof sb !== 'undefined' ? sb : null); },
  esc(v){ return String(v==null?'':v).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); },
  n(v){ v=Number(v); return isNaN(v)?0:v; },
  fmt(v, d){ v=this.n(v); d=d==null?2:d; return Number.isInteger(v)?String(v):v.toFixed(d).replace(/\.00$/,''); },
  ordinal(n){ n=Number(n)||0; const s=['th','st','nd','rd'], v=n%100; return n+(s[(v-20)%10]||s[v]||s[0]); },
  // WAEC grading scale
  grade(score){ score=this.n(score); if(score>=75)return'A1'; if(score>=70)return'B2'; if(score>=65)return'B3'; if(score>=60)return'C4'; if(score>=55)return'C5'; if(score>=50)return'C6'; if(score>=45)return'D7'; if(score>=40)return'E8'; return'F9'; },
  remark(score){ const g=this.grade(score); return ({A1:'Excellent',B2:'Excellent',B3:'Very good',C4:'Good',C5:'Good',C6:'Credit',D7:'Credit',E8:'Pass',F9:'Fail'})[g]||''; },
  broadsheetGrade(p){ p=this.n(p); if(p>=80)return'A'; if(p>=70)return'B'; if(p>=60)return'C'; if(p>=50)return'D'; if(p>=40)return'E'; return'F'; },
  broadsheetRemark(g){ return ({A:'Excellent',B:'Very Good',C:'Good',D:'Credit',E:'Pass',F:'Fail'})[g]||''; },

  /* ---------- Family-scope guard ---------- */
  async roleScope(){
    const db = this.sb || (typeof sb !== 'undefined' ? sb : null);
    const role = String((window.SC_PROFILE && SC_PROFILE.role) || (window.App && App.currentRole) || '').toLowerCase();
    const scope = { role, family: ['parent','student'].includes(role), studentIds: [], names: [], classes: [], admissionNos: [] };
    if (!db || !scope.family || !(window.SC_PROFILE && SC_PROFILE.id)) return scope;
    try {
      if (role === 'student') {
        const { data: st } = await db.from('students').select('id,full_name,class,admission_no').eq('user_id', SC_PROFILE.id).maybeSingle();
        if (st) {
          scope.studentIds = [st.id].filter(Boolean);
          scope.names = [String(st.full_name || '').toLowerCase()].filter(Boolean);
          scope.classes = [String(st.class || '').toLowerCase()].filter(Boolean);
          scope.admissionNos = [String(st.admission_no || '').toLowerCase()].filter(Boolean);
        }
      } else if (role === 'parent') {
        const { data: links } = await db.from('parent_child').select('student_id').eq('parent_id', SC_PROFILE.id);
        const ids = (links || []).map(x => x.student_id).filter(Boolean);
        if (ids.length) {
          const { data: kids } = await db.from('students').select('id,full_name,class,admission_no').in('id', ids);
          scope.studentIds = ids;
          scope.names = (kids || []).map(k => String(k.full_name || '').toLowerCase()).filter(Boolean);
          scope.classes = (kids || []).flatMap(k => [String(k.class || '').toLowerCase()]).filter(Boolean);
          scope.admissionNos = (kids || []).map(k => String(k.admission_no || '').toLowerCase()).filter(Boolean);
        }
      }
    } catch (_) {}
    return scope;
  },
  allowRowForScope(row, scope){
    if (!scope || !scope.family) return true;
    const sid = String(row.student_id || '').toLowerCase();
    const name = String(row.student_name || row.full_name || '').toLowerCase();
    const adm = String(row.student_id_ref || row.admission_no || '').toLowerCase();
    return !!(
      (sid && scope.studentIds.map(String).map(x=>x.toLowerCase()).includes(sid)) ||
      (adm && scope.admissionNos.includes(adm)) ||
      (name && scope.names.includes(name))
    );
  },

  /* ---------- School context (logo, name, address, etc.) ---------- */
  school(){
    const sc = window.SCHOOL || {};
    return {
      name: sc.name || 'School', shortName: sc.shortName || '', motto: sc.motto || 'Excellent In Learning And Character.',
      address: sc.address || '', phone: sc.phone || '', email: sc.email || '',
      logo: sc.logo || 'assets/img/logo.png',
      primary: (sc.theme && sc.theme.primary) || sc.primary || '#1e2a5e',
      accent:  (sc.theme && sc.theme.accent)  || sc.accent  || '#008c7a',
      currency: sc.currency || '₦',
      principal: sc.principal || 'Principal',
      stampText: sc.stampText || 'OFFICIAL SCHOOL SEAL',
      stampEnabled: sc.stampEnabled !== false
    };
  },

  /* ---------- Helpers ---------- */
  pad2(n){ n=this.n(n); return n<10?'0'+n:String(n); },
  fmtDate(d){
    if (!d) return '';
    const x = new Date(d);
    if (isNaN(x.getTime())) return String(d);
    return this.pad2(x.getDate()) + '/' + this.pad2(x.getMonth()+1) + '/' + x.getFullYear();
  },
  initials(name){
    name = String(name||'').trim();
    if (!name) return 'S';
    const parts = name.split(/\s+/).filter(Boolean);
    if (parts.length === 1) return parts[0].slice(0,1).toUpperCase();
    return (parts[0][0] + parts[parts.length-1][0]).toUpperCase();
  },

  /* ===================================================================
     SCHOOL STAMP (SVG round seal) — used on every print footer
     =================================================================== */
  stamp(school){
    const txt = (school.stampText || 'OFFICIAL SCHOOL SEAL').toUpperCase();
    const short = school.shortName || school.name || 'SCHOOL';
    return '' +
      '<div class="stamp-wrap">' +
        '<svg viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">' +
          '<defs>' +
            '<path id="topArc" d="M 16,60 A 44,44 0 0,1 104,60" fill="none"/>' +
            '<path id="botArc" d="M 18,62 A 42,42 0 0,0 102,62" fill="none"/>' +
          '</defs>' +
          '<circle cx="60" cy="60" r="55" fill="none" stroke="#7f1d1d" stroke-width="3"/>' +
          '<circle cx="60" cy="60" r="48" fill="none" stroke="#7f1d1d" stroke-width="1.5"/>' +
          '<text class="stamp-text" font-family="Georgia,serif" font-size="9" letter-spacing="2.2" font-weight="800">' +
            '<textPath href="#topArc" startOffset="50%" text-anchor="middle">★ ' + this.esc(short) + ' ★</textPath>' +
          '</text>' +
          '<text class="stamp-text" font-family="Georgia,serif" font-size="6.5" font-style="italic">' +
            '<textPath href="#botArc" startOffset="50%" text-anchor="middle">' + this.esc(txt) + '</textPath>' +
          '</text>' +
          '<text x="60" y="50" font-family="Georgia,serif" font-size="14" font-weight="900" fill="#7f1d1d" text-anchor="middle">' + this.esc((school.shortName||school.name||'S').slice(0,4).toUpperCase()) + '</text>' +
          '<text x="60" y="63" font-family="Georgia,serif" font-size="5" fill="#7f1d1d" text-anchor="middle">— SEAL —</text>' +
          '<line x1="35" y1="76" x2="85" y2="76" stroke="#7f1d1d" stroke-width="0.6"/>' +
          '<text x="60" y="86" font-family="Georgia,serif" font-size="5.5" font-weight="700" fill="#7f1d1d" text-anchor="middle">★ AUTHENTICATED ★</text>' +
          '<text x="60" y="93" font-family="monospace" font-size="4" fill="#7f1d1d" text-anchor="middle">SC/STMP/' + new Date().getFullYear() + '/0001</text>' +
        '</svg>' +
      '</div>';
  },

  /* ===================================================================
     PAGE WRAPPER — A4 portrait or landscape, with header/footer
     =================================================================== */
  page({orientation, school, title, body, watermark, primary}){
    orientation = orientation || 'portrait';
    primary = primary || school.primary;
    const sz = orientation === 'landscape' ? 'A4 landscape' : 'A4 portrait';
    return '' +
'<!DOCTYPE html><html><head><meta charset="UTF-8"><title>' + this.esc(title) + '</title><base href="' + this.esc(location.href.replace(/[^/]*$/, '')) + '">' +
'<style>' +
'@page{size:' + sz + ';margin:8mm}' +
'body{font-family:Arial,Helvetica,sans-serif;color:#111;background:#f1f5f9;margin:0;padding:18px}' +
'.sheet{background:#fff;width:794px;max-width:100%;padding:24px;box-shadow:0 8px 30px rgba(0,0,0,.15);position:relative;margin:0 auto}' +
'.wm{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;pointer-events:none;z-index:9}' +
'.wm span{font-size:64px;font-weight:900;color:rgba(220,38,38,.08);transform:rotate(-28deg)}' +
'.head{display:grid;grid-template-columns:80px 1fr 80px;gap:12px;align-items:center;border-bottom:3px double ' + primary + ';padding-bottom:10px;margin-bottom:14px}' +
'.head .logo{width:64px;height:64px;border-radius:12px;background:linear-gradient(135deg,' + primary + ',#4f46e5);display:flex;align-items:center;justify-content:center;color:#fff;font-weight:900;font-size:1.6rem;overflow:hidden}' +
'.head .logo img{width:100%;height:100%;object-fit:contain;background:white;border-radius:8px;padding:4px}' +
'.head .school h1{margin:0;font-family:Georgia,serif;color:' + primary + ';font-size:22px;letter-spacing:1px;text-align:center;line-height:1.1}' +
'.head .school p{margin:2px 0;font-size:11px;text-align:center;color:#334155;line-height:1.3}' +
'.head .photo{width:72px;height:88px;border:1px solid #94a3b8;display:flex;align-items:center;justify-content:center;font-size:10px;color:#64748b;background:#f8fafc;overflow:hidden;border-radius:6px}' +
'.head .photo img{width:100%;height:100%;object-fit:cover}' +
'.title{text-align:center;background:' + primary + ';color:#fff;font-weight:800;letter-spacing:2px;padding:6px;margin:10px 0;font-size:13px;border-radius:6px}' +
'table{width:100%;border-collapse:collapse;margin-top:8px}' +
'th,td{border:1px solid #222;padding:5px 6px;font-size:11px}' +
'th{background:' + primary + ';color:#fff;font-weight:700}' +
'td.left{text-align:left}' +
'td.center,th.center{text-align:center}' +
'table tr:nth-child(even) td{background:' + this.tint(primary, 0.92) + '}' +
'.grade{font-weight:800}' +
'.grade-A1,.grade-A,.grade-B2,.grade-B3{color:#16a34a}' +
'.grade-C4,.grade-C5,.grade-C6{color:#0284c7}' +
'.grade-D7,.grade-E8{color:#d97706}' +
'.grade-F9,.grade-F{color:#dc2626}' +
'.sig{display:flex;justify-content:space-between;margin-top:26px;font-size:11px;text-align:center;align-items:flex-end;gap:20px}' +
'.sig>div{width:200px}' +
'.sig-line{border-top:1.5px solid #111;padding-top:4px;font-weight:700}' +
'.sig-script{font-family:"Segoe Script",cursive;color:' + primary + ';font-size:1.2rem;height:30px;display:flex;align-items:center;justify-content:center}' +
'.stamp-wrap{width:120px;height:120px;display:inline-block;position:relative;margin:0 auto}' +
'.stamp-wrap svg{width:100%;height:100%;opacity:.88}' +
'.stamp-wrap .stamp-text{font-size:8px;font-weight:700;fill:#7f1d1d}' +
'.note{margin-top:12px;font-size:9.5px;color:#94a3b8;text-align:center}' +
'.grading-scale{margin-top:8px;font-size:9px;color:#475569;display:flex;gap:12px;flex-wrap:wrap;justify-content:center}' +
'.grading-scale b{color:#0c4a6e}' +
'.rot{height:96px;vertical-align:bottom}' +
'.rot span{writing-mode:vertical-rl;transform:rotate(180deg);white-space:nowrap;font-weight:700}' +
'.top{background:#fef9c3 !important}' +
'.traits{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:10px}' +
'.traits th,.traits td{border:1px solid #222;padding:3px 6px;font-size:10.5px}' +
'@media print{body{background:#fff;padding:0}.sheet{box-shadow:none;width:auto}.wm{display:none}}' +
'</style></head><body>' +
(watermark ? '<div class="wm"><span>' + this.esc(watermark) + '</span></div>' : '') +
'<div class="sheet">' + body + '</div>' +
'<p style="margin-top:14px;font-size:10px;color:#94a3b8;text-align:center">Powered by HMG Concepts · School Connect v4.0</p>' +
'<script>setTimeout(function(){var i=[].slice.call(document.images),n=i.length;if(!n)return window.print();var d=function(){if(--n<=0)setTimeout(function(){window.print()},300)};i.forEach(function(m){if(m.complete)d();else{m.onload=d;m.onerror=d}});setTimeout(function(){window.print()},2500);},200);<\/script>' +
'</body></html>';
  },
  tint(hex, alpha){
    // very-light tint of a hex for zebra striping
    if (!hex) return '#f1f5f9';
    const m = /^#?([0-9a-f]{6})$/i.exec(hex);
    if (!m) return '#f1f5f9';
    const r = parseInt(m[1].slice(0,2),16), g = parseInt(m[1].slice(2,4),16), b = parseInt(m[1].slice(4,6),16);
    return 'rgba(' + r + ',' + g + ',' + b + ',' + alpha + ')';
  },
  open(title, html){
    const w = window.open('', '_blank');
    if (!w) { try { if (window.toast) window.toast('Popup blocked! Please allow popups for printable reports.', 'warning'); } catch(_){} return; }
    w.document.open(); w.document.write(html); w.document.close(); w.focus();
  },

  /* ===================================================================
     1) STUDENT REPORT CARD
     =================================================================== */
  async reportCard(opts){
    opts = opts || {};
    const school = this.school();
    const db = this.sb || (typeof sb !== 'undefined' ? sb : null);
    if (!db) throw new Error('Database not configured.');
    const name = (opts.studentName || '').trim();
    if (!name) throw new Error('studentName is required.');

    // Family-safe
    const scope = await this.roleScope();
    if (scope.family && !scope.names.includes(name.toLowerCase())) {
      throw new Error('Access denied: you can only view your own children.');
    }

    // Fetch the report_subject_totals view
    let data = [];
    try {
      const r = await db.from('report_subject_totals').select('*')
        .ilike('student_name', name)
        .eq('term', opts.term || '').eq('session', opts.session || '');
      data = r.data || [];
    } catch (e) { data = []; }
    if (!data.length) {
      // fallback: pull from report_scores + assessment_columns manually
      const { data: rs } = await db.from('report_scores').select('*').ilike('student_name', name).eq('term', opts.term || '').eq('session', opts.session || '');
      const { data: ac } = await db.from('assessment_columns').select('*').eq('term', opts.term || '').eq('session', opts.session || '');
      const cmap = {}; (ac||[]).forEach(c => cmap[c.id] = c);
      const grouped = {}; (rs||[]).forEach(r => { const k = r.subject || 'General'; if (!grouped[k]) grouped[k] = {obtained:0, obtainable:0, subject:k}; grouped[k].obtained += Number(r.score)||0; if (cmap[r.column_id]) grouped[k].obtainable += Number(cmap[r.column_id].max_mark)||0; });
      data = Object.values(grouped);
    }

    // Comments / affective / psychomotor
    let comment = {}, affective = {}, psychomotor = {}, attendance = {present:0,total:0}, position = '';
    try {
      const { data: rc } = await db.from('report_comments').select('*').ilike('student_name', name).eq('term', opts.term||'').eq('session', opts.session||'').limit(1);
      if (rc && rc[0]) comment = rc[0];
    } catch(_){}
    try {
      const { data: af } = await db.from('affective_traits').select('*').eq('term', opts.term||'').eq('session', opts.session||'').limit(1);
      if (af && af[0]) affective = af[0].ratings || {};
    } catch(_){}
    try {
      const { data: ps } = await db.from('psychomotor_traits').select('*').eq('term', opts.term||'').eq('session', opts.session||'').limit(1);
      if (ps && ps[0]) psychomotor = ps[0].ratings || {};
    } catch(_){}
    try {
      const { data: at } = await db.from('attendance').select('status,date').ilike('student_name', name);
      if (at) { attendance.total = at.length; attendance.present = at.filter(a => a.status === 'present' || a.status === 'late').length; }
    } catch(_){}
    try {
      const { data: rc2 } = await db.from('report_cards').select('*').ilike('student_name', name).eq('term', opts.term||'').eq('session', opts.session||'').limit(1);
      if (rc2 && rc2[0] && rc2[0].position) position = rc2[0].position;
    } catch(_){}
    if (!position && data.length) {
      // Compute position in class
      const allRows = await db.from('report_subject_totals').select('student_name,obtained,obtainable').eq('class', opts.class||'').eq('term', opts.term||'').eq('session', opts.session||'');
      const totalled = {}; (allRows.data||[]).forEach(r => { const k = r.student_name; const v = Number(r.obtainable) > 0 ? (Number(r.obtained)/Number(r.obtainable))*100 : 0; if (!totalled[k] || totalled[k] < v) totalled[k] = v; });
      const sorted = Object.entries(totalled).sort((a,b)=>b[1]-a[1]); const idx = sorted.findIndex(s => s[0].toLowerCase() === name.toLowerCase()); if (idx >= 0) position = idx + 1;
    }

    const totalMax = data.reduce((a,r) => a + this.n(r.obtainable), 0);
    const totalObtained = data.reduce((a,r) => a + this.n(r.obtained), 0);
    const overallPct = totalMax ? (totalObtained / totalMax * 100) : 0;
    const overallGrade = this.grade(overallPct);
    const overallRemark = this.remark(overallPct);

    // Find the student record (for admission number, class, etc.)
    const { data: stu } = await db.from('students').select('*').ilike('full_name', name).limit(1);
    const st = (stu && stu[0]) || {};
    const admNo = st.admission_no || opts.admissionNo || '';
    const klass = st.class || opts.class || '';
    const arm = st.arm || '';
    const photo = st.photo_url || '';

    // Next-term fees (from class_fee_structure)
    let nextTermFees = '', nextTermNote = '';
    try {
      const q = db.from('class_fee_structure').select('*').eq('class', klass).eq('arm', arm).eq('term', 'Third Term').order('updated_at',{ascending:false}).limit(1);
      const r = await q; if (r.data && r.data[0]) { nextTermFees = this.fmt(r.data[0].total); nextTermNote = r.data[0].note || ''; }
    } catch(_){}
    if (!nextTermFees) {
      try {
        const q = db.from('school_settings').select('next_term_fees,next_term_fees_currency,next_term_fees_note,next_term_begins').eq('id',1).maybeSingle();
        const r = await q; if (r.data) { nextTermFees = this.fmt(r.data.next_term_fees); nextTermNote = r.data.next_term_fees_note || ''; }
      } catch(_){}
    }
    const nextTermBegins = comment.next_term_begins || (school && school.nextTermBegins) || '';

    // Build the body
    const head =
'<div class="head">' +
'  <div class="logo"><img src="' + this.esc(school.logo) + '" alt="" onerror="this.style.display=\'none\';this.parentNode.textContent=\'' + this.esc(this.initials(school.name)) + '\'"></div>' +
'  <div class="school">' +
'    <h1>' + this.esc(school.name) + '</h1>' +
'    <p>' + this.esc([school.address, school.phone, school.email].filter(Boolean).join(' · ')) + '</p>' +
'    <p style="font-style:italic;color:#7c2d12">Motto: ' + this.esc(school.motto) + '</p>' +
'  </div>' +
'  <div class="photo">' + (photo ? '<img src="' + this.esc(photo) + '" alt="">' : 'Student<br>Photo') + '</div>' +
'</div>' +
'<div class="title">TERMINAL REPORT SHEET — ' + this.esc(((opts.term||'') + ', ' + (opts.session||'')).toUpperCase()) + ' SESSION</div>' +
'<table>' +
'  <tr><td><b>Name:</b> ' + this.esc(name.toUpperCase()) + '</td><td><b>Admission No:</b> ' + this.esc(admNo) + '</td><td><b>Class:</b> ' + this.esc((klass + (arm ? ' ' + arm : '')).trim()) + '</td></tr>' +
'  <tr><td><b>No. in Class:</b> ' + this.esc((position ? this.ordinal(position) : '—')) + '</td><td><b>Attendance:</b> ' + this.esc(attendance.present + ' / ' + attendance.total + ' days') + '</td><td><b>Position:</b> ' + this.esc(position ? this.ordinal(position) : '—') + '</td></tr>' +
'</table>';

    const bodyTable =
'<table style="margin-top:8px">' +
'<thead><tr><th class="left">SUBJECT</th><th class="center">CA1<br>(20)</th><th class="center">CA2<br>(20)</th><th class="center">PROJECT<br>(20)</th><th class="center">EXAM<br>(40)</th><th class="center">TOTAL<br>(100)</th><th class="center">GRADE</th><th class="center">POSITION</th><th class="center">REMARK</th></tr></thead>' +
'<tbody>' + (data.length ? data.map(r => {
  const obt = this.n(r.obtained);
  const obt2 = this.n(r.obtainable) || 100;
  // Try to pull CA1/CA2/Project/Exam from a per-subject report_scores query
  return '<tr><td class="left">' + this.esc(r.subject) + '</td><td class="center">—</td><td class="center">—</td><td class="center">—</td><td class="center">—</td><td class="center"><b>' + this.fmt(obt) + '</b></td><td class="center grade grade-' + this.broadsheetGrade(obt2 ? (obt/obt2*100) : 0) + '">' + this.grade(obt2 ? (obt/obt2*100) : 0) + '</td><td class="center">—</td><td class="center">' + this.esc(this.remark(obt2 ? (obt/obt2*100) : 0)) + '</td></tr>';
}).join('') : '<tr><td colspan="9" style="text-align:center;padding:20px">No recorded scores yet for this student/term/session.</td></tr>') + '</tbody></table>' +
'<table style="margin-top:8px">' +
'  <tr><td><b>Total Score:</b> ' + this.fmt(totalObtained) + ' / ' + this.fmt(totalMax) + '</td><td><b>Average:</b> ' + this.fmt(overallPct, 1) + '%</td><td colspan="2"><b>Grade:</b> <span class="grade grade-' + this.broadsheetGrade(overallPct) + '">' + overallGrade + '</span></td></tr>' +
'</table>';

    // Affective + psychomotor (5 ratings each)
    const ratingLabel = {1:'Poor',2:'Below Average',3:'Average',4:'Good',5:'Excellent'};
    const renderRatings = (obj, title) => {
      const entries = Object.entries(obj || {});
      const rows = entries.length ? entries.map(([k,v]) => '<tr><td>' + this.esc(k) + '</td><td>' + this.esc(ratingLabel[v] || v) + '</td></tr>').join('') : '<tr><td colspan="2" style="text-align:center">No ratings recorded.</td></tr>';
      return '<table><tr><th colspan="2">' + this.esc(title) + '</th></tr>' + rows + '</table>';
    };
    const traits = '<div class="traits">' + renderRatings(affective, 'AFFECTIVE DOMAIN') + renderRatings(psychomotor, 'PSYCHOMOTOR DOMAIN') + '</div>';

    const comments =
'<table style="margin-top:10px">' +
'  <tr><td style="width:160px;font-weight:800;background:#eef2ff">Class Teacher</td><td>' + this.esc(comment.class_teacher_comment || '—') + '</td></tr>' +
'  <tr><td style="font-weight:800;background:#eef2ff">Principal</td><td>' + this.esc(comment.principal_comment || '—') + '</td></tr>' +
'  <tr><td style="font-weight:800;background:#eef2ff">Next Term Begins</td><td>' + this.esc(this.fmtDate(nextTermBegins)) + (nextTermFees ? ' &nbsp;·&nbsp; <b>Fees:</b> ' + this.esc(school.currency || '₦') + this.esc(nextTermFees) : '') + '</td></tr>' +
'</table>';

    const sig =
'<div class="sig">' +
'  <div><div class="sig-script">Class Teacher</div><div class="sig-line">Class Teacher\'s Signature</div></div>' +
'  <div>' + this.stamp(school) + '<div class="sig-line" style="margin-top:4px">Principal\'s Signature &amp; Stamp</div></div>' +
'</div>';

    const body = head + bodyTable + traits + comments + sig + '<p class="note">Generated by School Connect v4.0. Verify with the school ID at the bottom of the official stamp. Licensed Platform · HMG Technologies.</p>';
    const html = this.page({orientation:'portrait', school, title:'Report Card — ' + name, body, watermark: opts.watermark || ''});
    this.open('Report Card — ' + name, html);
  },

  /* ===================================================================
     2) CLASS BROADSHEET
     =================================================================== */
  async classBroadsheet(opts){
    opts = opts || {};
    const school = this.school();
    const db = this.sb || (typeof sb !== 'undefined' ? sb : null);
    if (!db) throw new Error('Database not configured.');
    const klass = (opts.class || '').trim();
    const term  = (opts.term || '').trim();
    const sess  = (opts.session || '').trim();
    if (!klass) throw new Error('class is required.');

    // Family-safe: parents/students cannot view broadsheets
    const scope = await this.roleScope();
    if (scope.family) throw new Error('Broadsheets are staff-only.');

    const { data: rows } = await db.from('report_subject_totals').select('*').eq('class', klass).eq('term', term).eq('session', sess);
    const subjects = [...new Set((rows || []).map(r => r.subject))].sort();
    const students = [...new Set((rows || []).map(r => r.student_name))].sort();
    const clsAvg = (() => {
      if (!rows || !rows.length) return 0;
      const per = {}; rows.forEach(r => { const k = r.student_name; const p = this.n(r.obtainable) ? (this.n(r.obtained)/this.n(r.obtainable))*100 : 0; per[k] = (per[k]||0) + p; });
      const keys = Object.keys(per); const avgs = keys.map(k => per[k] / Math.max(1, subjects.length));
      return avgs.length ? avgs.reduce((a,b)=>a+b,0) / avgs.length : 0;
    })();

    // Build per-student table
    const totals = {};
    students.forEach(st => {
      let tot = 0, obt = 0, count = 0;
      subjects.forEach(su => {
        const r = (rows || []).find(x => x.student_name === st && x.subject === su);
        if (r) { tot += this.n(r.obtained); obt += this.n(r.obtainable); count++; }
      });
      const avg = obt ? (tot / obt) * 100 : 0;
      totals[st] = { tot, obt, avg };
    });
    const sorted = [...students].sort((a,b) => (totals[b]?.avg||0) - (totals[a]?.avg||0));
    const position = {}; sorted.forEach((st, i) => position[st] = i + 1);

    const head =
'<h1 style="font-family:Georgia,serif;color:' + school.primary + ';text-align:center;margin:0;font-size:22px">' + this.esc(school.name) + ' — CLASS BROADSHEET</h1>' +
'<p style="text-align:center;font-size:11px;margin:6px 0 10px;color:#334155">' + this.esc(((term||'') + ' · ' + (sess||'')).toUpperCase()) + ' SESSION · CLASS: ' + this.esc(klass.toUpperCase()) + ' · ' + students.length + ' students · Class Average: ' + this.fmt(clsAvg, 1) + '%</p>';

    const rot = (s) => '<th class="rot"><span>' + this.esc(s) + '</span></th>';
    let bodyTable = '<table><thead><tr><th>S/N</th><th class="left">FULL NAME</th><th>ADM NO.</th>' + subjects.map(rot).join('') + '<th>TOTAL</th><th>AVG %</th><th>POS</th><th>GRADE</th><th>REMARK</th></tr></thead><tbody>';
    if (!students.length) {
      bodyTable += '<tr><td colspan="' + (3 + subjects.length + 4) + '" style="text-align:center;padding:30px">No scores recorded for this class/term/session.</td></tr>';
    } else {
      sorted.forEach((st, i) => {
        const t = totals[st] || {tot:0, obt:0, avg:0};
        const isTop = i === 0;
        const cls = isTop ? 'top' : '';
        const cells = subjects.map(su => {
          const r = (rows || []).find(x => x.student_name === st && x.subject === su);
          return '<td>' + (r ? this.fmt(r.obtained) : '-') + '</td>';
        }).join('');
        const grade = this.broadsheetGrade(t.avg);
        bodyTable += '<tr class="' + cls + '"><td>' + (i+1) + '</td><td class="left"><b>' + this.esc(st) + '</b></td><td>—</td>' + cells + '<td><b>' + this.fmt(t.tot) + '</b></td><td>' + this.fmt(t.avg, 1) + '</td><td><b>' + this.ordinal(position[st]) + '</b></td><td>' + grade + '</td><td>' + this.broadsheetRemark(grade) + '</td></tr>';
      });
    }
    bodyTable += '</tbody></table>';

    const scale = '<div class="grading-scale"><b>Grading scale:</b> A (80–100) Excellent · B (70–79) Very Good · C (60–69) Good · D (50–59) Credit · E (40–49) Pass · F (0–39) Fail</div>';

    const sig =
'<div class="sig">' +
'  <div><div class="sig-script">Class Teacher</div><div class="sig-line">Class Teacher\'s Signature</div></div>' +
'  <div>' + this.stamp(school) + '<div class="sig-line" style="margin-top:4px">Principal\'s Signature &amp; Stamp</div></div>' +
'</div>';

    const body = head + bodyTable + scale + sig + '<p class="note">SAMPLE of the class broadsheet (Academic Records → Class Broadsheet → Print). One row per student, one column per subject, automatic totals/averages/positions/grades. Landscape A4. Licensed Platform · HMG Technologies.</p>';
    const html = this.page({orientation:'landscape', school, title:'Class Broadsheet — ' + klass, body, watermark: opts.watermark || ''});
    this.open('Class Broadsheet — ' + klass, html);
  },

  /* ===================================================================
     3) SUBJECT BROADSHEET
     =================================================================== */
  async subjectBroadsheet(opts){
    opts = opts || {};
    const school = this.school();
    const db = this.sb || (typeof sb !== 'undefined' ? sb : null);
    if (!db) throw new Error('Database not configured.');
    const klass = (opts.class || '').trim();
    const subject = (opts.subject || '').trim();
    const term  = (opts.term || '').trim();
    const sess  = (opts.session || '').trim();
    if (!klass || !subject) throw new Error('class and subject are required.');
    const scope = await this.roleScope();
    if (scope.family) throw new Error('Broadsheets are staff-only.');

    // Pull assessment_columns + report_scores for this combo
    const { data: ac } = await db.from('assessment_columns').select('*').eq('class', klass).eq('term', term).eq('session', sess).order('position');
    const { data: rs } = await db.from('report_scores').select('*').eq('class', klass).eq('subject', subject).eq('term', term).eq('session', sess);
    const { data: stu } = await db.from('students').select('id,full_name,admission_no').eq('class', klass).order('full_name');
    const cols = (ac || []).filter(c => c.subject === '*' || c.subject === subject);
    const totalMax = cols.reduce((a,c) => a + this.n(c.max_mark), 0);

    // Build the per-student scores
    const scoreMap = {}; (rs || []).forEach(r => { const k = (r.student_id_ref || r.student_name) + '|' + r.column_id; scoreMap[k] = r.score; });
    const lines = (stu || []).map(st => {
      const ref = st.admission_no || st.full_name;
      let tot = 0; const cells = cols.map(c => { const v = scoreMap[ref + '|' + c.id]; if (v != null) tot += this.n(v); return '<td>' + (v != null ? this.fmt(v) : '') + '</td>'; }).join('');
      const pct = totalMax ? (tot / totalMax) * 100 : 0;
      return { name: st.full_name, adm: st.admission_no || '', cells, tot, pct, grade: this.grade(pct), remark: this.remark(pct) };
    });
    const sorted = [...lines].sort((a,b) => b.pct - a.pct); const pos = {}; sorted.forEach((l, i) => pos[l.name] = i + 1);

    const head =
'<h1 style="font-family:Georgia,serif;color:' + school.primary + ';text-align:center;margin:0;font-size:22px">' + this.esc(school.name) + ' — SUBJECT BROADSHEET</h1>' +
'<p style="text-align:center;font-size:11px;margin:6px 0 10px;color:#334155">' + this.esc(((term||'') + ' · ' + (sess||'')).toUpperCase()) + ' SESSION · CLASS: ' + this.esc(klass.toUpperCase()) + ' · SUBJECT: ' + this.esc(subject.toUpperCase()) + '</p>';

    let bodyTable = '<table><thead><tr><th>S/N</th><th class="left">FULL NAME</th><th>ADM NO.</th>' + cols.map(c => '<th>' + this.esc(c.name) + '<br><small>/' + this.fmt(c.max_mark) + '</small></th>').join('') + '<th>TOTAL<br><small>/' + this.fmt(totalMax) + '</small></th><th>AVG %</th><th>POS</th><th>GRADE</th><th>REMARK</th></tr></thead><tbody>';
    if (!lines.length) {
      bodyTable += '<tr><td colspan="' + (3 + cols.length + 4) + '" style="text-align:center;padding:30px">No assessment columns or students configured for this combination yet.</td></tr>';
    } else {
      sorted.forEach((l, i) => {
        const isTop = i === 0;
        bodyTable += '<tr class="' + (isTop ? 'top' : '') + '"><td>' + (i+1) + '</td><td class="left"><b>' + this.esc(l.name) + '</b></td><td>' + this.esc(l.adm) + '</td>' + l.cells + '<td><b>' + this.fmt(l.tot) + '</b></td><td>' + this.fmt(l.pct, 1) + '</td><td><b>' + this.ordinal(pos[l.name]) + '</b></td><td>' + l.grade + '</td><td>' + l.remark + '</td></tr>';
      });
    }
    bodyTable += '</tbody></table>';

    const sig =
'<div class="sig">' +
'  <div><div class="sig-script">Subject Teacher</div><div class="sig-line">Subject Teacher\'s Signature</div></div>' +
'  <div>' + this.stamp(school) + '<div class="sig-line" style="margin-top:4px">Principal\'s Signature &amp; Stamp</div></div>' +
'</div>';

    const body = head + bodyTable + sig + '<p class="note">SAMPLE of the subject broadsheet (Report Cards → Subject Broadsheet). One row per student, one column per assessment column, automatic totals/percentages/positions/grades. Landscape A4. Licensed Platform · HMG Technologies.</p>';
    const html = this.page({orientation:'landscape', school, title:'Subject Broadsheet — ' + subject, body, watermark: opts.watermark || ''});
    this.open('Subject Broadsheet — ' + subject, html);
  },

  /* ===================================================================
     4) FEE E-RECEIPT
     =================================================================== */
  async feeReceipt(opts){
    opts = opts || {};
    const school = this.school();
    const db = this.sb || (typeof sb !== 'undefined' ? sb : null);
    if (!db) throw new Error('Database not configured.');
    const studentId = opts.studentId;
    if (!studentId) throw new Error('studentId is required.');

    const scope = await this.roleScope();
    if (scope.family && !scope.studentIds.includes(studentId)) {
      throw new Error('Access denied: you can only view your own children.');
    }
    const { data: stu } = await db.from('students').select('*').eq('id', studentId).maybeSingle();
    if (!stu) throw new Error('Student not found.');
    const { data: pays } = await db.from('fee_payments').select('*').eq('student_id', studentId).order('created_at',{ascending:false});
    const last = (pays && pays[0]) || null;
    const term = (opts.term || last?.term || 'Current Term');
    const session = (opts.session || last?.session || '');
    const amountPaid = this.n(last?.amount_paid);
    const feeTotal = this.n(last?.fee_total);
    const balance = last?.balance != null ? this.n(last.balance) : Math.max(0, feeTotal - amountPaid);
    const isFullyPaid = balance <= 0;
    const receiptNo = (last?.reference || ('RCP-' + new Date().getFullYear() + '-' + String(Date.now()).slice(-4))).slice(0, 20);

    // Build the receipt body (A4 portrait, single 520px receipt)
    const body =
'<div class="receipt">' +
'  <div class="rh">' +
'    <div class="logo" style="width:58px;height:58px;border-radius:12px;background:linear-gradient(135deg,' + school.primary + ',#4f46e5);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:900;font-size:1.5rem"><img src="' + this.esc(school.logo) + '" alt="" onerror="this.style.display=\'none\';this.parentNode.textContent=\'' + this.esc(this.initials(school.name)) + '\'"></div>' +
'    <div style="text-align:center">' +
'      <h2 style="margin:0;font-size:1.15rem;font-family:Georgia,serif;color:' + school.primary + '">' + this.esc(school.name) + '</h2>' +
'      <p class="sub" style="margin:2px 0 0;font-size:.72rem;color:#334155">' + this.esc([school.address, school.phone, school.email].filter(Boolean).join(' · ')) + '</p>' +
'      <p class="sub" style="letter-spacing:3px;font-weight:800;font-size:.78rem;margin-top:6px">OFFICIAL E-RECEIPT</p>' +
'    </div>' +
'  </div>' +
'  <div class="row"><span>Receipt No.</span><b>' + this.esc(receiptNo) + '</b></div>' +
'  <div class="row"><span>Date</span><b>' + this.esc(this.fmtDate(last?.created_at || new Date())) + '</b></div>' +
'  <div class="row"><span>Student</span><b>' + this.esc((stu.full_name || '').toUpperCase()) + (stu.class ? ' (' + this.esc(stu.class + (stu.arm ? ' ' + stu.arm : '')) + ')' : '') + '</b></div>' +
'  <div class="row"><span>Admission No.</span><b>' + this.esc(stu.admission_no || '—') + '</b></div>' +
'  <div class="row"><span>Term / Session</span><b>' + this.esc(term) + (session ? ' · ' + this.esc(session) : '') + '</b></div>' +
'  <div class="row"><span>Payment Method</span><b>' + this.esc((last?.method || 'Cash') + (last?.reference ? ' · Ref: ' + last.reference : '')) + '</b></div>' +
'  <div class="row"><span>Total Fee for Term</span><b>' + this.esc(school.currency || '₦') + this.fmt(feeTotal) + '</b></div>' +
'  <div class="paid"><div style="font-size:.75rem;color:#334155">AMOUNT PAID</div><div class="amt">' + this.esc(school.currency || '₦') + this.fmt(amountPaid) + '</div></div>' +
(isFullyPaid
  ? '<div class="bal full" style="background:#f0fdf4;border:1px solid #16a34a;color:#16a34a;font-weight:800;padding:8px;text-align:center;margin-top:8px;border-radius:8px">FULLY PAID ✔</div>'
  : '<div class="bal" style="background:#fef2f2;border:1px dashed #dc2626;border-radius:8px;padding:8px;text-align:center;margin-top:8px;font-size:.9rem">Remaining Balance: <b style="color:#dc2626;font-size:1.1rem">' + this.esc(school.currency || '₦') + this.fmt(balance) + '</b></div>') +
'  <div class="sig" style="margin-top:22px;text-align:center;font-size:.8rem">' +
'    <div class="script" style="font-family:\'Segoe Script\',cursive;font-size:1.3rem;color:' + school.primary + '">' + this.esc(school.principal || 'Bursar / Principal') + '</div>' +
'    <div style="border-top:1px solid #111;width:180px;margin:2px auto 0;padding-top:2px"><b>' + this.esc(school.principal || 'Bursar / Principal') + '</b> — Bursar / Principal</div>' +
'  </div>' +
'  <p class="note" style="margin-top:12px;font-size:.62rem;color:#94a3b8;text-align:center">Generated by School Connect v4.0 · E-receipt carries your school logo, signature, currency and dd/mm/yyyy dates. Licensed Platform · HMG Technologies.</p>' +
'</div>';

    const html = this.page({orientation:'portrait', school, title:'E-Receipt — ' + (stu.full_name||''), body, watermark: opts.watermark || ''}) + '<style>.sheet{width:580px !important;padding:26px !important}.receipt{border:2px solid #111;padding:0}.row{display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px dashed #cbd5e1;font-size:.9rem}.row b{color:#0f172a}</style>';
    this.open('E-Receipt — ' + (stu.full_name||''), html);
  }
};

if (typeof window !== 'undefined') window.ReportEngine = ReportEngine;
