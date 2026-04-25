# Design Principles Reference

Default principles applied during a `/design-qa:review` pass. Override per-project via `.claude/design-qa/reviewer.json` and `pageTypePriorities`.

## Visual hierarchy

One thing should be the most important thing on screen at a time. Hero pages need a single dominant element. Product pages need a clear primary action.

Anti-pattern: 3+ CTAs of equal weight competing above the fold.

## Typography scale

Use a defined type scale, not arbitrary sizes. If `brand.tokens.fontSizes` is set, every visible text element's `font-size` should be in that array.

Anti-pattern: 14px, 15px, 17px, 18px all on the same page (the design system has 14, 16, 18 — pick one).

Body copy should be ≥ 16px on desktop, ≥ 14px on mobile. Captions ≥ 12px.

## Spacing rhythm

Spacing should follow a system (4-based, 8-based, or t-shirt-sized). Off-token spacing reads as sloppy.

Anti-pattern: `padding: 13px 27px`. Use `12px 24px` or `16px 32px`.

## Touch targets

Mobile (≤ 768px): every interactive element ≥ 44×44 CSS pixels (Apple's HIG) or ≥ 48×48 (Material). Hit area can extend beyond the visual via padding or `::before`.

Blocker: dense settings lists where each row is < 40px tall.

## Color and contrast

WCAG 2.2 AA: 4.5:1 for normal text, 3:1 for large text (≥ 18pt or ≥ 14pt bold), 3:1 for UI component boundaries.

Test contrast in both light and dark themes. Test in hover/focus states. Brand grays often fail in hover states.

Disabled states are exempt from contrast rules (WCAG specifically excludes them) but should still be visually distinct from enabled.

## Interaction states

Every interactive element needs visible: default, hover, focus, active, disabled. Focus indicator must have ≥ 3:1 contrast against the adjacent background.

Anti-pattern: `outline: none` without a replacement focus style.

## Motion

Respect `prefers-reduced-motion`. If a user has it set, no parallax, no auto-playing video, no animations longer than 200ms. Only meaningful transitions remain (e.g., disclosure expands).

## Forms

Labels above inputs (left-aligned), not placeholder-as-label. Error messages adjacent to the field (not at the bottom of the form). Inline validation on blur, not on every keystroke.

Anti-pattern: floating labels that overlap input text.

Anti-pattern: red asterisk for "required" without explaining what the asterisk means.

## Loading and empty states

Every async surface needs three states: loading, empty, error.

Anti-pattern: "No data" as the only message in an empty state. Tell the user what should be there and how to get it.

## AI slop patterns to flag

Pervasive on AI-generated UIs. Mark as Medium severity at `balanced` strictness, High at `strict`.

- Unnecessary gradient backgrounds on buttons.
- Emoji used in place of icons (✨ 🚀 ⚡ next to feature labels).
- Faux-3D shadows on cards (multiple stacked `box-shadow` layers, blur > 20px).
- Glassmorphism applied indiscriminately (more than 2 elements with `backdrop-filter: blur`).
- Generic "AI startup" copy: "Synergize," "Unlock," "Transform your...," "AI-powered..."
- Decorative gradients behind every section heading.
- "Card with icon + title + 1-line description" repeated 6 times in a feature grid.

## Brand fidelity

If `brand.tokens` is provided, sample the rendered DOM and verify ≥ 90% of elements use tokens. Below 90% means the design system is leaking.

If `brand.voice` lists "no jargon," scan visible copy for: synergize, leverage, ecosystem, robust, scalable, seamless, cutting-edge, best-in-class, world-class, revolutionary, game-changing, unlock, empower (without an object). Flag each occurrence.

## When to be lenient

A design pass at `lenient` strictness is for early prototypes. Only flag:
- WCAG-A and clear WCAG-AA violations.
- Broken layouts (overflow, content cut off).
- Severe contrast failures.
- Performance scores < 50 on mobile.

A design pass at `strict` is for shipping marketing pages. Flag everything above plus:
- Off-token spacing.
- Off-token font sizes.
- Voice violations.
- All AI slop patterns.
- Touch targets < 44px.
- Typography contrast issues even at 4.5:1 (favor 7:1 for body copy on white).

`balanced` is the default and what most reviews should run as.
