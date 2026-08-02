# خطة الإصلاح الشاملة — NOVA Download Manager

**التاريخ:** 2026-08-01
**المرجع:** [AUDIT_REPORT.md](AUDIT_REPORT.md) (تدقيق محرك الـ daemon) + [code-audit-report.md](code-audit-report.md) (التدقيق الميكروسكوبي، 99 مشكلة) + تحقق ميداني من الكود الحالي (سطراً بسطر للنقاط الحرجة).
**الأساس:** القرارات المعتمدة — شحن المحرك التكيفي بالكامل، تغطية كل الفئات دفعة واحدة، واختبار لكل إصلاح.

---

## 1. الملخص التنفيذي

NOVA مشروع ضخم (Tauri + Rust daemon + React + إضافة متصفح MV3) بوضع أمني ممتاز وخط إنتاج محترف، لكنه يحمل عبئاً تقنياً موزعاً كالتالي:

| الفئة | العدد (حسب التدقيق) | تم التحقق من إصلاحه | ما زال قائماً ومؤكداً |
|---|---|---|---|
| CRITICAL | 12 | 11 | 1 (مسارات تحويل بعد C12) |
| HIGH | 22 | ~15 | ~7 |
| MEDIUM | 31 | ~8 | ~23 |
| LOW / INFO | 34 | ~6 | ~28 |

**أهم الاكتشافات المؤكدة بنفسي في الكود الحالي:**

1. **مشكلة الإيقاف المؤقت (Pause) — الأخطر من حيث توقعات المستخدم:** `allowed_speed_for_task` ترجع `0` عند التوقف (bandwidth.rs:76-80)، وtransfer.rs:712-716 يحوّل `0 → None` → لا يُضبط `MAX_RECV_SPEED` → **التحميل المتوقف يستمر بكامل السرعة**.
2. **المحرك التكيفي كامل التنفيذ لكنه معطّل في الإنتاج:** `AdaptiveEngine::evaluate` وقراراته (split/merge/rebalance/change connections) لا تملك أي مسار يعدّل easy handles الحية (transfer.rs:1247-1252 — تعليق صريح). هذا يجعل ~6 وحدات كاملة (PolicyEngine, SegmentController, BufferManager, ChunkManager, ConvergenceDetector, ServerProfiler) كوداً ميتاً، وسطح API/UI يعرض قرارات لا تُطبق.
3. **`hlsDashDownload` لن تصبح `true` أبداً:** engine_capabilities.rs:1504 يفحص النص المركّب `"mov,mp4,m4a,3gp,3g2,mj2"` بينما `formats` قائمة رموز مفصولة (sorted_vec) — الشرط مستحيل التحقق.
4. **`CANDIDATE_CURL_RAW_OPTIONS` فارغ:** engine_capabilities.rs:205 — `rawOptions` يُرفض دائماً رغم وجود شيفرة تحقّق كاملة.
5. **أخطاء jitter للـ retry:** retry.rs:69-74 — الجمع ثم `%` على قيمة f64 قابلة للقسمة يجعل الجِتر صفراً دائماً (لا يوجد تفريق للحشود).
6. **حدود السرعة لا تُطبّق على التحويلات الحيّة:** M6 — تغيير الحد لا يصل إلا عند إنشاء easy handle جديد.
7. **المجدول (Scheduler) level-triggered:** H2 — إجراءات Shutdown/Sleep/Notify تعيد الإطلاق كل 60 ثانية طالما الشرط قائماً، وM4: `return` بدل `continue` يُسقط باقي الإجراءات عند تعطيل أوامر الطاقة.
8. **سباق `TelemetryBus::report_speed`:** M9 — fetch_add/fetch_sub غير ذرية مع تبديل الخانة وقد يحدث underflow؛ وسرعة آخر اتصال لا تُطرح عند انتهائه.
9. **قيمة افتراضية ضارة في easy_config.rs:646-647:** `low_speed_limit(500) + low_speed_time(15s)` يقطع أي تحميل شرعي أبطأ من 500 بايت/ث.
10. **قفل مزدوج وملف تعريف يُكتب بصمت:** bandwidth.rs `remove_task_limit` (3 أقفال متداخلة)، وprofile_store.rs `save()` يبتلع أخطاء الكتابة.

---

## 2. القرارات الاستراتيجية (المعتمدة + المقترحة)

| القرار | الحالة |
|---|---|
| المحرك التكيفي: **شحن بالكامل** (تطبيق القرارات على easy handles الحية) | ✅ معتمد من المستخدم |
| نطاق الجولة: **كل الفئات دفعة واحدة** (مراحل متتالية، كل مرحلة PR يبقي CI خضراء) | ✅ معتمد من المستخدم |
| **اختبار لكل إصلاح** (أحمر → أخضر) | ✅ معتمد من المستخدم |
| التخفيض الديناميكي للاتصالات: **soft** (استكمال طبيعي + تقييد النمو بالتقارب) في الإصدار الأول؛ التخفيض الصلب المقيّد بالميزانية لاحقاً | اقتراح — يعتمد |
| المحرك التكيفي **مفعّل افتراضياً** للتحميلات المجزأة ذات الحجم المعروف، مع مفتاح `direct_options["adaptive"]=false` للتعطيل | اقتراح — يعتمد |
| إضافة `start_byte/end_byte` بنوع `Segment` مع `#[serde(default)]` (مطلوبة لصحة الاستئناف بعد تغيير الهندسة) | اقتراح — يعتمد |
| السماح بالتجاوز المؤقت لطول ملف الجزء (حتى القص عند الاكتمال/الدمج) بدل إعادة التحميل | اقتراح — يعتمد |

