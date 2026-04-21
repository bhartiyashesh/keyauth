/**
 * TOTP field detection utilities.
 * Pure functions operating on Document -- testable with jsdom.
 * D-04: Three-layer heuristic detection.
 * D-06: Split-input (6 single-digit fields) handling.
 */

const OTP_KEYWORDS = ['otp', 'totp', '2fa', 'verification', 'code'];

/**
 * Detect a single TOTP input field using 3-layer heuristics (D-04).
 *
 * Layer 1: autocomplete="one-time-code" (most reliable, W3C standard)
 * Layer 2: input name/id/placeholder containing OTP keywords
 * Layer 3: single maxlength=6 input near a submit button in a form
 */
export function detectTOTPField(doc: Document): HTMLInputElement | null {
  // Layer 1: autocomplete="one-time-code"
  const autocompleteField = doc.querySelector<HTMLInputElement>(
    'input[autocomplete="one-time-code"]'
  );
  if (autocompleteField && !isExcludedType(autocompleteField)) return autocompleteField;

  // Layer 2: name/id/placeholder heuristics
  const allInputs = doc.querySelectorAll<HTMLInputElement>(
    'input[type="text"], input[type="tel"], input[type="number"], input:not([type])'
  );
  for (const input of allInputs) {
    if (isExcludedType(input)) continue;
    const identifier = `${input.name} ${input.id} ${input.placeholder}`.toLowerCase();
    if (OTP_KEYWORDS.some(kw => identifier.includes(kw))) {
      return input;
    }
  }

  // Layer 3: single 6-digit maxlength input near submit button
  for (const input of allInputs) {
    if (isExcludedType(input)) continue;
    const maxlen = input.maxLength > 0
      ? input.maxLength
      : parseInt(input.getAttribute('maxlength') || '0', 10);
    if (maxlen === 6) {
      const form = input.closest('form');
      if (form) {
        const hasSubmit = form.querySelector(
          'button[type="submit"], input[type="submit"], button:not([type])'
        );
        if (hasSubmit) return input;
      }
    }
  }

  return null;
}

/**
 * Detect split-input TOTP fields (D-06): 6 adjacent single-char inputs.
 * Looks for groups of 6 maxlength=1 inputs in an OTP-related container
 * or sharing the same parent element.
 */
export function detectSplitInputs(doc: Document): HTMLInputElement[] | null {
  const allSingleChar = Array.from(
    doc.querySelectorAll<HTMLInputElement>('input[maxlength="1"]')
  ).filter(input => !isExcludedType(input));

  if (allSingleChar.length < 6) return null;

  // Find groups of 6 in a container with OTP-related class/id
  for (let i = 0; i <= allSingleChar.length - 6; i++) {
    const group = allSingleChar.slice(i, i + 6);
    const container = group[0].closest(
      '[class*="otp"], [class*="code"], [class*="pin"], [class*="verify"], ' +
      '[id*="otp"], [id*="code"], [id*="pin"], [id*="verify"]'
    );
    if (container) {
      // Verify all 6 are in the same container
      const allInContainer = group.every(input => container.contains(input));
      if (allInContainer) return group;
    }

    // Fallback: check if all share the same parent
    const parent = group[0].parentElement;
    if (parent && group.every(input => input.parentElement === parent)) {
      return group;
    }
  }

  return null;
}

/**
 * Attempt to fill TOTP code into detected field(s).
 * Returns true if fill succeeded, false if no field found.
 */
export function attemptFill(doc: Document, code: string): boolean {
  // Try split inputs first (more specific match)
  const splitInputs = detectSplitInputs(doc);
  if (splitInputs) {
    fillSplitInputs(splitInputs, code);
    return true;
  }

  // Try single field
  const singleField = detectTOTPField(doc);
  if (singleField) {
    fillSingleInput(singleField, code);
    return true;
  }

  return false;
}

/**
 * Get the native value setter from the input's prototype chain.
 * Uses the input's own constructor prototype to work in both browser and jsdom contexts.
 * This bypasses React/Angular/Vue overrides on the value property.
 */
function getNativeValueSetter(input: HTMLInputElement): ((v: string) => void) | undefined {
  // Walk the prototype chain to find the native setter
  let proto = Object.getPrototypeOf(input);
  while (proto) {
    const descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
    if (descriptor?.set) return descriptor.set;
    proto = Object.getPrototypeOf(proto);
  }
  return undefined;
}

/**
 * Set input value using native setter (for framework compat) with event dispatch.
 */
function setInputValue(input: HTMLInputElement, value: string): void {
  const nativeSetter = getNativeValueSetter(input);
  if (nativeSetter) {
    nativeSetter.call(input, value);
  } else {
    input.value = value;
  }
  // Use the Event constructor from the element's own window context
  // to ensure compatibility with both jsdom (tests) and real browsers
  const EventCtor = input.ownerDocument.defaultView?.Event ?? Event;
  input.dispatchEvent(new EventCtor('input', { bubbles: true }));
  input.dispatchEvent(new EventCtor('change', { bubbles: true }));
}

/**
 * Fill a single TOTP input with the full code.
 * Uses native value setter to trigger React/Angular/Vue change detection.
 */
function fillSingleInput(input: HTMLInputElement, code: string): void {
  setInputValue(input, code);
}

/**
 * Fill split-input fields by distributing digits across individual inputs.
 * Each input gets one digit with event dispatch for framework compatibility.
 */
function fillSplitInputs(inputs: HTMLInputElement[], code: string): void {
  const digits = code.replace(/\s/g, '');
  inputs.forEach((input, i) => {
    if (i < digits.length) {
      setInputValue(input, digits[i]);
    }
  });
}

/** Exclude input types that should never be TOTP fields */
function isExcludedType(input: HTMLInputElement): boolean {
  const type = input.type?.toLowerCase();
  return type === 'password' || type === 'hidden' || type === 'email';
}
