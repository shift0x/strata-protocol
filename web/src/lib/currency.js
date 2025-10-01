/**
 * Format a raw string input as currency display
 * @param {string} value - Raw input value
 * @returns {string} Formatted currency string with $ prefix
 */
export function formatCurrency(value) {
  // Remove all non-numeric except dot
  let cleaned = value.replace(/[^\d.]/g, '');
  // Only allow one dot
  const parts = cleaned.split('.');
  if (parts.length > 2) cleaned = parts[0] + '.' + parts[1];
  // Format as currency
  let [intPart, decPart] = cleaned.split('.');
  intPart = intPart ? String(Number(intPart)) : '';
  // Add commas to integer part
  if (intPart) intPart = Number(intPart).toLocaleString();
  if (decPart !== undefined) decPart = decPart.slice(0, 2);
  let formatted = intPart;
  if (decPart !== undefined) formatted += '.' + decPart;
  if (formatted) formatted = '$' + formatted;
  return formatted;
}

/**
 * Parse a formatted currency string to get numeric value
 * @param {string} formatted - Formatted currency string
 * @returns {string} Numeric string without formatting
 */
export function parseCurrency(formatted) {
  return formatted.replace(/[^\d.]/g, '');
}

/**
 * Validate if a currency string represents a valid positive number
 * @param {string} value - Currency value to validate
 * @returns {boolean} True if valid positive number
 */
export function isValidCurrencyAmount(value) {
  const numeric = parseCurrency(value);
  const num = parseFloat(numeric);
  return !isNaN(num) && num > 0;
}