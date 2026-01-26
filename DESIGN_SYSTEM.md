# Apricity CI - Design System Reference

## Color Tokens

### Status Colors (Semantic)
Use these for all status indicators to ensure consistency:

```css
/* Success (Passed Tests, Successful Runs) */
--color-success-50: #f0f8f4
--color-success-100: #c4dfce
--color-success-500: #3a8a5c  /* Primary */
--color-success-600: #2f7249  /* Hover */
--color-success-700: #276644  /* Active/Text */

/* Warning (Running, In Progress) */
--color-warning-50: #fef8eb
--color-warning-100: #f0d9a8
--color-warning-500: #c98a1d  /* Primary */
--color-warning-600: #b07718  /* Hover */
--color-warning-700: #8a5d12  /* Active/Text */

/* Danger (Failed Tests, Errors) */
--color-danger-50: #fef5f5
--color-danger-100: #f0c4c4
--color-danger-500: #c45c5c  /* Primary */
--color-danger-600: #a84848  /* Hover */
--color-danger-700: #8a3232  /* Active/Text */
```

### Usage Examples

#### Status Badges
```javascript
// ✅ CORRECT - Using semantic tokens
<span class="bg-success-50 text-success-700 ring-1 ring-success-100">Passed</span>
<span class="bg-warning-50 text-warning-700 ring-1 ring-warning-100">Running</span>
<span class="bg-danger-50 text-danger-700 ring-1 ring-danger-100">Failed</span>

// ❌ WRONG - Using generic Tailwind colors
<span class="bg-green-50 text-green-700">Passed</span>
<span class="bg-amber-50 text-amber-700">Running</span>
<span class="bg-red-50 text-red-700">Failed</span>
```

#### Status Icons
```erb
<!-- ✅ CORRECT -->
<i class="fas fa-check text-success-600"></i>
<i class="fas fa-circle-notch fa-spin text-warning-600"></i>
<i class="fas fa-times text-danger-600"></i>

<!-- ❌ WRONG -->
<i class="fas fa-check text-emerald-600"></i>
<i class="fas fa-circle-notch fa-spin text-amber-600"></i>
<i class="fas fa-times text-red-600"></i>
```

---

## Component Patterns

### Cards
```html
<!-- Standard card -->
<div class="bg-white rounded-xl border border-frost-200 p-6 shadow-sm">
  <h2 class="text-base font-semibold text-frost-800 mb-4">Card Title</h2>
  <!-- Content -->
</div>

<!-- Interactive card (hover effect) -->
<div class="bg-white rounded-xl border border-frost-200 p-6 shadow-sm 
            hover:border-sun-300 hover:shadow-md transition-all duration-200">
  <!-- Content -->
</div>
```

### Buttons
```html
<!-- Primary action -->
<button class="inline-flex items-center px-4 py-2 bg-sun-500 hover:bg-sun-600 
               text-white font-medium rounded-lg transition-colors shadow-sm">
  <i class="fas fa-play mr-2 text-xs"></i>
  Start Run
</button>

<!-- Secondary action -->
<button class="inline-flex items-center px-4 py-2 bg-white hover:bg-frost-50 
               text-frost-700 font-medium rounded-lg transition-colors 
               border border-frost-200">
  <i class="fas fa-arrow-left mr-2 text-xs"></i>
  Back
</button>

<!-- Danger action -->
<button class="inline-flex items-center px-4 py-2 bg-danger-500 hover:bg-danger-600 
               text-white font-medium rounded-lg transition-colors shadow-sm">
  <i class="fas fa-stop mr-2 text-xs"></i>
  Cancel
</button>
```

### Badges
```html
<!-- Info badge -->
<span class="text-xs px-3 py-1.5 bg-frost-50 text-frost-600 rounded-full 
             font-medium border border-frost-200">
  5 configured
</span>

<!-- Status badge with dot -->
<span class="inline-flex items-center gap-2 text-xs px-3 py-1.5 rounded-full 
             font-medium bg-success-50 text-success-700 ring-1 ring-success-100">
  <span class="w-1.5 h-1.5 rounded-full bg-success-500"></span>
  <span>Passed</span>
</span>
```

