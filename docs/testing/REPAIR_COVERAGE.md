# سجل تغطية الإصلاح — NOVA Download Manager

> هذا الملف هو سجل "أحمر → أخضر" لكل بند من بنود [REPAIR_PLAN.md](../../REPAIR_PLAN.md).
> يُحدَّث مع كل مرحلة: بند = إصلاح + اختبار يثبت المشكلة (أحمر) ثم الحل (أخضر).

## الحالة الأساسية (المرحلة 0.1 — 2026-08-01)

| البوابة | الحالة | ملاحظات |
|---|---|---|
| `pnpm lint` (tsc) | ✅ خضراء | 0 أخطاء |
| `pnpm lint:eslint` | ✅ خضراء | `--max-warnings 0` |
| `pnpm test` (Vitest) | ✅ خضراء | 171/171 — **بعد إصلاح إعداد الاختبار** |
| `cargo check` | ✅ خضراء | 0 أخطاء |
| `cargo test` | ✅ خضراء | 541/541 |
| `cargo clippy --all-targets -D warnings` | ✅ خضراء | 0 تحذيرات |
| `cargo fmt --check` | ✅ خضراء | |
| `pnpm run audit:final` | ✅ خضراء | final-audit + capability-gating + installer + branding + extension |

### إصلاح أساسي اكتُشف في المرحلة 0.1

| البند | الحالة |
|---|---|
| **خلل بنية الاختبارات: `React.act is not a function`** — React 19.2.8 يصدّر `act` فقط في development build؛ Vitest يعمل بـ NODE_ENV=production. أُصلح بفرض `NODE_ENV=development` في `src/test/setup.ts`. | ✅ أُصلح — 18 اختباراً كان أحمر → أصبح أخضر |

### المرحلة 0.3 — إصلاح إضافي اكتُشفه الاختبار

| البند | الحالة |
|---|---|
| **أخطاء HTTP 4xx كانت تُعاد محاولتها** — `request()` في `novaClient.ts` كان يفحص `err.message.includes('HTTP 4')`، لكن عند وجود `error` في جسم الاستجابة كانت الرسالة المخصصة تحل محلها فيفقد الاختبار. أُصلح بالتحقق من كود الحالة عبر regex مباشرة، والرسالة الآن تحتفظ بكود الحالة. | ✅ أُصلح — اختبار "لا يعيد 4xx" كان أحمر → أخضر |

## سجل البنود

| المرحلة | المعرف | الحالة | اختبار أحمر → أخضر |
|---|---|---|---|
| 0 | 0.0 رفع التعديلات الأمنية (`logging.rs` + `native_host.rs`) | ✅ | — |
| 0 | 0.2 اختبار تطابق مفاتيح i18n (132 لغة) | ✅ | ✅ (134 اختبار) |
| 0 | 0.3 اختبارات novaClient (SSE/retry/حماية window) | ✅ | ✅ (9 اختبارات) |
| 0 | 0.4 إنشاء سجل التغطية | ✅ | — |
| 1 | H10/H13 ProfileStore يعيد Result | ⬜ | ⬜ |
| 1 | H4 ضم watchdog JoinHandle | ⬜ | ⬜ |
| 1 | C1/C2/H8 انحدارات | ⬜ | ⬜ |
| 2 | H1 Pause يعمل فعلياً | ⬜ | ⬜ |
| 2 | M6 حدود حية | ⬜ | ⬜ |
| 2 | A15 low_speed_limit | ⬜ | ⬜ |
| 2 | M1 jitter | ⬜ | ⬜ |
| 2 | M12 معالجة easy.*() | ⬜ | ⬜ |
| 3 | H3 hlsDashDownload | ⬜ | ⬜ |
| 3 | H4 rawOptions | ⬜ | ⬜ |
| 3 | H2/M4 مجدول edge-triggered | ⬜ | ⬜ |
| 3 | L18/L3/M30/L8/M29/M28/H19/H18 | ⬜ | ⬜ |
| 4 | M9 TelemetryBus | ⬜ | ⬜ |
| 4 | H9 unwraps | ⬜ | ⬜ |
| 4 | M10 rebalance prefix | ⬜ | ⬜ |
| 4 | merge_adjacent_segments | ⬜ | ⬜ |
| 4 | SplitSegment at_byte | ⬜ | ⬜ |
| 4 | L13/M23/H16/M11/1.2/M27 | ⬜ | ⬜ |
| 5 | شحن المحرك التكيفي (SegmentSet) | ⬜ | ⬜ |
| 6 | قائمة المتوسط المتبقية | ⬜ | ⬜ |
| 7 | الواجهة والإضافة والترجمة | ⬜ | ⬜ |
| 8 | الجودة النهائية والتوثيق | ⬜ | ⬜ |

*القاعدة: كل بند يُنقل من ⬜ إلى ✅ فقط عندما يكون إصلاحه + اختباره الأحمر→الأخضر موثقين هنا.*
