---
name: Analog Companion
colors:
  surface: '#161311'
  surface-dim: '#161311'
  surface-bright: '#3c3836'
  surface-container-lowest: '#100e0c'
  surface-container-low: '#1e1b19'
  surface-container: '#221f1d'
  surface-container-high: '#2d2927'
  surface-container-highest: '#383432'
  on-surface: '#e9e1dd'
  on-surface-variant: '#d8c3af'
  inverse-surface: '#e9e1dd'
  inverse-on-surface: '#33302d'
  outline: '#a08e7b'
  outline-variant: '#534435'
  surface-tint: '#ffb963'
  primary: '#ffb963'
  on-primary: '#472a00'
  primary-container: '#d4860a'
  on-primary-container: '#472900'
  inverse-primary: '#875300'
  secondary: '#5bdbc1'
  on-secondary: '#00382e'
  secondary-container: '#00a68e'
  on-secondary-container: '#00332a'
  tertiary: '#9acbff'
  on-tertiary: '#003355'
  tertiary-container: '#679bd0'
  on-tertiary-container: '#003154'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#ffddb9'
  primary-fixed-dim: '#ffb963'
  on-primary-fixed: '#2b1700'
  on-primary-fixed-variant: '#663e00'
  secondary-fixed: '#7af8dc'
  secondary-fixed-dim: '#5bdbc1'
  on-secondary-fixed: '#00201a'
  on-secondary-fixed-variant: '#005144'
  tertiary-fixed: '#d0e4ff'
  tertiary-fixed-dim: '#9acbff'
  on-tertiary-fixed: '#001d34'
  on-tertiary-fixed-variant: '#004a79'
  background: '#161311'
  on-background: '#e9e1dd'
  surface-variant: '#383432'
typography:
  display-lg:
    fontFamily: DM Serif Display
    fontSize: 48px
    fontWeight: '400'
    lineHeight: '1.1'
  display-md:
    fontFamily: DM Serif Display
    fontSize: 32px
    fontWeight: '400'
    lineHeight: '1.2'
  headline-sm:
    fontFamily: DM Serif Display
    fontSize: 24px
    fontWeight: '400'
    lineHeight: '1.3'
  body-lg:
    fontFamily: DM Sans
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.6'
  body-md:
    fontFamily: DM Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.5'
  body-sm:
    fontFamily: DM Sans
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.4'
  label-lg:
    fontFamily: DM Sans
    fontSize: 14px
    fontWeight: '500'
    letterSpacing: 0.05em
  label-md:
    fontFamily: DM Sans
    fontSize: 12px
    fontWeight: '500'
    letterSpacing: 0.02em
  display-lg-mobile:
    fontFamily: DM Serif Display
    fontSize: 36px
    fontWeight: '400'
    lineHeight: '1.1'
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  gutter: 16px
  margin-mobile: 20px
  margin-desktop: 40px
---

## Brand & Style

This design system is built on the philosophy of "Analog Warmth." It aims to reduce the digital friction often felt by ADHD users by grounding the interface in the tactile, comforting aesthetic of high-quality stationery and dimly lit workspaces. The experience should feel like a trusted leather-bound notebook—permanent, forgiving, and quiet.

The style rejects modern digital trends like glassmorphism or neon glows in favor of a flat, structured, and deeply matte aesthetic. Visual hierarchy is established through tonal layering and high-quality serif typography rather than shadows or depth effects. The goal is to create a focused "sanctuary" that minimizes overstimulation while providing a sense of ritual and reward.

## Colors

The palette is anchored in deep, warm earth tones to reduce eye strain and provide a "lamp-lit" atmosphere. 

- **Primary & Secondary:** Reward Amber (#D4860A) is used for celebratory moments and habit completions. Fresh Start Teal (#00A68E) denotes new entries and positive momentum.
- **Surface Strategy:** We use a tonal stacking system. The deepest color is the background, with progressively lighter/warmer browns for cards and interactive inputs to indicate "clickability" without using shadows.
- **Typography Colors:** Pure white is avoided. Primary Cream (#E8DFD0) provides high legibility with a soft, paper-like feel against the dark backgrounds.

## Typography

The typography pairing creates a balance between editorial elegance and utilitarian clarity.

- **Display Serif:** Use *DM Serif Display* (Italic) for all major titles and empty-state prompts. This evokes the feeling of a printed journal or a classic novel, providing a sense of permanence to the user's thoughts.
- **UI Sans:** Use *DM Sans* for all functional text, body copy, and data. It is geometric and clean, ensuring that even in "brain dump" sessions, the text remains highly legible and organized.
- **Rhythm:** Heavy use of vertical rhythm is encouraged. Large serif headers should always have ample "breathing room" (margins) to prevent visual clutter.

## Layout & Spacing

The layout follows a "Notebook Philosophy": generous margins act like the edges of a physical page. 

- **Grid:** A 12-column grid is used for desktop, while a single-column fluid layout with 20px side margins is preferred for mobile to maximize focus.
- **Rhythm:** All spacing must be a multiple of 4px. Use 24px (lg) spacing between distinct content blocks and 8px (sm) between related items within a card.
- **Containment:** Content should be centered with a maximum readable width of 720px for text-heavy areas, mimicking the proportions of a standard journal.

## Elevation & Depth

In this design system, depth is communicated through **Tonal Layers** and **Subtle Outlines** rather than shadows.

- **The Stack:** The Z-axis is defined by color luminosity. The background is the lowest layer (#1C1917), cards sit one level above (#252017), and interactive inputs/modals sit at the highest level (#2E2A1F).
- **Outlines:** All containers and cards feature a 1px solid border at `rgba(255, 255, 255, 0.06)`. This provides a "paper edge" definition that is visible but non-distractive.
- **No Shadows:** Absolutely no box-shadows or drop-shadows are used. Depth is purely a matter of color value contrast.

## Shapes

The shape language combines the structural reliability of a notebook with the approachability of a companion.

- **Cards:** Use a consistent 12px radius to soften the interface without making it feel "bubbly."
- **Inputs:** A slightly tighter 8px radius for text fields and checkboxes to maintain a sense of precision.
- **Buttons:** All primary actions use "Pill" shapes (999px radius), making them distinct from the rectangular layout of the content and inviting interaction.
- **Persona Orb:** The primary brand element/companion is a 44px perfect circle in Reward Amber (#D4860A), always present as a focal point.

## Components

- **Buttons:** 
    - *Primary:* Pill-shaped, Background: Reward Amber, Text: Neutral Black (for contrast).
    - *Secondary:* Pill-shaped, Border: 1px Cream, Text: Cream. No fill.
- **Cards:** Background: #252017, Border: 1px rgba(255,255,255,0.06), Radius: 12px. Padding: 20px.
- **Input Fields:** Background: #2E2A1F, Radius: 8px. Text should use Primary Cream. Placeholder should use Muted (#4A4438).
- **Habit Chips:** Small, 8px radius or pill. Use Soft Steel Blue (#6B9FD4) for "in progress" and Fresh Start Teal (#00A68E) for "completed."
- **Checkboxes:** 8px radius squares. When checked, fill with Reward Amber and use a dark check icon.
- **The Companion Orb:** A 44px amber circle that pulsates slightly (opacity 0.8 to 1.0) during active focus sessions.
- **Lists:** Items should be separated by 1px dividers (#3E3830) rather than gaps, maintaining the "lined paper" feel.