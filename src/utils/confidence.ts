/**
 * Compute a confidence score (0–1) based on how many top-level fields in the
 * parsed JSON are non-empty.
 */
export function computeConfidence(jsonString: string): number {
  try {
    const parsed = JSON.parse(jsonString);
    if (!parsed || typeof parsed !== 'object') return 0.5;

    // Count non-empty fields
    const fields = Object.keys(parsed);
    let filledCount = 0;
    for (const key of fields) {
      const val = parsed[key];
      if (val === '' || val === 0 || val === null || val === undefined) continue;
      if (Array.isArray(val) && val.length === 0) continue;
      filledCount++;
    }

    if (fields.length === 0) return 0.5;

    const fillRatio = filledCount / fields.length;
    // Base confidence 0.7, scaled up by fill ratio to max 0.95
    return Math.min(0.95, 0.7 + fillRatio * 0.25);
  } catch {
    // JSON parse failed — low confidence
    return 0.4;
  }
}
