# تقرير التدقيق المجهري الشامل لمشروع NOVA — الإصدار المحدث

**التاريخ:** 31 يوليو 2026  
**النطاق:** 60+ ملف Rust عبر الوحدات التالية: `daemon/engine/` (23 ملفًا + `adaptive/`)، `daemon/curl/` (8 ملفات)، `daemon/routes/` (9 ملفات)، `daemon/resource_intelligence/` (7 ملفات)، `daemon/external_tools/`، بالإضافة إلى `mod.rs`, `state.rs`, `types.rs`, `utils.rs`, `direct.rs`, `persist.rs`, `ytdlp.rs`, `telegram.rs`, `native_host.rs`.  
**الأسطر المفحوصة:** ~20,000+ سطر (قراءة كاملة وليس بحثًا سطحيًا).  
**الطريقة:** فحص سطري مقابل الحقيقة الفعلية للكود الحالي عند `HEAD = 0767363`؛ إعادة التحقق من كل ادعاء ورد في تقرير التدقيق السابق (29 يوليو 2026)؛ اختبارات تجريبية على Windows 10 للأجزاء الحرجة (تخصيص مساحة القرص).  
**الملاحظة:** هذا التقرير يصحح تقرير 29 يوليو ويحل محله؛ ادعاءات التقرير القديم التي لم تعد صحيحة في النسخة الحالية مُدرجة في قسم «تصحيحات لتقرير سابق».

---

