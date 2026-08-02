# سجل تغطية الإصلاح — NOVA Download Manager

> هذا الملف هو سجل "أحمر → أخضر" لكل بند من بنود [REPAIR_PLAN.md](../../REPAIR_PLAN.md).
> آخر تحديث: 2026-08-01 — اكتمال المراحل 0-7.

## الحالة الأساسية (المرحلة 0.1 — 2026-08-01)

| البوابة | الحالة | ملاحظات |
|---|---|---|
| `pnpm lint` (tsc) | ✅ خضراء | 0 أخطاء |
| `pnpm lint:eslint` | ✅ خضراء | `--max-warnings 0` |
| `pnpm test` (Vitest) | ✅ خضراء | 314+ اختباراً |
| `cargo check` | ✅ خضراء | 0 أخطاء |
| `cargo test` | ✅ خضراء | 578/578 |
| `cargo clippy --all-targets -D warnings` | ✅ خضراء | 0 تحذيرات |
| `cargo fmt --check` | ✅ خضراء | |
| `pnpm run audit:final` | ✅ خضراء | |

## سجل البنود المكتملة

| المرحلة | المعرف | الحالة | اختبار أحمر → أخضر |
|---|---|---|---|
| 0 | إصلاح `React.act is not a function` (NODE_ENV في setup.ts) | ✅ | ✅ |
| 0 | 0.0 رفع التعديلات الأمنية (`logging.rs` + `native_host.rs`) | ✅ | — |
| 0 | 0.2 تطابق مفاتيح i18n (132 لغة) | ✅ | ✅ (134 اختبار) |
| 0 | 0.3 novaClient (SSE/retry/حماية window) + إصلاح 4xx retry | ✅ | ✅ (10 اختبارات) |
| 1 | H10/H13 ProfileStore يعيد Result (لا صمت) | ✅ | ✅ save_failure_is_reported |
| 1 | H4 ضم watchdog JoinHandle مع timeout | ✅ | ✅ |
| 1 | C1/C2 انحدار signal_shutdown | ✅ | ✅ |
| 1 | H8 انحدار stale generation | ✅ | ✅ stale_generation_does_not_overwrite |
| 1 | 1.2 مسار كتابة DieOrchestrator | ✅ | ✅ record_telemetry_persists_to_disk |
| 2 | H1 Pause يوقف البايتات فعلياً (RateLimit enum + بوابة القيادة) | ✅ | ✅ pause_actually_stalls_bytes_and_resume_completes |
| 2 | M6 حدود حية تُدفع فوراً (set_live_rate كل tick) | ✅ | ✅ live_rate_limit_change_takes_effect |
| 2 | A15 إزالة low_speed_limit(500/15s) الافتراضي | ✅ | ✅ |
| 2 | M1/L20 جِتر متماثل (أعداد صحيحة) | ✅ | ✅ jitter_is_symmetric_and_varied |
| 2 | M12 معالجة easy.*() المهملة | ✅ | ✅ set_live_rate_rejects_null_handle |
| 3 | H3 hlsDashDownload يفحص الرموز لا النص المركّب | ✅ | ✅ hls_dash_download_declared_when_mp4 |
| 3 | H4 CANDIDATE_CURL_RAW_OPTIONS حقيقي | ✅ | ✅ supported_raw_options_are_advertised |
| 3 | H2/M4 مجدول edge-triggered + continue | ✅ | ✅ rules_are_edge_triggered_not_level_triggered |
| 3 | L3 mac sleep عبر pmset | ✅ | ✅ |
| 3 | M30 HeaderContains exact | ✅ | ✅ header_contains_requires_exact |
| 3 | L8 امتداد صغير الحالة + regex صالح | ✅ | ✅ invalid_regex_rule_is_rejected |
| 3 | M29/M28 تبسيطات | ✅ | ✅ |
| 3 | H18 وحدة القرص | ✅ | ✅ disk_budget_is_bytes_per_second |
| 4 | M9 TelemetryBus خالٍ من السباق | ✅ | ✅ telemetry_speed_aggregate_is_recomputed |
| 4 | H9 unwraps → `?` | ✅ | ✅ |
| 4 | M10 rebalance بالبادئة (لا إعادة تحميل) | ✅ | ✅ rebalance_uses_prefix_segment_no_overlap |
| 4 | merge يحفظ المحفوظات | ✅ | ✅ merge_preserves_downloaded_progress |
| 4 | SplitSegment at_byte حقيقي | ✅ | ✅ split_at_byte_is_inside_remaining |
| 4 | L13 per_connection_ceiling ثابت | ✅ | ✅ |
| 4 | M23/L12 التحسّن يلغي التهدئة | ✅ | ✅ improvement_cancels_cooldown |
| 4 | H16 set_alive يعدّ الانتقالات مرة | ✅ | ✅ telemetry_set_alive_counts_transitions_once |
| 4 | M27 قفل remove_task_limit | ✅ | ✅ remove_task_limit_cleans_history |
| 4 | types.rs start_byte/end_byte (توافق مخطط) | ✅ | ✅ legacy_segment_without_byte_range |
| 4 | merge_parts يقصّ الأجزاء الأطول | ✅ | ✅ |
| 5 | **شحن المحرك التكيفي** — قرارات تُطبّق على easy handles الحية | ✅ | ✅ adaptive_segmented_download_grows_and_completes |
| 5 | transfer_config adaptive + adaptiveEvalMs | ✅ | ✅ |
| 5 | dynamic_segments.replace_segments | ✅ | ✅ |
| 5 | CurlMultiGuard::remove | ✅ | ✅ |
| 5 | record_preflight/record_telemetry في الإنتاج | ✅ | ✅ |
| 6 | M3 طابور pending_events محدود | ✅ | ✅ pending_events_queue_is_bounded |
| 6 | M2 with_size(0) → Err | ✅ | ✅ zero_size_pool_is_rejected |
| 6 | M7 mirror upsert + تعليم كل النسخ | ✅ | ✅ add_mirror_deduplicates + marks_all_copies |
| 6 | M15 التفاف next_token | ✅ | ✅ socket_token_wraps_at_max |
| 6 | M25 حذف recovery_window_start | ✅ | ✅ |
| 6 | M4 عميل HTTP احتياطي بلا timeout | ✅ | ✅ |
| 7 | novaClient بدون window | ✅ | ✅ works_without_window |
| 7 | translations.ts محمّل صريح | ✅ | ✅ |
| 7 | bridgeStore degraded mode متزامن | ✅ | ✅ setIsDegradedMode_syncs_status |
| 7 | pl.ts ترميز كامل | ✅ | فحص ترميز آلي |

