---
name: reviewer-persona
description: Use whenever the design-qa agent needs to apply project-specific design principles, brand voice, page-type priorities, or strictness level to a review. Loads .claude/design-qa/reviewer.json.
---

# Reviewer Persona

This skill defines HOW the design-qa agent reviews — strictness, brand-aware rules, page-type priorities, and what to ignore.

## Loading

Read the reviewer config at `${user_config.reviewerConfigPath}` (default `.claude/design-qa/reviewer.json`).

If absent, copy `${CLAUDE_PLUGIN_ROOT}/templates/reviewer.default.json` to that path and use it. Notify the user that the default is in use and they can customize.

## Schema

```json
{
  "strictness": "lenient | balanced | strict",
  "brand": {
    "name": "Acme",
    "voice": ["clear", "warm", "no jargon"],
    "tokens": {
      "spacing": [4, 8, 12, 16, 24, 32, 48, 64],
      "radius": [4, 8, 12, 16, 9999],
      "fontFamilies": ["Inter", "Geist Mono"],
      "fontSizes": [12, 14, 16, 18, 20, 24, 30, 36, 48, 60]
    },
    "antiPatterns": [
      "gradient buttons",
      "emoji as icons",
      "faux-3D shadows",
      "unnecessary glassmorphism"
    ]
  },
  "pageTypePriorities": {
    "marketing": ["typography", "hero clarity", "CTA hierarchy", "social proof"],
    "product": ["accessibility", "interaction states", "error handling", "data density"],
    "checkout": ["accessibility", "error states", "trust signals", "performance"],
    "auth": ["error states", "field validation", "social-login affordance"],
    "settings": ["scannability", "destructive-action affordance", "save/cancel clarity"]
  },
  "excludeRules": ["color-contrast-enhanced"],
  "hooks": true,
  "breakpointPagesAllowed": {
    "marketing": ["/", "/about", "/pricing"],
    "product": ["/dashboard", "/projects/:id"],
    "checkout": ["/checkout", "/checkout/confirm"]
  }
}
```

## How strictness changes behavior

- **lenient:** Only flag things that hurt usability or accessibility. Do not flag style inconsistencies. Do not flag "AI slop" patterns unless they're pervasive.
- **balanced** (default): Flag usability + a11y + brand-token violations. Note style inconsistencies but mark them as Nitpicks.
- **strict:** Flag every spacing inconsistency, every off-token color, every off-token font size. Mark these as Medium or High.

## How brand tokens are validated

For each screenshot, use `browser_evaluate` to extract computed styles for:
- All elements with `padding`, `margin`, `gap` — check values are in `tokens.spacing`.
- All elements with `border-radius` — check values are in `tokens.radius`.
- All elements with `font-family` — check first family is in `tokens.fontFamilies`.
- All elements with `font-size` — check value is in `tokens.fontSizes`.

Sample 50 elements per page (full DOM walk is expensive). Report the % of elements that match the token system.

## How page-type priorities work

Detect page type from URL and content:
- `/`, `/about`, `/pricing`, `/blog/*` → marketing.
- `/dashboard`, `/app/*`, `/projects/*` → product.
- `/checkout/*`, `/cart`, `/order/*` → checkout.
- `/login`, `/signup`, `/auth/*` → auth.
- `/settings/*`, `/account/*`, `/profile/*` → settings.

If the page type is in `pageTypePriorities`, weight findings in those categories higher (move from Medium to High, etc.).

## Anti-pattern detection

For each screenshot, look for the patterns in `brand.antiPatterns`. Examples of how to spot them:

- **Gradient buttons:** A `<button>` whose computed `background-image` includes `linear-gradient`.
- **Emoji as icons:** Text content matching emoji unicode ranges in places where SVG icons should be.
- **Faux-3D shadows:** `box-shadow` with multiple stacked layers and high blur (>20px) on a non-modal element.
- **Glassmorphism:** `backdrop-filter: blur` on more than 2 elements per page.

Flag as Medium severity unless `strictness: strict` (then High).

## Voice rules applied to copy

For each visible CTA, heading, and body paragraph:
- If `voice` includes "no jargon": flag corporate terms (synergize, leverage, ecosystem, robust, scalable, seamless).
- If `voice` includes "clear": flag CTAs > 5 words.
- If `voice` includes "warm": flag overly clinical or impersonal phrasing.
- Always flag inconsistent capitalization of brand-name terms.

## Output

When called, return a section to the parent agent:

```markdown
### Reviewer persona pass (strictness: balanced)

**Token compliance:**
- Spacing: 87% of sampled elements match token system.
- Radius: 100%.
- Font sizes: 93%.
- Font families: 100%.

**Anti-patterns detected:**
- Glassmorphism on 4 elements (header nav, modal, toast, hero card). [Medium]
- Gradient button on `.cta-secondary`. [Medium]

**Voice issues:**
- "Synergize your workflow" — jargon (hero subhead). [High]
- "Click here to learn more about our pricing options" — wordy CTA (12 words). [Medium]

**Page-type priority hits (page detected: marketing):**
- Hero CTA visible above fold ✅
- Social proof present ✅
- Typography scale clear ⚠️ (3 different heading sizes used inconsistently)
```
