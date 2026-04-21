import { describe, it, expect, beforeEach } from 'vitest';
import { JSDOM } from 'jsdom';

import { detectTOTPField, detectSplitInputs, attemptFill } from '../content-utils';

describe('detectTOTPField', () => {
  let document: Document;

  beforeEach(() => {
    const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>');
    document = dom.window.document;
  });

  it('detects autocomplete="one-time-code" (Layer 1)', () => {
    document.body.innerHTML = '<input type="text" autocomplete="one-time-code" />';
    const field = detectTOTPField(document);
    expect(field).not.toBeNull();
    expect(field?.getAttribute('autocomplete')).toBe('one-time-code');
  });

  it('detects input with name containing "otp" (Layer 2)', () => {
    document.body.innerHTML = '<input type="text" name="otp_code" />';
    const field = detectTOTPField(document);
    expect(field).not.toBeNull();
  });

  it('detects input with id containing "2fa" (Layer 2)', () => {
    document.body.innerHTML = '<input type="text" id="2fa-input" />';
    const field = detectTOTPField(document);
    expect(field).not.toBeNull();
  });

  it('detects input with id containing "verification" (Layer 2)', () => {
    document.body.innerHTML = '<input type="tel" id="verification_code" />';
    const field = detectTOTPField(document);
    expect(field).not.toBeNull();
  });

  it('detects maxlength=6 input near submit button (Layer 3)', () => {
    document.body.innerHTML = `
      <form>
        <input type="text" maxlength="6" />
        <button type="submit">Verify</button>
      </form>
    `;
    const field = detectTOTPField(document);
    expect(field).not.toBeNull();
    expect(field?.getAttribute('maxlength')).toBe('6');
  });

  it('returns null when no TOTP field exists', () => {
    document.body.innerHTML = '<input type="text" name="username" />';
    const field = detectTOTPField(document);
    expect(field).toBeNull();
  });

  it('does not match password fields', () => {
    document.body.innerHTML = '<input type="password" name="code" />';
    const field = detectTOTPField(document);
    expect(field).toBeNull();
  });
});

describe('detectSplitInputs', () => {
  let document: Document;

  beforeEach(() => {
    const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>');
    document = dom.window.document;
  });

  it('detects 6 adjacent maxlength=1 inputs in OTP container', () => {
    document.body.innerHTML = `
      <div class="otp-container">
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
      </div>
    `;
    const inputs = detectSplitInputs(document);
    expect(inputs).not.toBeNull();
    expect(inputs?.length).toBe(6);
  });

  it('detects 6 inputs in verify-code container', () => {
    document.body.innerHTML = `
      <div class="verify-code">
        <input maxlength="1" type="tel" />
        <input maxlength="1" type="tel" />
        <input maxlength="1" type="tel" />
        <input maxlength="1" type="tel" />
        <input maxlength="1" type="tel" />
        <input maxlength="1" type="tel" />
      </div>
    `;
    const inputs = detectSplitInputs(document);
    expect(inputs).not.toBeNull();
    expect(inputs?.length).toBe(6);
  });

  it('returns null when only 4 single-char inputs exist', () => {
    document.body.innerHTML = `
      <div class="pin-code">
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
      </div>
    `;
    const inputs = detectSplitInputs(document);
    expect(inputs).toBeNull();
  });

  it('returns null when no maxlength=1 inputs exist', () => {
    document.body.innerHTML = '<input type="text" name="search" />';
    const inputs = detectSplitInputs(document);
    expect(inputs).toBeNull();
  });
});

describe('attemptFill', () => {
  let document: Document;

  beforeEach(() => {
    const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>');
    document = dom.window.document;
  });

  it('returns true and fills single TOTP field', () => {
    document.body.innerHTML = '<input type="text" autocomplete="one-time-code" />';
    const result = attemptFill(document, '123456');
    expect(result).toBe(true);
    const input = document.querySelector('input') as HTMLInputElement;
    expect(input.value).toBe('123456');
  });

  it('returns true and fills split inputs', () => {
    document.body.innerHTML = `
      <div class="otp-container">
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
        <input maxlength="1" type="text" />
      </div>
    `;
    const result = attemptFill(document, '789012');
    expect(result).toBe(true);
    const inputs = document.querySelectorAll('input');
    expect((inputs[0] as HTMLInputElement).value).toBe('7');
    expect((inputs[5] as HTMLInputElement).value).toBe('2');
  });

  it('returns false when no field detected', () => {
    document.body.innerHTML = '<input type="text" name="username" />';
    const result = attemptFill(document, '123456');
    expect(result).toBe(false);
  });
});