---

## 3. الحالة المؤكدة حالياً (Verification Results)

### 3.1 أُصلح مسبقاً — أضف اختبارات انحدار فقط

| المعرف | المشكلة | مكان الإصلاح الحالي |
|---|---|---|
| C1 | تسريب Tokio Runtime عند إعادة التشغيل | `signal_shutdown()` + oneshot (lib.rs:562-590, daemon/mod.rs:594-602) |
| C2 | `app.exit(0)` دون حفظ | tray quit → `signal_shutdown()` + 800ms (lib.rs:767-771) |
| C3/C4 | disk_writer يبتلع أخطاء I/O / بدون Drop | **الحذف الكامل للملف** من المشروع |
| C5 | panic في thread_pool يقتل العامل | `catch_unwind` (thread_pool.rs:38-51) |
| C6 | تسمم Mutex يجمّد EventBus | `PublishGuard` يعيد ضبط العمق عند unwind (event_bus.rs:149-196) |
| C7 | OOM من `u32::MAX` قطعة | `MAX_SEGMENTS = 256` (direct.rs:212) |
| C8 | yt-dlp pipe deadlock | قراءة stdout/stderr بخيطين متوازيين (ytdlp.rs:190-220) |
| C9 | تقدم 100% فوراً مع preallocation | transfer.rs:644-658 + اختبارات 2484/2556/2620 |
| C10/H5 | Watchdog قديم يدمّر الجيل الجديد | فحص `generation` في `force_error_status` (transfer.rs:2103-2109) |
| C11 | DNS بدون timeout | `recv_timeout(5s)` (lib.rs:372-402) |
| C12 | CPU statics غير ذرية | حقول per-instance (resource_monitor.rs:194-209) |
| H1 | مهمة الـ scheduler تموت بصمت | spawn كـ task + معالجة JoinError (daemon/mod.rs:457-474) |
| H2 | canonicalize مزدوج يضخّم TOCTOU | canonicalize واحد (lib.rs:200) |
| H7 | كشف 200 زائف عبر `plan.connections` | `ranges.len() > 1` (transfer.rs:1301) |
| H8 | remove_file قبل زيادة generation | bump generation أولاً (task_api.rs:483/570) |
| M19 | مهمة شبحية | snapshot يُحذف قبل curl_jobs (task_api.rs:575-577) |
| M2 | منفذ مشغول عند استنفاد النطاق | مسح كامل النطاق (lib.rs:121-135) |
| M18 | SSRF لبروكسي بدون scheme | تحليل scheme-less + timeout DNS (args.rs:97-149) |
| M20 | `retry_all_errors` افتراضياً true | `unwrap_or(false)` (transfer_config.rs:378/392) |
| M21 | ضرب/قسمة زائدة | `target.max(1)` (adaptive/mod.rs:632-637) |
| M23/L12 | cooldown التقارب لا يُعاد ضبطه | convergence.rs:78-86 |
| H12 | `is_rate_limited` صحيح للأبد عند `None` | يرجع false عند None (server_profiler.rs:138-146) |

### 3.2 قائم ومؤكد — يجب إصلاحه (المرجع لكل بند: معرفات التدقيق)