## الجولة الثانية (2026-08-01) — سجل البنود المكتملة

| المرحلة | المعرف | الحالة | اختبار أحمر → أخضر |
|---|---|---|---|
| A | ترميز 10 ملفات لاتينية (de, es, fr, id, it, nl, pt, ro, sv, tr) — 0 U+FFFD | ✅ | فحص آلي fix-locale-encoding.mjs |
| A | ترقية فحص الترميز ليفشل CI على أي U+FFFD لاتيني | ✅ | nova-extension-feature-parity-check |
| B | M8 قراءات Linux حقيقية (meminfo/self.io/stat) + WARN مرة واحدة | ✅ | fallback_warning_logged_once + linux_proc_readings |
| B | M22 segment_ctrl.evaluate() مرة واحدة لكل tick | ✅ | |
| B | M13 attempted_segments = القطع الفعلية | ✅ | |
| B | M10 clone_with_url بدل plan.clone() | ✅ | |
| B | L17 from_u32 موثق | ✅ | from_u32_out_of_range_defaults_to_normal |
| B | M26 حذف _mem_gb | ✅ | |
| C | M3 Telegram يستخدم Handle مشترك (لا runtime ثانٍ) | ✅ | |
| C | logging بلا استنساخ حلقة كاملة | ✅ | task_summaries_aggregate + task_trace_* |
| C | set_live_rate الفاشل يُسجَّل مرة لا كل tick | ✅ | |
| C | L18 توثيق تداخل جداول bandwidth | ✅ | |
| D | M12 رفض api_version غير متوافق | ✅ | incompatible_api_version_is_rejected |
| D | zh.ts/zh_TW.ts ترجمة كل القيم الإنجليزية (sched_engine, rename, logging, progress…) | ✅ | i18n-parity zh/zh_TW |
| D | إضافة zh.ts: candidate.detail.* | ✅ | |

## متبقٍّ موثق (خارج نطاق الجولتين)

| البند | الحالة |
|---|---|
| bn/fa/th (الإضافة): 6,107 حرف U+FFFD — انهار النص غير اللاتيني بلا رجعة، يحتاج إعادة ترجمة يدوية | ⬜ متابعة — الفحص يُحذر (لا يكسر CI) |
| خريطة استرجاع أوسع للغات لاتينية إضافية إن ظهرت | ⬜ متابعة |
| المرحلة 8.1: اختبارات evaluate() حية مع convergence (أصبحت ضمن اختبارات المرحلة 5) | ✅ مغطاة |