## جدول المحتويات
1. [الملخص التنفيذي](#الملخص-التنفيذي)
2. [ملخص النتائج حسب الخطورة](#ملخص-النتائج-حسب-الخطورة)
3. [مشاكل أمان الشبكة (SSRF)](#مشاكل-أمان-الشبكة-ssrf)
4. [مشاكل الصحة والاستمرارية (Correctness)](#مشاكل-الصحة-والاستمرارية-correctness)
5. [مشاكل التزامن](#مشاكل-التزامن)
6. [مشاكل إدارة الذاكرة وlibcurl FFI](#مشاكل-إدارة-الذاكرة-وlibcurl-ffi)
7. [مشاكل الأداء](#مشاكل-الأداء)
8. [الكود الميت (المُصحح)](#الكود-الميت-المصحح)
9. [مشاكل معمارية](#مشاكل-معمارية)
10. [نقاط القوة المؤكدة](#نقاط-القوة-المؤكدة)
11. [تصحيحات لتقرير سابق](#تصحيحات-لتقرير-سابق)
12. [قائمة الأولويات للتصليح](#قائمة-الأولويات-للتصليح)
13. [الملخص الإحصائي والحكم النهائي](#الملخص-الإحصائي-والحكم-النهائي)

---

## الملخص التنفيذي

نوفا هو مدير تحميل مبني على Tauri + Rust مع محرك تحميل داخلي يعتمد على libcurl عبر FFI خام (easy + multi)، وخادم HTTP محلي على `127.0.0.1` عبر axum، وإضافة متصفح. أُعيدت هندسة المحرك بشكل كبير مقارنةً بالتدقيق السابق: وحدة `daemon/adaptive/` القديمة حُذفت بالكامل، وتم توصيل `AdaptiveEngine` و `ResourceIntelligenceEngine` و `SelfHealer` و `PolicyEngine` بالتدفق الفعلي للتحميل.

**الخلاصة العامة:** البنية الحالية سليمة بشكل ملحوظ في طبقات الدفاع الأساسية (تقييد المخططات، فحص SSRF عند الإنشاء، ترتيب الأقفال، اندماج الأجزاء). لم يُرصد أي خلل حرج (Critical) في النسخة الحالية. الرصد الأهم هو **ثغرة SSRF عبر إعادة التوجيه (redirect) وخدمات المرايا (mirrors)** في مسار التحميل الفعلي، حيث لا يُعاد التحقق من الهدف بعد أي redirect أو عند التحويل إلى mirror، ولا من سلسلة redirects الخاصة بـ RIE.

---

## ملخص النتائج حسب الخطورة

| المعرف | الخطورة | الموقع | الملخص |
|--------|---------|--------|--------|
| SEC-1 | عالية | `curl/transfer.rs:299-453,1273-1281` + `routes/downloads.rs:731-735` | الهدف بعد إعادة التوجيه لا يُعاد التحقق منه (SSRF) |
| SEC-2 | متوسطة | `routes/downloads.rs:757-764` + `curl/transfer.rs:1494-1520` | حقن مرايا من رأس `Link` دون فحص SSRF، والتحويل إليها في failover دون فحص |
| COR-1 | متوسطة | `curl/easy_config.rs:1197-1201` | تخصيص مساحة القرص لا يعمل فعليًا على NTFS (اختبار تجريبي مؤكد) |
| SEC-3 | منخفضة | `curl/task_api.rs:405` | تحديث URL يستخدم الفحص غير المثبت DNS (TOCTOU) |
| SEC-4 | منخفضة | `ytdlp.rs:949`, `routes/probes.rs:315/618/720` | فحوصات yt-dlp والبروبات غير مثبتة DNS |
| COR-2 | منخفضة | `direct.rs:359` vs `engine/retry.rs:6` | نوعا `RetryPolicy` منفصلان مع منطق مختلف |
| COR-3 | منخفضة | `direct.rs:425-426` | أي خطأ يحتوي `ssl`/`tls` يُعد عابرًا في `is_transient_error` |
| CON-1 | منخفضة | `engine/thread_pool.rs:37-40` | ترتيب ذاكرة `Relaxed` على عدّاد العمال |
| PERF-1 | منخفضة | `external_tools/installer.rs:208-214` | `block_in_place` + `block_on` |
| DEAD-1 | منخفضة | `engine/chunk_manager.rs` | وحدة كاملة ميتة إنتاجيًا |
| ARCH-1 | منخفضة | `engine/adaptive_connections.rs` + `engine/adaptive/mod.rs` | نظامان تكيفيان متوازيان يعملان معًا |
| ARCH-2 | معلوماتية | `engine/plugin_api.rs:49` | `api_version` ثابتة بلا تحقق توافق |

---

## مشاكل أمان الشبكة (SSRF)

### SEC-1 — الهدف الفعلي بعد إعادة التوجيه لا يُعاد التحقق منه (عالية)

**المواقع:**
- `daemon/curl/transfer.rs:299-453` — `resolve_effective_target()` يتابع سلاسل HTTP redirects و meta-refresh (حتى 5 قفزات) بدون أي استدعاء `is_safe_target_url`.
- `daemon/curl/transfer.rs:1273-1281` — `plan.url = effective_url` دون إعادة تحقق.
- `daemon/routes/downloads.rs:731-735` — الهدف النهائي من سلسلة redirects الخاص بـ RIE يُكتب إلى `job.task.url` بعد فحص *المخطط* فقط (`supported_direct_url`).
- `daemon/curl/task_api.rs:29-30` — تثبيت `--resolve host:port:ip` يغطي **host الأصل فقط**؛ أي host جديد بعد redirect يُحلّ DNS من جديد بحرية.

**آلية الثغرة:** عند الإنشاء يُثبَّت host الأصل بالعنوان الخارجي (فحص صحيح). لكن إذا ردّ الخادم الخارجي بـ `302 Location: http://169.254.169.254/...` أو `http://127.0.0.1:8080/...`، فإن:
1. محرك curl يتابع التوجيه (FOLLOWLOCATION مفعّل افتراضيًا، حد 20) ويحمّل من الهدف الداخلي ويكتب المحتوى إلى القرص؛
2. مسار RIE (`background_resolve_and_start` → `state.rie.resolve`) يجري فحص HEAD/RANGE/GET على الهدف الداخلي بدون أي فحص SSRF في كامل وحدة `resource_intelligence/` (صفر استدعاءات `is_safe_target_url`).

**الأثر:** استخراج محتوى خدمات داخلية (بيانات تعريف السحابة، إعدادات الراوتر) إلى قرص المستخدم؛ وSSRF أعمى مع تسريب بيانات تعريفية (الحجم/etag/content-type/اسم الملف) من hosts داخلية. المسار العملي: صفحة ويب خبيثة تطلق تحميل متصفح لـ URL على خادم المهاجم يرد بـ 302 إلى عنوان داخلي؛ الإضافة تحوّل URL (الخارجي الآمن) إلى NOVA؛ الفحص المثبّت يمرّ (الخادم الأصلي خارجي) ثم تتبع NOVA التوجيه إلى الداخل.

**الإصلاح:** إعادة `is_safe_target_url_pinned(&effective_url)` بعد `resolve_effective_target` وقبل `run_libcurl_download`؛ ورفض أي redirect/meta-refresh إلى host داخلي؛ وإعادة الفحص المثبّت على `final_url` القادمة من RIE قبل كتابتها في `task.url`.

### SEC-2 — حقن مرايا (mirrors) من رأس Link دون فحص، والتحويل إليها دون فحص (متوسطة)

**المواقع:**
- `daemon/routes/downloads.rs:757-764` — `link_mirrors` من `report.server_capabilities.link_mirrors` تُدخل في `direct_options` دون أي `is_safe_target_url`.
- `daemon/curl/transfer.rs:1494-1520` — عند فشل التحميل تُسجَّل المرايا في `MirrorManager` ثم `plan.url = new_url` (failover) دون فحص SSRF.
- `daemon/routes/downloads.rs:227,263-285` — المرايا القادمة من القواعد (`RuleAction::AddMirror`) تُسجَّل مباشرة دون فحص (الفحص الوحيد موجود في واجهة `/api/mirrors` فقط: `routes/engine.rs:797-800,1018-1019`).

**الأثر:** خادم خارجي يمكنه الإعلان عن `Link: <http://127.0.0.1:...>; rel=duplicate` فيستقبلها NOVA كمرآة failover، ويحمّل منها عند فشل المصدر الأساسي دون أي تحقق من الوجهة.

**الإصلاح:** فحص كل mirror بـ `is_safe_target_url_pinned` عند الإدخال (سواء من البروب أو من القواعد) وعند الاستخدام في failover.

### SEC-3 — تحديث URL يستخدم الفحص غير المثبت DNS (منخفضة)

**الموقع:** `daemon/curl/task_api.rs:403-405` — `update_task_metadata()` يستخدم `is_safe_target_url(&parsed.normalized)` (غير المثبتة)، بينما مسار الإنشاء يستخدم `is_safe_target_url_pinned` (task_api.rs:30). نافذة DNS rebinding: تتحقق الدالة من العنوان، ثم يُحلّ DNS لاحقًا من جديد بواسطة libcurl.

**الإصلاح:** استخدام `is_safe_target_url_pinned` في مسار التحديث أيضًا، وتحديث `resolve` entries في `direct_options`.

### SEC-4 — فحوصات yt-dlp والبروبات غير مثبتة DNS (منخفضة)

**المواقع:** `daemon/ytdlp.rs:949`، `daemon/routes/probes.rs:315,618,720` — كلها تستخدم النسخة غير المثبتة. طبيعة التحقق زمنية: يتم الفحص قبل أن يحلّ yt-dlp/curl DNS بنفسه. أثرها محدود لأن الخادم المنفذ للطلب النهائي يتحقق ضمنيًا عبر `validate_resolve_entry` في مسار curl، لكنها تبقى نقاط تحقق أضعف من المسار المثبت.

---

## مشاكل الصحة والاستمرارية (Correctness)

### COR-1 — تخصيص مساحة القرص لا يعمل فعليًا على NTFS (متوسطة، اختبار تجريبي مؤكد)

**الموقع:** `daemon/curl/easy_config.rs:1197-1201` — عند `preallocate_bytes = Some(size)` يُستدعى `file.set_len(size)`.

**النتيجة التجريبية (Windows 10):** `File::set_len` يُترجم إلى `SetEndOfFile` على Windows الذي يمدّ الطول المنطقي فقط دون حجز كتل فعلية على NTFS. التخصيص المسبق «لا يمنع» نفاد القرص أثناء الكتابة، ووعد الميزة (منع فشل منتصف التحميل) لا يتحقق على NTFS. الكود الحالي يتعامل مع الأثر الجانبي (تضخّم الحجم الظاهري) عبر `effective_downloaded` (transfer.rs:690-721) و`f.set_len(0)` عند الخطأ (transfer.rs:864) — السلوك آمن من ناحية الفساد، لكنه لا يفي بالغرض المعلن.

**الإصلاح:** على Windows استبدال بـ `SetFileValidData` (يتطلب `SeManageVolumePrivilege`) أو حذف التخصيص والاكتفاء بالتحقق من المساحة المتبقية قبل البدء.

### COR-2 — نوعا `RetryPolicy` منفصلان (منخفضة)

**المواقع:** `daemon/direct.rs:359` (المُستخدَم فعليًا في حلقة النقل: `transfer.rs:1241,1557` عبر `transfer_config.rs:373`) مقابل `daemon/engine/retry.rs:6` (المُستخدَم في `config.rs:91`, `profiles.rs:183`, `persist.rs:262`, `policy_engine.rs:328`).

**الأثر:** منطقان مختلفان لإعادة المحاولة وتصنيف الأخطاء؛ أي إعداد في ملف التعريف يُخزَّن عبر `to_retry_policy()` قد لا يصل إلى الحلقة الفعلية بذات الدلالات. يتطلب توحيد النوعين على أساس واحد.

### COR-3 — `is_transient_error` يعدّ أي خطأ يحوي `ssl`/`tls` عابرًا (منخفضة)

**الموقع:** `daemon/direct.rs:425-426`. القائمة `permanent_ssl` (402-410) تستبعد بعض أخطاء الشهادات، لكن أي رسالة أخرى تحوي `ssl` أو `tls` (مثل أخطاء إصدار بروتوكول غير قابل للحل) تُعاد محاولتها. كما أن `is_permanent_error` (446-455) تُصنّف 500/501/504 دائمة بينما تُصنّف 502/503 عابرة في القائمة المقابلة — اتساق غير مضمون بين الدالتين.

---

## مشاكل التزامن

### CON-1 — ترتيب ذاكرة `Relaxed` على عدّاد العمال (منخفضة)

**الموقع:** `daemon/engine/thread_pool.rs:37,40` — `fetch_add(1, Ordering::Relaxed)` / `fetch_sub(1, Ordering::Relaxed)`. الأثر معلوماتي فقط (`active_count`)، لكنه قد يُقرأ كقيمة قديمة. الإصلاح: `Acquire`/`Release`.

**ملاحظات إيجابية في نفس الملف:**
- قناة مستقلة لكل عامل (تعليق C-04) — لا تنازع على قناة استقبال واحدة (thread_pool.rs:26-30).
- `catch_unwind` حول كل مهمة مع تسجيل الذعر (38-50) — لا يموت العامل.
- توزيع round-robin مع إعادة محاولة إرسال عند امتلاء قناة (74-96).

### CON-2 — `active_count` و `spawn()` غير مستخدمين في الإنتاج

**الموقع:** `thread_pool.rs:111` — `#[allow(dead_code)]` على `spawn()`. العمال يُدارون عبر `ResourceManager`، والدالة العامة للجدولة غير مستخدمة. لا يُعد خللًا بل كودًا ميتًا جزئيًا.

### CON-3 — أقفال `ProfileManager` متسقة (تم التحقق — لا ثغرة)

تم فحص الادعاء الوارد في تقرير سابق حول «ترتيب قفل غير متناسق» وثبت أنه **غير صحيح** في النسخة الحالية: `active_profile()` يقفل `active_profile` ثم `profiles` (profiles.rs:218-225)، و`set_active()` يقفل `active_profile` فقط (237)؛ لا يوجد مسار يقفل `profiles` أولًا، فلا يحدث ABBA.

### CON-4 — ترتيب القفل `curl_jobs → task_snapshot` موثق ومطبق

تأكد الالتزام به في: `task_api.rs:75-83` (الإنشاء)، `routes/downloads.rs:723` (التحديث الخلفي)، `transfer.rs:1306` (إعادة التسمية). لا يوجد مسار يقفل الترتيب المعاكس.

### CON-5 — `event_bus` بسعة محدودة 100 حدث

**الموقع:** `engine/event_bus.rs` (`EventBus::new_with_capacity(100)`)، ناشرون متعددون (persist.rs:252, mod.rs:274, routes/engine.rs:192/345/824, downloads.rs:237/277). بدون backpressure قد تُسقط أحداث تحت ضغط نشر مرتفع؛ الأثر تشغيلي (إشعارات مفقودة) وليس انهيارًا.

---

## مشاكل إدارة الذاكرة وlibcurl FFI

| المعرف | الموقع | الوصف | الحالة |
|--------|--------|-------|--------|
| FFI-1 | `easy_config.rs:37-38` | `CString::new(value).map_err` — لا panic على NUL | **مُصلح** (كان panic) |
| FFI-2 | `easy_config.rs:44-49` | فحص `CURLE_OK` مع تحرير الذاكرة عند الفشل | **مُصلح** |
| FFI-3 | `direct.rs:70-72` | `set_url` يعالج NUL بـ `map_err` | سليم |
| FFI-4 | `resource_manager.rs:85-93` | `unsafe` مع `MemoryStatusEx::zeroed()` — التحقق من `dw_length` قبل الاستدعاء | قائم (ينخفض لأنه يُملأ قبل الاستدعاء) |
| FFI-5 | `easy_config.rs:39-43` | تسريب مقصود لـ `CString` لضمان عمر المؤشر — مع تحريره عند فشل libcurl | مقبول وموثق |

**ملاحظة عامة:** طبقة FFI الحالية أفضل بكثير من التقرير السابق؛ كل `CString::new` في مسار easy config تمر عبر `map_err`، وكل `curl_easy_setopt` يفحص رمز الخطأ.

---

## مشاكل الأداء

### PERF-1 — `block_in_place` + `block_on` في التثبيت (منخفضة)

**الموقع:** `external_tools/installer.rs:208-214`. الطلب عبر HTTP يُنفَّذ داخل `block_in_place(|| handle.block_on(...))` — غير محظور لكنه يشغّل عمال الـ async runtime بشكل أقل كفاءة من `reqwest::blocking`.

### PERF-2 — حلقة انتظار نشطة في `hidden_output_timed`

**الموقع:** `routes/common.rs:48-70` — حلقة `sleep(50ms)` تنتظر انتهاء عملية خارجية. دالة محظورة (لا تمنع المفاعل) لكنها تستهلك دورة فحص؛ الأثر منخفض.

### PERF-3 — تصميم جيد يستحق الذكر

- SSE بمعدل 250ms مع التزامية كاملة (SSE heartbeat 10s، إعادة مزامنة كاملة كل 60 ثانية) — downloads.rs:55-142.
- `preflight_resolved` يمنع ازدواج الفحص (RIE ثم curl) — transfer.rs:323-334.
- استعلام القدرات في `/api/health` عبر `spawn_blocking` — downloads.rs:33.
- `MAX_TASKS = 10_000` يمنع نمو غير محدود — task_api.rs:15,78.

---

## الكود الميت (المُصحح)

الادعاء الوارد في التقرير السابق بأن «~40% من قاعدة الكود ميت وكل الأنظمة التكيفية غير متصلة» **لم يعد صحيحًا**. الواقع الحالي (بعد الفحص السطري):

| المعرف | الموقع | الوصف | الحالة |
|--------|--------|-------|--------|
| DEAD-1 | `engine/chunk_manager.rs` | `ChunkManager` + `SlidingWindow` + `recommend_chunk_size` + `update_remaining_bytes` — لا مستهلك في الإنتاج (بحث شامل: لا استدعاء خارج الاختبارات) | ميت تمامًا |
| DEAD-2 | `engine/self_healing.rs` | 10 مواضع `allow(dead_code)` (حقول/دوال) — لكن `SelfHealer` نفسه موصول (transfer.rs:1443-1479) | جزئي |
| DEAD-3 | `engine/resource_manager.rs` | `allow(dead_code)` عند 51,57,77,93 | جزئي |
| DEAD-4 | `engine/retry.rs:80` | حقل واحد | جزئي |
| DEAD-5 | `engine/event_bus.rs:364` | دالة واحدة | جزئي |
| DEAD-6 | `resource_intelligence/mod.rs:166` | `minimal_resolve` | جزئي |
| DEAD-7 | `external_tools/` | `types.rs:28,226-316` (8 مواضع)، `registry.rs:8`، `mod.rs:304,310`، `health.rs:10,176`، `capabilities.rs:86-124` (4 مواضع) | جزئي |

**الملاحظات التصحيحية:**
- `engine/adaptive/resource_monitor.rs:36-42` تستخدم `cfg_attr(not(target_os = "windows"), allow(dead_code))` — هذا ليس كودًا ميتًا، بل حقول Windows-only مُعلَّمة لأجل builds غير Windows. **سليم**.
- وحدة `engine/adaptive/` موصولة بالكامل: `AdaptiveEngine` في `state.rs:39`، إنشاؤه في `transfer.rs:984`، وتحديث تقدم الأجزاء في `transfer.rs:1134-1141` عبر `segment_ctrl.update_progress`.
- `AdaptiveConnectionManager` موصول: `tracker.adaptive.report_speed` في `transfer.rs:493` وإنشاء عند `transfer.rs:1029`.
- `checksum.rs` موصول: واجهات تحقق في `routes/engine.rs:728-746` وفحص SHA-256 بعد الاكتمال في `transfer.rs:1381-1384`.
- `scheduler.rs` موصول عبر مؤشر ترابط المجدول في `daemon/mod.rs` مع تقييد `power_commands_enabled` على إجراءات Shutdown/Sleep.

---

## مشاكل معمارية

### ARCH-1 — نظامان تكيفيان متوازيان يعملان معًا (منخفضة)

- `engine/adaptive_connections.rs::AdaptiveConnectionManager` (عدّادات ذرية، يضبط الاتصالات الكلية) و`engine/adaptive/mod.rs::AdaptiveEngine` (SegmentController عبر `segment_ctrl.update_progress`) كلاهما نشط في نفس حلقة التحميل. الحدود بين مسؤولية كل منهما غير موثقة؛ خطر تضارب القرارات (أحدهما يرفع الاتصالات والآخر يخفضها).

### ARCH-2 — مخزنان منفصلان لملفات تعريف الخوادم (منخفضة)

- `resource_intelligence/stability.rs::ServerProfileStore` (داخل `state.rie`) مقابل `engine/adaptive/profile_store.rs::UnifiedProfileStore` (داخل `DieOrchestrator`). قراءة واحدة لمسار التحميل تقرأ الأول (transfer.rs:87-102) بينما يسجّل الثاني (record_preflight/record_telemetry). لا يوجد تبادل بين المخزنين رغم تطابق الغرض.

### ARCH-3 — `RetryPolicy` مكرر

انظر COR-2 — نوعان بنفس الاسم بمنطق مختلف.

### ARCH-4 — `api_version` ثابتة (معلوماتية)

**الموقع:** `engine/plugin_api.rs:49,190` — `api_version: "1.0.0"` مثبتة نصيًا بلا تحقق توافق فعلي عند التحميل.

### ARCH-5 — `DynamicSegmentScheduler::new` مع `_max_segments` محجوز وغير مستخدم

**الموقع:** `engine/dynamic_segments.rs` — المعامل الثالث لا يُستخدم (محجوز للمستقبل). إشارة إلى إعادة تصميم متوقعة لنظام التجزئة.

---

## نقاط القوة المؤكدة

| المعرف | الموقع | الوصف |
|--------|--------|-------|
| POS-1 | `direct.rs:136-183` | `DirectUrl::parse` يرفض أي مخطط خارج (http/https/ftp/ftps/sftp/scp)، ويرفض أي URL يبدأ بـ `-` (حماية من حقن flags). |
| POS-2 | `utils.rs:35-94,155-193` + `task_api.rs:30` | طبقة SSRF ثلاثية: فحص، فحص مثبّت DNS (يرجع IP + resolve entry)، وفحص entries الخاصة بـ `--resolve/--connect-to`. |
| POS-3 | `utils.rs:696` + `resource_intelligence/mod.rs:188-194` + `curl/args.rs:96` | فحص URLs الخاصة بالبروكسيات قبل استخدامها ورفضها عند عدم الأمان. |
| POS-4 | `direct.rs:295-355` | `merge_parts`: فحص حجم كل جزء قبل النسخ، ملف مؤقت باسم عشوائي (لا تعارض)، `sync_all` للملف والمجلد، `rename` آمن، والتحقق النهائي من الحجم، مع تنظيف الأجزاء. |
| POS-5 | `direct.rs:432-456` | `is_permanent_error` يستثني تحديات Cloudflare/anti-bot (403) من التصنيف الدائم؛ و`ssrf blocked` يُعد دائمًا (لا إعادة محاولة). |
| POS-6 | `transfer.rs:323-334` | تخطي الفحص المسبق عند نجاح RIE — يمنع ازدواج الفحص ويحافظ على حالة الجلسة. |
| POS-7 | `transfer.rs:1246` | `learned_host_ceiling == Some(1)` يعطل التجزئة فورًا للـ hosts التي فشلت معها — تكيف ذكي بلا hosts مبرمجة. |
| POS-8 | `engine/scheduler.rs:59,71-79` | إجراءات Shutdown/Sleep مقيدة بـ `power_commands_enabled` (افتراضيًا معطلة). |
| POS-9 | `task_api.rs:15,78` | سقف `MAX_TASKS = 10_000` مع إدخال ذري بين قفلين. |
| POS-10 | `transfer.rs:1381-1384` + `routes/engine.rs:728-746` | تحقق SHA-256 بعد الاكتمال وواجهات تحقق يدوية مع كشف تلقائي للخوارزمية. |
| POS-11 | `engine/metadata_cache.rs` | TTL 3600s وحد أقصى 2048 مدخلًا — منع نمو غير محدود للذاكرة. |
| POS-12 | `daemon/mod.rs:445-462` | حارس يمنع النواة الأصلية من الوصول إلى أي عنوان غير loopback عند بدء التشغيل. |

---

## تصحيحات لتقرير سابق

| الادعاء السابق | الموقع المدّعى | الحكم في النسخة الحالية |
|----------------|----------------|--------------------------|
| «~40% من قاعدة الكود ميت؛ الأنظمة التكيفية والاستخبارية غير متصلة» | تقرير 29 يوليو | **خطأ.** `AdaptiveEngine`, `AdaptiveConnectionManager`, `SelfHealer`, `PolicyEngine`, `RIE`, `scheduler`, `checksum` كلها موصولة بالتدفق الفعلي. |
| «`daemon/adaptive/` و `disk_writer.rs` نسخة مكررة» | ARCH-2/DUP-1 | **انتهى.** المجلد حُذف؛ توجد فقط `engine/adaptive/` بلا `disk_writer.rs`. |
| «ترتيب قفل غير متناسق في ProfileManager (ميتة قفل محتملة)» | BUG-HIGH-1 | **خطأ.** الترتيب موحد `active_profile → profiles` وموثق (profiles.rs:234-236). |
| «`CString::new(url).unwrap()` → panic» | CURL-1 | **مُصلح.** `map_err` (easy_config.rs:37-38). |
| «`setopt_*` لا يفحص CURLcode» | CURL-2 | **مُصلح.** فحص `CURLE_OK` + تحرير عند الفشل (easy_config.rs:44-49). |
| «`adaptive_engine` حقل allow(dead_code)» | state.rs:110 | **خطأ.** مستخدم في الإنشاء والتحديث (transfer.rs:984,1134-1141). |

---

## قائمة الأولويات للتصليح

### عالية (P0)

| # | الموقع | المشكلة | الإجراء |
|---|--------|---------|---------|
| P0-1 | `transfer.rs` + `downloads.rs:731-735` | الهدف بعد redirect و`final_url` القادمة من RIE لا يُعاد فحصهما | `is_safe_target_url_pinned` قبل الالتزام بالنقل |
| P0-2 | `downloads.rs:757-764` + `transfer.rs:1494-1520` | مرايا Link/Rule غير مفحصه وتُستخدم في failover | فحص كل mirror عند الإدخال وعند الاستخدام |

### متوسطة (P1)

| # | الموقع | المشكلة | الإجراء |
|---|--------|---------|---------|
| P1-1 | `easy_config.rs:1197-1201` | تخصيص القرص لا يعمل على NTFS | `SetFileValidData` بصلاحية، أو فحص المساحة بدلًا من «التخصيص» |
| P1-2 | `direct.rs:359` / `engine/retry.rs:6` | نوعا RetryPolicy منفصلان | توحيد النوع وتغذية الحلقة الفعلية من ملفات التعريف |
| P1-3 | `task_api.rs:405` | فحص غير مثبت في تحديث URL | استخدام النسخة المثبتة وتحديث resolve entries |

### منخفضة (P2)

| # | الموقع | المشكلة | الإجراء |
|---|--------|---------|---------|
| P2-1 | `thread_pool.rs:37-40` | `Relaxed` على العدّاد | `Acquire`/`Release` |
| P2-2 | `direct.rs:425-426` | `ssl`/`tls` في `is_transient_error` | تضييق القائمة إلى أنماط قابلة للاسترداد فعليًا |
| P2-3 | `chunk_manager.rs` | وحدة ميتة إنتاجيًا | حذفها أو نقلها لاختبارات فقط |
| P2-4 | `external_tools/installer.rs:208-214` | `block_in_place`+`block_on` | `reqwest::blocking` |
| P2-5 | `engine/adaptive_connections.rs` vs `engine/adaptive/mod.rs` | نظامان تكيفيان | توثيق الحدود أو الدمج |
| P2-6 | `plugin_api.rs:49` | `api_version` ثابتة | تحقق فعلي من التوافق |

---

## الملخص الإحصائي والحكم النهائي

| الفئة | العدد | الخطورة الغالبة |
|-------|-------|------------------|
| SSRF (توجيه/مرايا) | 2 | عالية/متوسطة |
| صحة (preallocation, retry) | 3 | متوسطة/منخفضة |
| تزامن | 2 | منخفضة |
| أداء | 2 | منخفضة |
| كود ميت | 1 ملف كامل + 6 جزئي | منخفضة |
| معمارية | 5 | منخفضة/معلوماتية |
| خلل حرج (Critical) | 0 | — |
| خلل عالٍ | 1 | — |

**الحكم النهائي:** النسخة الحالية من المحرك متصلة فعليًا (خلافًا لتقرير يوليو) وتلتزم بضوابط أمنية جيدة عند الإنشاء. الثغرة الوحيدة ذات الأثر الواقعي هي غياب إعادة التحقق من الوجهة بعد إعادة التوجيه وعند المرايا — يجب معالجتها قبل اعتبار طبقة أمان الشبكة مكتملة. بقية الملاحظات تحسينية ولا تمنع التشغيل.