| المعرف | المشكلة | الموقع |
|---|---|---|
| H1/M27 | **Pause = بلا حد (تحميل بكامل السرعة)** | bandwidth.rs:76-97 + transfer.rs:712-716 |
| M6 | حدود السرعة لا تُطبّق حياً | easy_config.rs:591-604 + transfer.rs |
| A15 (جديد) | `low_speed_limit 500 B/s / 15s` افتراضياً يقطع التحميلات البطيئة | easy_config.rs:646-647 |
| M1/L1 | jitter = 0 دائماً + 4 تطبيقات retry متوازية | retry.rs:69-74 + direct.rs:370-390 + policy_engine |
| H3 | `hlsDashDownload` مستحيل التحقق | engine_capabilities.rs:1504 |
| H4 | `CANDIDATE_CURL_RAW_OPTIONS` فارغ → rawOptions مرفوض دائماً | engine_capabilities.rs:205 |
| H2/M4 | المجدول level-triggered + `return` بدل `continue` | scheduler.rs:151-153 + routes/engine.rs:649-691 |
| M9 | سباق `TelemetryBus::report_speed` + underflow + ركود | adaptive/mod.rs:147-161 |
| H9 | `.unwrap()` على find في segment_controller | segment_controller.rs:208-209, 238-239 |
| M10/L17 | Rebalance يعيد تحميل بايتات متداخلة + Split عند 0 | segment_controller.rs:454-480, adaptive/mod.rs:564-613 |
| L13 | `per_connection_ceiling` يُداس كل عينة | server_profiler.rs:162-165 |
| H16 | `set_alive` يعد الاتصالات النشطة خطأً | adaptive/mod.rs:209-219 |
| M11 | `BufferManager::recommend` و `ResourceManager::update_network` ميتان | buffer_manager.rs:47 |
| 1.2 | `DieOrchestrator`/`UnifiedProfileStore` لا يُكتب إليهما أبداً | die_orchestrator.rs + transfer.rs:87-102 |
| M7/L14 | إضافة مرايا مكررة + تعليم الأولى فقط | mirror.rs:55-60, 102-113 |
| M8 | resource monitor وهمي على غير Windows + WARN لكل عينة | resource_monitor.rs:214-281 |
| M12/M31 | plugin API: بلا runtime، بلا فحص api_version | plugin_api.rs |
| H10/H13 | profile_store يبتلع أخطاء الكتابة/الفتح | profile_store.rs:328-354 |
| H19 | `update_size()` لا يعيد توزيع الحصة | priority_queue.rs:144-155 |
| H20 | `Merge(0,1)` مُرمّز | policy_engine.rs:298-303 |
| H21 | `to_adaptive_config` يتجاوز min_connections | profiles.rs:149-167 |
| H18 | `is_disk_bottlenecked` يقارن MB/s مع bytes | resource_manager.rs:161-163 |
| M3 | EventBus `publish_depth` عام لا لكل خيط + طابور غير محدود | event_bus.rs |
| M2 | `ThreadPool::with_size(0)` ينهار | thread_pool.rs:74-78 |
| M5 | قفل external_tools عبر init بطيء | daemon/mod.rs:267-270 |
| M4 | عميل HTTP احتياطي بلا timeout | daemon/mod.rs:177-182 |
| M3(daemon) | Tokio Runtime ثانٍ + عميل blocking لـ Telegram | daemon/mod.rs:299, telegram.rs:182 |
| M10 | `plan.clone()` عند كل redirect | transfer.rs:372 |
| M12 | نتيجة `easy.timeout()` مهملة | transfer.rs:382 |
| M13 | عدد القطع ≠ plan.connections | transfer.rs:958,1024 |
| M15 | `next_token` يتشبع عند usize::MAX | multi.rs:240-241 |
| M17 | 6+ نتائج `easy.*()` مهملة | easy_config.rs |
| M22 | تقييم `segment_ctrl` مكرر | adaptive/mod.rs:538-566 vs 583-607 |
| M27 | قفل `task_limits` مرتين | bandwidth.rs:79-90 |
| M28 | `active.max(1)` بعد فحص `active==0` | priority_queue.rs:193-195 |
| M29 | `(total*2).max(total)` | config.rs:108 |
| M30 | HeaderContains substring بدل eq_ignore_ascii_case | rules.rs:148-153 |
| M25/L7 | `recovery_window_start` يُكتب ولا يُقرأ | self_healing.rs:49,64 |
| M26/L10 | `_mem_gb` وغيرها | adaptive_connections.rs:24 |
| L3 | mac sleep عبر `systemctl` | routes/engine.rs:686-691 |
| L8 | UrlExtension: URL صغير الحالة والامتداد لا | rules.rs:136-141 |
| L15 | `parse_rate_to_bytes` ينفجر مع non-ASCII | easy_config.rs:57-75 |
| L18 | ادعاءات قدرات غير موثقة | engine_capabilities.rs:763, 804-808, 841 |
| M16 | `next_token`/`collect_multi_errors` | multi.rs:240-241, 299-317 |
| 1.1/H5/H6/A7 | المحرك التكيفي + PolicyEngine + AdaptiveConnectionManager ميتة | راجع المرحلة 5 |

---

## 4. المراحل والتنفيذ

> **قاعدة عامة:** كل بند = إصلاح + اختبار وحدة (أو تكامل) يُثبت المشكلة (أحمر) ثم الحل (أخضر). كل مرحلة = PR واحد يبقي CI خضراء (`pnpm lint`, `lint:eslint`, `test`, `cargo check`, `cargo test`, `clippy -D warnings`, `rustfmt`, `audit:final`).

### المرحلة 0 — شبكات الأمان والأساس (تُنجز أولاً، وتُراجع مع كل مرحلة)

| البند | الوصف |
|---|---|
| 0.1 | تشغيل كامل بوابة الجودة الحالية وتوثيق الحالة الخضراء/الحمراء الأساسية. |
| 0.2 | **اختبار تطابق مفاتيح i18n:** اختبار Vitest يتحقق أن مفاتيح الـ 132 ملف لغة تطابق مفاتيح `en` (يُلتقط الانحراف الحالي أولاً). |
| 0.3 | **اختبار تطابق أدوات novaClient:** SSE delta merge + retry/abort logic + حماية `window` في `request()`. |
| 0.4 | إنشاء دليل `docs/testing/REPAIR_COVERAGE.md` يسجّل حالة أحمر/أخضر لكل بند في هذه الخطة (يتحدّث آلياً أو يدوياً مع كل مرحلة). |

### المرحلة 1 — سلامة البيانات ودورة الحياة (بقايا CRITICAL/HIGH)

| المعرف | الإصلاح | الاختبار |
|---|---|---|
| H10/H13 | `ProfileStore::save()`/`new()` يرجعان `Result`؛ المتصلون يتعاملون مع الخطأ (فشل ظاهر بدل صمت) | وحدة: فشل كتابة → `Err` معلن |
| H4 | ضم `JoinHandle` الخاصة بـ watchdog مع timeout في shutdown (لا فصل) | وحدة + تكامل إعادة تشغيل |
| C1 (انحدار) | اختبار يثبت أن `restart_daemon` لا يسرّب runtime (العد عبر مؤشر) | تكامل |
| C2 (انحدار) | اختبار أن quit يحفظ الحالة ويحذف ملف المنفذ | تكامل |
| H8 (انحدار) | اختبار ترتيب generation مقابل remove_file | وحدة |

### المرحلة 2 — دلالات التحميل الأساسية (الأهم للمستخدم)