### Breadcrumbs
```html
<nav class="breadcrumb mb-6 flex items-center text-sm text-frost-500">
  <a href="/" class="hover:text-sun-600 transition-colors">Dashboard</a>
  <i class="fas fa-chevron-right mx-2 text-frost-300 text-xs"></i>
  <a href="/pipelines/blog" class="hover:text-sun-600 transition-colors">Blog</a>
  <i class="fas fa-chevron-right mx-2 text-frost-300 text-xs"></i>
  <span class="text-frost-700 font-medium">Run abc1234</span>
</nav>
```

### Section Headers
```html
<!-- With icon and description -->
<div class="flex items-center justify-between mb-6">
  <div>
    <h2 class="text-base font-semibold text-frost-800 flex items-center gap-2">
      <i class="fas fa-diagram-project text-sun-500"></i>
      Pipelines
    </h2>
    <p class="text-xs text-frost-500 mt-1">Configure and trigger your CI/CD workflows</p>
  </div>
  <span class="text-xs text-frost-500 bg-frost-50 px-3 py-1.5 rounded-full 
               font-medium border border-frost-200">
    5 configured
  </span>
</div>
```

### Form Controls
```html
<!-- Select dropdown -->
<select class="text-sm border border-frost-200 rounded-lg px-3 py-1.5 bg-white 
               focus:ring-2 focus:ring-sun-500/20 focus:border-sun-400 
               transition-all text-frost-600">
  <option value="all">All Status</option>
  <option value="success">Passed</option>
  <option value="failure">Failed</option>
</select>

<!-- Text input -->
<input type="text" 
       class="border border-frost-200 rounded-lg px-3 py-2 bg-white 
              focus:ring-2 focus:ring-sun-500/20 focus:border-sun-400 
              transition-all text-frost-700"
       placeholder="Search...">
```

---

## Typography Scale

```css
--text-xs: 0.75rem      /* 12px - Labels, captions */
--text-sm: 0.8125rem    /* 13px - Secondary text */
--text-base: 0.875rem   /* 14px - Body text (default) */
--text-md: 0.9375rem    /* 15px - Emphasized body */
--text-lg: 1rem         /* 16px - Section headers */
--text-xl: 1.125rem     /* 18px - Card titles */
--text-2xl: 1.375rem    /* 22px - Page titles */
```

### Usage
```html
<!-- Page title -->
<h1 class="text-2xl font-bold text-frost-800">Page Title</h1>

<!-- Section header -->
<h2 class="text-lg font-semibold text-frost-800">Section Header</h2>

<!-- Card title -->
<h3 class="text-base font-semibold text-frost-800">Card Title</h3>

<!-- Body text -->
<p class="text-base text-frost-700">Regular body text</p>

<!-- Secondary text -->
<p class="text-sm text-frost-500">Secondary information</p>

<!-- Caption / metadata -->
<span class="text-xs text-frost-400">Metadata or caption</span>
```

---

## Spacing Scale

```css
--space-1: 0.25rem   /* 4px */
--space-2: 0.5rem    /* 8px */
--space-3: 0.75rem   /* 12px */
--space-4: 1rem      /* 16px */
--space-5: 1.5rem    /* 24px */
--space-6: 2rem      /* 32px */
--space-8: 3rem      /* 48px */
```

### Common Patterns
- **Card padding**: `p-6` (32px)
- **Section spacing**: `mb-6` or `mb-8` (32-48px)
- **Button padding**: `px-4 py-2` (16px horizontal, 8px vertical)
- **Icon spacing**: `mr-2` or `gap-2` (8px)

---

## Border Radius

```css
--radius-sm: 0.375rem   /* 6px - Small badges */
--radius-md: 0.5rem     /* 8px - Buttons, inputs */
--radius-lg: 0.75rem    /* 12px - Cards (small) */
--radius-xl: 1rem       /* 16px - Cards (standard) */
--radius-2xl: 1.5rem    /* 24px - Hero cards */
```

