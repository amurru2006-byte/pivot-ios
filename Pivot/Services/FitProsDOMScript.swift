// Original visible-DOM observer; generated from the private laboratory source.
// No vendor source, real identifiers or real records are embedded here.
// Observer SHA-256: 74dd1bb08c01631fb7b44619db20f5966b28c20e47bb6e00266ee81572ec22c9
import Foundation

enum FitProsDOMScript {
    static let observer = #"""
// Original read-only observer of the visible FitPros logger, observed build 6021.
// No storage, cookies, network, framework objects, credentials or DOM mutations.
function readFitProsEditor(doc, href) {
  const fail = reason => { throw new Error(reason); };
  const one = (root, selector) => {
    const found = Array.from(root.querySelectorAll(selector));
    if (found.length !== 1) fail('ambiguous_' + selector);
    return found[0];
  };
  const text = (node, max = 256) => {
    const value = (node.textContent || '').trim();
    if (!value || value.length > max) fail('invalid_visible_label');
    return value;
  };
  const url = new URL(href);
  if (url.origin !== 'https://app.fitpros.io' || url.pathname !== '/workout-log') fail('wrong_logger_origin');
  const identity = {};
  for (const name of ['programId', 'workoutId', 'weekId']) {
    const values = url.searchParams.getAll(name);
    if (values.length !== 1 || !/^[A-Za-z0-9_-]{1,256}$/.test(values[0])) fail('ambiguous_route_identity');
    identity[name] = values[0];
  }
  const title = text(one(doc, '[data-testid="logger-header-title"]'), 512);
  const cards = Array.from(doc.querySelectorAll('[data-testid="exercise-card-completion"]'));
  if (cards.length < 1 || cards.length > 40) fail('exercise_count');
  let totalSets = 0;
  const exercises = cards.map(card => {
    const metricIDs = new Set();
    const title = text(one(card, '[data-exercise-card-header] h3'));
    const rows = Array.from(card.querySelectorAll('[data-testid="metric-row-scroller"]'));
    if (!rows.length || rows.length > 6) fail('metric_count');
    const metrics = rows.map(row => {
      const cells = Array.from(row.querySelectorAll('[data-exercise-metric-id]'));
      if (!cells.length || cells.length > 60) fail('set_count');
      let metricID;
      let unit;
      const values = cells.map((cell, index) => {
        const currentID = cell.getAttribute('data-exercise-metric-id');
        if (!/^[A-Za-z0-9_-]{1,256}$/.test(currentID || '')) fail('invalid_metric_identity');
        if (metricID && metricID !== currentID) fail('mixed_metric_row');
        metricID = currentID;
        const input = one(cell, '[data-testid="metric-value-caption"] input');
        if (input.disabled || input.readOnly || !['text', 'number'].includes(input.type)) fail('unavailable_field');
        const currentUnit = text(one(cell, '[data-testid="metric-value-caption"] .sr-only'));
        if (unit && unit !== currentUnit) fail('mixed_metric_units');
        unit = currentUnit;
        const ordinal = Number(text(one(cell, 'span.pointer-events-none')));
        if (!Number.isInteger(ordinal) || ordinal !== index + 1) fail('changed_set_order');
        const raw = input.value.trim();
        const placeholder = input.getAttribute('placeholder') || '';
        if (raw.length > 64 || placeholder.length > 128) fail('field_too_large');
        let current = null;
        if (raw !== '') {
          if (!/^\d+(?:[.,]\d+)?$/.test(raw)) fail('invalid_actual_number');
          current = Number(raw.replace(',', '.'));
          if (!Number.isFinite(current)) fail('invalid_actual_number');
        }
        return {ordinal, current, placeholder};
      });
      if (metricIDs.has(metricID)) fail('duplicate_metric_identity');
      metricIDs.add(metricID);
      const kind = {kg: 'kg', reps: 'reps', sec: 'seconds'}[unit];
      if (!kind) fail('unsupported_visible_metric');
      if (values.some(v => v.current !== null && (v.current < 0 ||
          v.current > ({kg:2000,reps:1000,seconds:86400}[kind]) ||
          (kind !== 'kg' && !Number.isInteger(v.current))))) fail('invalid_actual_number');
      return {id:metricID, kind, unit, cells:values};
    });
    if (new Set(metrics.map(m => m.kind)).size !== metrics.length) fail('duplicate_metric_kind');
    if (new Set(metrics.map(m => m.cells.length)).size !== 1) fail('inconsistent_set_columns');
    const notesField = one(card, 'textarea');
    if (notesField.disabled || notesField.readOnly || notesField.value.length > 10000) fail('unavailable_notes');
    totalSets += metrics[0].cells.length;
    const mediaPaths = Array.from(card.querySelectorAll('img')).map(image => {
      const source = image.getAttribute('src');
      if (!source) return '';
      const media = new URL(source, url);
      // Keep only visible media identity, never query strings or credentials.
      return media.protocol === 'https:' ? media.hostname + media.pathname : '';
    }).filter(Boolean).sort();
    return {
      // Composite visible anchor, NOT an official remote exercise identifier.
      anchor: JSON.stringify([title,mediaPaths,metrics.map(m=>[m.id,m.kind,m.unit])]), title, metrics,
      notes: notesField.value,
      // The DOM has no distinct performed/skipped/failure controls.
      statusControl: false, failureControl: false
    };
  });
  if (new Set(exercises.map(e=>e.anchor)).size !== exercises.length) fail('ambiguous_exercise_anchors');
  if (totalSets > 400) fail('total_set_limit');
  const dock = one(doc, '[data-testid="workout-dock"]');
  const counter = one(dock, '[aria-label$="sets logged"]').getAttribute('aria-label').match(/^(\d+) of (\d+) sets logged$/);
  if (!counter || Number(counter[2]) !== totalSets || Number(counter[1]) > totalSets) fail('set_counter_mismatch');
  const finish = one(dock, '[data-testid="workout-finish"]');
  if (finish.disabled || text(finish) !== 'Finish') fail('finish_control_changed');
  const prescribed = exercises.map(e => ({
    anchor:e.anchor, title:e.title,
    metrics:e.metrics.map(m => ({id:m.id,kind:m.kind,unit:m.unit,cells:m.cells.map(c=>({ordinal:c.ordinal,placeholder:c.placeholder}))}))
  }));
  return {
    schema:1, adapter:'fitpros-visible-logger-v1', ...identity, title, exercises,
    loggedSets:Number(counter[1]), totalSets,
    emptyDraft:Number(counter[1])===0 && exercises.every(e=>e.notes==='' && e.metrics.every(m=>m.cells.every(c=>c.current===null))),
    // Host hashes these canonical strings; a DOM fingerprint is not a server revision.
    prescriptionCanonical:JSON.stringify({identity,prescribed}),
    stateCanonical:JSON.stringify({identity,title,exercises,loggedSets:Number(counter[1]),totalSets}),
    canWrite:false, serverPersistenceVerified:false, accountIdentityVerified:false
  };
}

"""#
}