| المعرف | الإصلاح | الاختبار |
|---|---|---|
| **H1 (Pause)** | `RateLimit { Unlimited, Limit(u64), Paused }` في bandwidth.rs + `rate_limit_for()`؛ حلقة القيادة تعمل كبوابة: عند `Paused` تنتظر فقط دون `multi.action`؛ إزالة دلالة `0 = بلا حد` | **تكامل:** بدء تحميل، `pause_all()`، تثبيت البايتات 1.5 ثانية، استئناف، اكتمال صحيح |
| **M6 (حد حي)** | `refresh_rate_limits()` في كل tick: حساب الحصة (global/per-task/engine override)، دفع `max_recv_speed` عبر `DerefMut` على easy الحية (مؤكد: يفعّل خلال نافذة قراءة واحدة) | **تكامل:** حد سخي → قياس سرعة → `set_task_limit(50KB/s)` → سرعة ≤ 1.5× → رفع الحد → تعافٍ |
| A15 | إزالة الافتراضي `low_speed_limit(500)/15s` (أو جعله قابلاً للضبط فقط عند طلب صريح) | وحدة: تحميل بطيء شرعي لا يُقطع |
| **M1 (jitter)** | رياضيات أعداد صحيحة: `dur.as_nanos() % jitter_range.as_nanos()` + توحيد تطبيقات retry الأربعة في واحد | وحدة: 1000 عينة → جِتر غير صفري ومتباين |
| M12 | معالجة نتيجة `easy.timeout()` (وكل `easy.*()` في easy_config) — `?` أو `map_err` | وحدة: فشل setter → خطأ معلن |

### المرحلة 3 — القدرات والمجدول (صغيرة وسريعة الظهور للمستخدم)

| المعرف | الإصلاح | الاختبار |
|---|---|---|
| H3 | `formats` تُقسَّم على `,` وكل رمز يُفحص (`hls`/`dash`/`mp4`…) | وحدة: media capabilities تعلن hlsDashDownload عند توفرها |
| H4 | إما ملء `CANDIDATE_CURL_RAW_OPTIONS` بقائمة حقيقية (تُستخرج من `curl_version_info` + خريطة الخيارات) أو حذف ادعاء الدعم؛ يُختار الخيار الأول إن كانت الخريطة موجودة | وحدة: rawOptions مقبولة/مرفوضة حسب القائمة |
| H2/M4 | المجدول **edge-triggered**: تذكّر حالة الإجراء المُطلق لكل قاعدة/فاصل زمني (episode token)؛ و`continue` بدل `return` عند تعطيل أوامر الطاقة | وحدة: إطلاق Shutdown مرة واحدة رغم استمرار الشرط + بقاء باقي الإجراءات |
| L18 | التحقق أو الإزالة: `skipExisting`, `retryConnRefused`, `tcpFastOpen`, `happyEyeballsTimeoutMs` | وحدة: خريطة قدرات صادقة |
| L3 | مسار نوم mac عبر `pmset sleepnow` (وLinux عبر `systemctl`, وWindows عبر `SetSuspendState`) | وحدة: اختيار الأمر حسب المنصة |
| M30 | `HeaderContains` → `eq_ignore_ascii_case` على قيمة الهيدر | وحدة: تطابق حالة |
| L8 | تطبيع الامتداد المُعدّ وصغير الحالة قبل المطابقة + رفض regex غير صالح عند الإنشاء | وحدة |
| M29 | تبسيط `(total*2).max(total)` → `total * 2` | وحدة |
| M28 | إزالة `active.max(1)` الميت | وحدة |
| H19/H18 | `update_size()` يستدعي `reallocate()`؛ تصحيح وحدة مقارنة القرص (MB/s مقابل bytes) | وحدة |
| M19(انحدار) | اختبار ترتيب حذف snapshot/jobs | وحدة |

### المرحلة 4 — متطلبات المحرك التكيفي المسبقة (تُهبط قبل أي عمل على مسار التطبيق)

كل بند هنا مستقل ومعزول، ويُنجز في PR تحضيري واحد:

1. **M9 — سباق TelemetryBus:** إزالة `fetch_add/fetch_sub`؛ `report_speed` يخزّن الخانة فقط؛ `snapshot()` يعيد حساب `total_speed = Σ speeds` للخانات الحية؛ `aggregate_peak` عبر `fetch_max`.
   - *اختبار:* نُشر متزامن عبر خيوط → `snapshot().aggregate.total_speed` = مجموع الخانات، بلا underflow؛ `mark_completed` مرتين تُعد مرة.
2. **H9 — unwraps:** `let Some(x) = ... else { return None }` في مواضع find الأربعة.
   - *اختبار:* هندسة مشوهة → `evaluate()` يرجع `None` لا panic.
3. **M10 — Rebalance بالبادئة (نموذج prefix-segment):** `apply_plan` يقصّ `slow.end_byte`، يضع `slow.truncate_on_complete`، ويدرج قطعة بادئة `P = [slow.end_byte, fast.start_byte)` بدلاً من تحريك `fast.start_byte`؛ `fast` يبقى كما هو.
   - *اختبار ثبات:* بعد التطبيق، القطع مرتبة متجاورة بلا تداخل، `fast.downloaded` لم يتغير، Σ downloaded ≤ Σ total.
4. **merge_adjacent_segments:** `a.downloaded += b.downloaded` قبل إزالة b (الملفان يبقيان فيزيائياً).
   - *اختبار:* Σ المحفوظ قبل/بعد الدمج متساوٍ.