---

## Shadows

```css
--shadow-sm: 0 1px 2px 0 rgba(0, 0, 0, 0.05)
--shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1)
--shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.1)
```

### Usage
- Default cards: `shadow-sm`
- Hover states: `shadow-md`
- Modals/popovers: `shadow-lg`

---

## Animation Durations

```css
/* Recommended values (not in CSS, use directly in classes) */
transition-all duration-200  /* Quick interactions (buttons, links) */
transition-all duration-300  /* Standard transitions (cards, modals) */
transition-all duration-500  /* Slow, dramatic transitions */
```

### Easing
Use `ease` (default) or `cubic-bezier(0.4, 0, 0.2, 1)` for smooth transitions.

---

## Icon Guidelines

### Sizes
- Navigation: `text-xs` (12px)
- Buttons: `text-xs` or `text-sm` (12-13px)
- Section headers: `text-base` (14px)
- Hero sections: `text-xl` to `text-3xl` (18-30px)

### Spacing
- Icon before text: `mr-2` (8px)
- Icon after text: `ml-2` (8px)
- Icon-only button: Ensure min-width/height of 36px

### Colors
- Active/primary: `text-sun-500` to `text-sun-600`
- Secondary/muted: `text-frost-400` to `text-frost-500`
- Status icons: Use semantic status colors

---

## Accessibility Checklist

- [ ] All interactive elements have minimum 44x44px touch target (mobile)
- [ ] Color contrast ratio >= 4.5:1 for normal text
- [ ] Color contrast ratio >= 3:1 for large text (18px+)
- [ ] Focus indicators are visible (3px outline)
- [ ] Icon-only buttons have `aria-label`
- [ ] Status is not conveyed by color alone (use icons + text)
- [ ] Forms have associated `<label>` elements
- [ ] Links are distinguishable from plain text

---

## Common Mistakes to Avoid

❌ **Don't mix generic Tailwind colors with custom tokens**
```html
<!-- Wrong -->
<span class="text-green-600">Success</span>
<span class="text-success-600">Success</span>

<!-- Right -->
<span class="text-success-600">Success</span>
<span class="text-success-600">Success</span>
```

❌ **Don't use arbitrary spacing values**
```html
<!-- Wrong -->
<div class="mb-7 px-5">

<!-- Right -->
<div class="mb-6 px-6">  <!-- Use design tokens -->
```

❌ **Don't forget hover/focus states**
```html
<!-- Wrong -->
<button class="bg-sun-500 text-white">Click</button>

<!-- Right -->
<button class="bg-sun-500 hover:bg-sun-600 text-white transition-colors">
  Click
</button>
```

❌ **Don't use different icon sizes in the same context**
```html
<!-- Wrong -->
<i class="fas fa-check text-sm"></i>
<i class="fas fa-times text-base"></i>

<!-- Right -->
<i class="fas fa-check text-sm"></i>
<i class="fas fa-times text-sm"></i>
```

---

## Quick Reference: Status Color Classes

| Status | Background | Text | Ring/Border | Icon |
|--------|------------|------|-------------|------|
| Success | `bg-success-50` | `text-success-700` | `ring-success-100` | `text-success-600` |
| Warning | `bg-warning-50` | `text-warning-700` | `ring-warning-100` | `text-warning-600` |
| Danger | `bg-danger-50` | `text-danger-700` | `ring-danger-100` | `text-danger-600` |
| Pending | `bg-frost-50` | `text-frost-600` | `ring-frost-200` | `text-frost-400` |
| Neutral | `bg-frost-50` | `text-frost-700` | `ring-frost-200` | `text-frost-500` |

---

## Resources

- Tailwind CSS: https://tailwindcss.com
- Font Awesome Icons: https://fontawesome.com/icons
- Mermaid Diagrams: https://mermaid.js.org
- Color Contrast Checker: https://webaim.org/resources/contrastchecker/