5. **SplitSegment at_byte:** ملء `at_byte` بنقطة منتصف فعلية (`start + downloaded + remaining/2`).
   - *اختبار:* نقطة القص داخل `[start+downloaded, end)`.
6. **L13 — per_connection_ceiling:** عدم تدويسه بعينة أحادية الاتصال؛ يُضبط فقط عند أول ملاحظة اتصالات متعددة (`observed_connection_count`).
   - *اختبار:* عينات متعددة الاتصالات لا تكسر السقف.
7. **M23/L12 — cooldown التقارب:** عند تحسّن (`ratio ≥ 1.05`) يُمسح `cooldown_until` ويُصفَّر العداد.
   - *اختبار:* تحسّن يلغي التهدئة.
8. **H16 — set_alive:** يرجع القيمة السابقة؛ `mark_completed/mark_failed` تُعدّ عند الانتقال من حي فقط.
   - *اختبار:* نداء مزدوج يُعد مرة.
9. **M11 — BufferManager/ResourceManager:** استدعاء `resource_manager.update_network(agg_speed, active_conns)` في خطوة التطبيق من `on_tick` (يفعّل `recommend`).
10. **1.2 — مسار كتابة DieOrchestrator:** `record_preflight(host, &profiler.get(host))` عند البداية + `record_telemetry(host, rtt, agg_speed, status)` عند كل تقييم؛ `save_if_dirty` مقيّد بالعلم.
    - *اختبار:* بعد دورة كاملة، `UnifiedProfileStore` يحتوي قيماً غير افتراضية.
11. **M27 — قفل مزدوج:** إعادة هيكلة `remove_task_limit` على مرحلتين (لا إمساك متزامن لـ speed_history و history_order).
12. **merge_parts truncate:** `FileWriter::merge_parts` يقصّ الأجزاء الأطول من المتوقع قبل الدمج (يبقى الأقصر خطأً).
    - *اختبار:* جزء أطول → يُقص ثم يُدمج؛ جزء أقصر → خطأ.
13. **types.rs:** `Segment` يكسب `start_byte/end_byte` مع `#[serde(default)]` (هندسة قابلة للاستئناف).
14. **easy_config.rs:** helper `set_live_rate(&mut Easy2Handle<SegmentWriter>, Option<u64>)`.

### المرحلة 5 — شحن المحرك التكيفي (التطبيق الحي)

**التصميم المعتمد (مختصر):**

```
tick كل 250ms → SegmentSet::on_tick:
  1. قراءة تقدم كل قطعة → telemetry_bus + segment_ctrl.update_progress
  2. engine.evaluate(&telemetry_bus)  (يتقيّم كل tick؛ evaluate يتقيّد داخلياً بـ 2s tick_interval)
  3. إذا AdjustConnections → redistribute_for_count(target)
  4. reconcile(engine.segments()) — diff هندسي خامل: spawn/suspend/truncate
  5. إسقاط أقفال engine_trackers قبل أي قفل curl_jobs (منع انقلاب AB-BA مع delete_task)
  6. refresh_rate_limits() + update_curl_task_progress + record_telemetry(DIE)
```

**بنود التنفيذ:**

| البند | الملف | التغيير |
|---|---|---|
| 5.1 | `multi.rs` | `CurlMultiGuard::remove(handle)`؛ Trait `SegmentedDrive { multi_mut, handle_count, sweep_finished, on_tick, check_errors }`؛ `drive_adaptive_socket/wait` مع بوابة `paused` وكسح الاكتمال؛ دوال القيادة القديمة تبقى كما هي للمسار الأحادي |
| 5.2 | **جديد** `curl/dynamic_transfer.rs` | `ActiveSegment` (id, start, end, file, progress, initial, handle, truncate_on_complete, finished, code)؛ `SegmentSet`؛ Trait `Transport { add, remove, set_rate }` (إنتاجي = guard، اختباري = مسجّل)؛ `spawn_segment/suspend_segment/truncate_file/reconcile/apply_decision/refresh_rate_limits/on_tick`؛ تحقق ثبات البلاطات البايتية بعد كل طفرة |
| 5.3 | `transfer.rs` | `run_segmented_libcurl` يبني `SegmentSet`، يزرع `segment_ctrl.reset_from_ranges(...)`، يقود عبر `drive_adaptive_*`؛ إعادة صياغة `update_curl_task_progress` لتفترض مفاتيح `HashMap<segment_id, u64>`؛ تمريرة قص قبل الدمج؛ فحص generation/status قبل طفرات الهندسة |
| 5.4 | `transfer_config.rs` | `adaptive: bool` (`bool_("adaptive").unwrap_or(true)`) + `adaptiveEvalMs` → `engine.set_tick_interval` |
| 5.5 | `dynamic_segments.rs` | `replace_segments(&[(id,start,end,downloaded,speed,active)])` — مرآة هندسة المحرك لواجهة الـ UI |
| 5.6 | `die_orchestrator.rs` | لا تغيير API؛ إضافة المتصلين (يُحدّ `save_if_dirty` بالعلم) |

**قواعد بايت محكمة:** ثابت `Σ active.finished_len + Σ active.(initial+progress clamped)` = كل البايتات الفريدة؛ كل ملف جزء = بلاطة `[start, start+len)` متجاورة؛ نقطة القص حصرية (`mid`: الأصلي `[start, mid-1]`، الذيل `[mid, end]`).

**قيود الكب:** `max_segments = min(64, max_connections_per_download)`؛ القصّ يرفض عند `remaining < 2*min_segment_bytes`؛ الدمج يرفض عند عدم كفاية المجموع؛ `redistribute_for_count` يغيّر الهندسة فقط عند اختلاف فعلي (reconcile = diff وليس rebuild).

**اختبارات المرحلة 5 (تكامل ضد خادم نطاق محلي — أدوات موجودة: `spawn_range_server`, `run_task_to_completion`, `test_state`):**

1. `adaptive_segmented_download_grows_and_completes` — 8 MiB، connections=2، evalMs صغير → عدد القطع يتجاوز الابتدائي أثناء التشغيل، والملف النهائي مطابق للبايت.
2. `pause_actually_stalls_bytes` — بعد بدء وتقدم، `pause_all()` → البايتات لا تتحرك → استئناف → اكتمال صحيح.
3. `live_rate_limit_change_takes_effect` — تغيير حد حي يُقاس فعلياً.
4. `segment_count_responds_to_growth_decision` — عدد الـ handles يزداد (عبر `SegmentSet::active_handles()` خلف `#[cfg(test)]`).
5. وحدة: reconcile مع `Transport` وهمي — split → add واحد + truncate؛ rebalance → بادئة add + truncate بلا إعادة إرسال `fast`؛ merge → لا عمليات؛ shrink → لا add جديد؛ ثبات البلاطات بعد كل طفرة.

### المرحلة 6 — قائمة المتوسط (MEDIUM) المتبقية

| المعرف | الإصلاح | الاختبار |
|---|---|---|
| M3 | `thread_local!` لـ `publish_depth` + طابور محدود drop-oldest | وحدة: ناشر بطيء لا يحجب البقية؛ حد الطابور |
| M2 | `with_size(0)` → `Err`؛ `spawn` يرجع `Result`؛ طابور محدود | وحدة: 0 يُرفض؛ تجاوز الطابور لا يفقد |
| M7/L14 | `add_mirror` upsert بالـ url (dedup)؛ `report_failure` يعلّم كل النسخ غير صحية؛ cooldown لكل مرآة لا لكل مهمة | وحدة |
| M8 | قراءة فعلية على Linux (`/proc/stat`, `/proc/self/io`) وmacOS (`host_statistics64`, `getrusage`) بدل الثوابت؛ إزالة WARN لكل عينة | وحدة (منصات مُنمّطة) |
| M12/M31 | قرار: إما تنفيذ تحميل/تفعيل plugins فعلي مع فحص `api_version`، أو إزالة سطح الـ API المضلِّل — يُختار **فحص api_version + توثيق الـ hooks كخريطة طريق** في هذه الجولة | وحدة: api_version مرفوض/مقبول |
| M10 | `plan.clone()` عند redirect → استنساخ الحقول المتغيرة فقط | وحدة |
| M13 | محاذاة عدد القطع مع `plan.connections` (أو `ranges.len()` بعد التغيير الديناميكي) | تكامل |
| M15/M16 | `next_token` يلتف بآمان؛ `collect_multi_errors` O(n) بخريطة token | وحدة |
| M17 | معالجة كل نتائج `easy.*()` المهملة | وحدة |
| M22 | تقييم `segment_ctrl` مرة واحدة لكل tick | وحدة |
| M5 | قفل `external_tools` عبر `discover_and_initialize` → قفل ذري per-step | وحدة |
| M4 | عميل HTTP احتياطي بكل timeouts | وحدة |
| M3(daemon) | توحيد runtime — خيط Telegram يعيد استخدام Runtime الرئيسي عبر `Handle` | وحدة |
| M25/L7 | `recovery_window_start` إما يُقرأ أو يُحذف | وحدة |
| M26 | تنظيف `_mem_gb` والثوابت الميتة | وحدة |
| L15 | `parse_rate_to_bytes` يتعامل مع non-ASCII بسلامة (chars أصلاً bytes) | وحدة |
| L16 | `AtomicU64::fetch_add` داخل Mutex → `store` عادي | وحدة |
| L17 | `from_u32(2)` → مطابقة صريحة بدل wildcard | وحدة |
| L18(قدرات) | جداول bandwidth المتداخلة: ترتيب صريح موثق | وحدة |
| L19 | توحيد ترتيب قفل profiles | وحدة |
| L20 | jitter يطرح أيضاً (توزيع متماثل) | وحدة |

### المرحلة 7 — الواجهة والإضافة والترجمة

| المعرف | الإصلاح | الاختبار |
|---|---|---|
| جديد | حماية `window` في `novaClient.request()` (بيئة غير متصفح) | وحدة Vitest |
| جديد | محمّل `translations.ts:288` يختار القاموس بـ `key === 'default'` صراحة | وحدة |
| جديد | `bridgeStore.setIsDegradedMode` تُزامن مع الحالة لا تستقل عنها | وحدة |
| جديد | `pl.ts` (الإضافة): إصلاح الترميز (`wys�,anych` …) | فحص ترميز آلي |
| جديد | `zh.ts` وغيرها: مفاتيح إنجليزية خام → تمريرة ترجمة (تُوثق كمتبقي خارج نطاق الكود) | — |
| 0.2 | اختبار تطابق مفاتيح 132 لغة | Vitest |
| جديد | `logging.rs`: `task_summaries`/`task_trace` تُبنى بلا استنساخ كامل للحلقة عند الطلب | اختبار أداء بسيط |

### المرحلة 8 — الجودة النهائية والتوثيق

| البند | الوصف |
|---|---|
| 8.1 | اختبارات `evaluate()` مع convergence/rebalancing (كانت I12-I14) — بعد المرحلة 5 تصبح اختبارات حية. |
| 8.2 | تحديث `AUDIT_REPORT.md` بحالة "أُصلح" لكل بند (سجل إغلاق). |
| 8.3 | `CHANGELOG.md` + ملخص README لقدرات المحرك التكيفي الفعلية. |
| 8.4 | تشغيل البوابة الكاملة: `pnpm lint`, `pnpm lint:eslint`, `pnpm test`, `pnpm run verify:capabilities`, `pnpm run audit:installer`, `pnpm run audit:final`, `cargo check`, `cargo test`, `clippy -D warnings`, `rustfmt --check`. |

---

## 5. استراتيجية الاختبارات (ملخص)

- **أحمر → أخضر:** كل إصلاح يبدأ باختبار يفشل (يثبت المشكلة) ثم يمر (يثبت الحل). يوثَّق الحالتان في `docs/testing/REPAIR_COVERAGE.md`.
- **طبقات:** وحدة (مكوّن) → تكامل (خادم نطاق محلي + مسار تحميل حقيقي) → E2E (Playwright موجود) → بوابة CI.
- **أدوات موجودة تُعاد:** `spawn_range_server`, `run_task_to_completion`, `test_state` (transfer.rs:2214-2342) — تُعمَّم لخدمة اختبارات المرحلة 5.
- **منصات:** اختبارات المنصة (mac sleep, /proc/stat, sysinfo) تُنمّط عبر cfg ولا تتطلب أجهزة حقيقية في CI.
- **لا اختبار مكسور يُسلم:** أي PR يتجاوز بوابة CI يُرفض قبل الدمج.

---

## 6. خريطة تغيير الملفات (إجمالي)

**Rust — src-tauri/src:**
- `daemon/engine/bandwidth.rs` — RateLimit enum + rate_limit_for + فك القفل المزدوج.
- `daemon/engine/adaptive/mod.rs` — TelemetryBus، set_alive، at_byte، وصل BufferManager.
- `daemon/engine/adaptive/segment_controller.rs` — unwraps، prefix-rebalance، دمج المحفوظات، reset_from_ranges، truncate_on_complete/prefix_of، سقف max_segments.
- `daemon/engine/adaptive/convergence.rs` — مسح cooldown عند التحسّن.
- `daemon/engine/adaptive/server_profiler.rs` — per_connection_ceiling، observed_connection_count.
- `daemon/engine/adaptive/resource_monitor.rs` — قراءات Linux/macOS حقيقية.
- `daemon/engine/die_orchestrator.rs` — المتصلون (لا API).
- `daemon/engine/policy_engine.rs` — Merge(0,1) بالمعرّف الصحيح.
- `daemon/engine/priority_queue.rs` — update_size→reallocate، إزالة الميت.
- `daemon/engine/profiles.rs` — min_connections، Result من save.
- `daemon/engine/profile_store.rs` — Result من save/new.
- `daemon/engine/resource_manager.rs` — إصلاح وحدة القرص، update_network.
- `daemon/engine/self_healing.rs` — recovery_window_start.
- `daemon/engine/mirror.rs` — upsert + تعليم كل النسخ + cooldown لكل مرآة.
- `daemon/engine/plugin_api.rs` — فحص api_version.
- `daemon/engine/event_bus.rs` — thread_local depth + طابور محدود.
- `daemon/engine/thread_pool.rs` — with_size(0) رفض، spawn Result، طابور محدود.
- `daemon/engine/config.rs` — تبسيط (total*2).
- `daemon/engine/rules.rs` — امتداد صغير الحالة، HeaderContains، regex صالح.
- `daemon/engine/adaptive_connections.rs` — تنظيف/إزالة.
- `daemon/engine/dynamic_segments.rs` — replace_segments.
- `daemon/engine_capabilities.rs` — hlsDash، rawOptions، ادعاءات L18.
- `daemon/curl/transfer.rs` — SegmentSet، update_curl_task_progress بالمفتاح، بوابة pause، التكاملات.
- `daemon/curl/multi.rs` — remove، SegmentedDrive، drive_adaptive_*، next_token، O(n).
- `daemon/curl/easy_config.rs` — set_live_rate، إزالة low_speed الافتراضي، معالجة النتائج، parse_rate_to_bytes.
- `daemon/curl/dynamic_transfer.rs` — **جديد:** SegmentSet/Transport/ActiveSegment.
- `daemon/curl/transfer_config.rs` — adaptive + adaptiveEvalMs.
- `daemon/curl/task_api.rs` — (انحدارات فقط).
- `daemon/ytdlp.rs` — (انحدارات فقط).
- `daemon/mod.rs` — external_tools lock، عميل HTTP، Telegram runtime.
- `daemon/direct.rs` — merge_parts truncate.
- `daemon/types.rs` — start_byte/end_byte.
- `daemon/scheduler.rs` / `routes/engine.rs` — edge-trigger + continue + mac sleep.
- `daemon/telegram.rs` — runtime موحّد.
- `lib.rs` — (انحدارات C1/C2 فقط).
- `logging.rs` — تحسين O(n) للحلقات عند الطلب.

**Frontend — src/:**
- `api/novaClient.ts` — حماية window.
- `lib/i18n/translations.ts` — محمّل قاموس صريح.
- `store/bridgeStore.ts` — مزامنة degraded mode.
- `test/` — اختبار تطابق i18n + novaClient.

**Browser extension:**
- `src/i18n/locales/pl.ts` — إصلاح الترميز.

**Docs:**
- `REPAIR_PLAN.md` (هذه الوثيقة) — تُحدَّث حالة كل مرحلة.
- `docs/testing/REPAIR_COVERAGE.md` — سجل أحمر/أخضر.
- `AUDIT_REPORT.md` — سجل إغلاق.

---

## 7. التسلسل والاعتماديات

```
المرحلة 0 (أساس/شبكات أمان)
   │
   ▼
المرحلة 1 (سلامة بيانات) ──► المرحلة 2 (دلالات التحميل) ──► المرحلة 3 (قدرات/مجدول)
   │                               │
   ▼                               ▼
المرحلة 4 (متطلبات المحرك المسبقة) ──► المرحلة 5 (شحن المحرك التكيفي)
                                                │
                                                ▼
                            المرحلة 6 (متوسط) ──► المرحلة 7 (واجهة/i18n)
                                                │
                                                ▼
                                        المرحلة 8 (جودة نهائية)
```

- **المرحلة 4 تحجب 5** (لا عمل على مسار التطبيق قبل إصلاح سباق TelemetryBus و unwraps و byte-accounting).
- **المرحلة 2 تحجب اختبارات التكامل في 5** (بوابة pause وحدود حية يجب أن تكون صحيحة أولاً لأن اختبارات 5 تعتمد عليها).
- المراحل 3 و6 و7 مستقلة عن بعضها ويمكن أن تتقاطع إذا رغبت.
- كل مرحلة تبدأ وتنتهي بحالة CI خضراء.

---

## 8. سجل المخاطر

| الخطر | الاحتمال | الأثر | التخفيف |
|---|---|---|---|
| Deadlock AB-BA: engine_trackers ↔ curl_jobs في on_tick | منخفض | عالٍ | إسقاط أقفال engine قبل curl_jobs؛ تعليق توثيقي في الموقعين؛ مراجعة |
| تذبذب عدد الاتصالات (oscillation) | متوسط | متوسط | cooldown التقارب + max_adjustments_per_minute + debounce 5s + reconcile كـ diff |
| حسابات بايت خاطئة عند القص/الدمج قرب نهاية الملف | متوسط | عالٍ | ثبات البلاطات بعد كل طفرة + رفض قص `remaining < 2*min` + تمريرة قص قبل الدمج |
| Watchdog قديم يطوّر الجيل الجديد | منخفض | عالٍ | فحص generation/status قبل طفرات الهندسة (مؤكد موجود للمسارات الأخرى) |
| تخفيض الاتصالات ليس فورياً (soft) | منخفض | منخفض | موثق كقيد إصدار أول؛ خيار صلب خلف flag بميزانية إعادة تحميل |
| انحدار المسار الأحادي/غير المعروف الحجم | منخفض | عالٍ | دوال القيادة القديمة تبقى؛ المحرك فقط عند `segmented && total_size ≥ min`؛ اختبارات تكامل للمسارين |
| توافق مخطط الاستئناف | منخفض | متوسط | `#[serde(default)]` على الحقول الجديدة؛ اختبار تحميل لقطة قديمة |
| أخطاء i18n/UI أثناء تدفق التنفيذ | منخفض | منخفض | اختبار تطابق المفاتيح في 0.2 |

---

## 9. تعريف "تم" (Definition of Done)

1. كل بند في الجدول أعلاه له اختبار أحمر→أخضر موثق في `docs/testing/REPAIR_COVERAGE.md`.
2. المحرك التكيفي يعمل في الإنتاج: قرارات تُطبق على easy handles الحية وتُقاس في اختبارات التكامل (نمو القطع، توقف حقيقي عند pause، حدود حية).
3. لا توجد ادعاءات قدرات كاذبة في `engine_capabilities.rs`.
4. لا توجد `#[allow(dead_code)]` لكتل قرارات المحرك إلا مع تبرير مكتوب (أو إزالة).
5. بوابة الجودة كاملة خضراء (القسم 4/المرحلة 8.4).
6. `AUDIT_REPORT.md` و `code-audit-report.md` محدّثان بسجل إغلاق، و`CHANGELOG.md` يوثق التغييرات.

---

## 10. قرارات مفتوحة للمراجعة

1. هل يُفعّل المحرك التكيفي افتراضياً (الاقتراح: نعم، للتحميلات المجزأة ذات الحجم المعروف) أم خلف flag في الإصدار الأول؟
2. هل يُقبل القيد "التخفيض بالاستكمال الطبيعي" للتوصيل الأول، مع خيار الصلب لاحقاً؟
3. هل نسمح بالتجاوز المؤقت لطول ملف الجزء (مع القص عند الاكتمال) — الاقتراح: نعم (البديل يعيد تحميل بيانات).
4. هل تُضاف `start_byte/end_byte` لمخطط `Segment` المستمر (الاقتراح: نعم، `serde(default)`).
5. مصير سطح Plugin API: فحص api_version + خارطة طريق توثيق، أم حذف السطح المضلِّل؟

---

*هذه الخطة قابلة للتنفيذ مرحلةً بمرحلة؛ ابدأ بالمرحلة 0 ثم 1 عند الاعتماد.*
