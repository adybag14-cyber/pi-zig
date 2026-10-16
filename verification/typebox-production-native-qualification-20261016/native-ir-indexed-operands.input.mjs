// Prepared genuine-source input. Capture only after an explicit Source grant.
// Reuse unchanged against the actual native shared graph after source authority exists.
const { Compile } = globalThis.actualSchemaCompiler;
const rows = [];
function result(operation) {
  try { return { value: operation() }; }
  catch (error) { return { error: { name: error.name, message: error.message } }; }
}
function observe(name, schema, make) {
  const validator = Compile(schema);
  const { value, reads } = make();
  const check = result(() => validator.Check(value));
  const checkReads = reads.splice(0);
  const errors = result(() => validator.Errors(value).length);
  const errorReads = reads.splice(0);
  rows.push({ name, check, checkReads, errors, errorReads, code: validator.Code() });
}
const prefix = { type: 'array', prefixItems: [{ type: 'string' }, { type: 'number' }], items: { type: 'boolean' } };
observe('original-prefix-valid', prefix, () => ({ value: ['x', 1, true], reads: [] }));
observe('original-prefix-invalid', prefix, () => ({ value: ['x', 'wrong', true], reads: [] }));
observe('prefix-short-array', prefix, () => ({ value: ['x'], reads: [] }));
observe('prefix-hole', prefix, () => ({ value: new Array(1), reads: [] }));
observe('tuple-items-valid', { type: 'array', items: [{ type: 'string' }, { type: 'number' }], additionalItems: false }, () => ({ value: ['x', 1], reads: [] }));
observe('own-prefix-getter', { type: 'array', prefixItems: [{ type: 'string' }] }, () => {
  const value = new Array(1), reads = [];
  Object.defineProperty(value, '0', { configurable: true, get() { reads.push(['own-zero', this === value]); return 'x'; } });
  return { value, reads };
});
observe('inherited-prefix-getter', { type: 'array', prefixItems: [{ type: 'string' }] }, () => {
  const value = new Array(1), reads = [], prototype = Object.create(Array.prototype);
  Object.defineProperty(prototype, '0', { configurable: true, get() { reads.push(['prototype-zero', this === value]); return 'x'; } });
  Object.setPrototypeOf(value, prototype);
  return { value, reads };
});
observe('throwing-prefix-getter', { type: 'array', prefixItems: [{ type: 'string' }] }, () => {
  const value = new Array(1), reads = [];
  Object.defineProperty(value, '0', { configurable: true, get() { reads.push(['throwing-zero', this === value]); throw Error('indexed-source-getter'); } });
  return { value, reads };
});
const nestedPrefix = { type: 'array', prefixItems: [{ type: 'array', prefixItems: [{ type: 'string' }, { type: 'number' }] }] };
observe('nested-prefix-array', nestedPrefix, () => ({ value: [['x', 1]], reads: [] }));
observe('nested-prefix-getters', nestedPrefix, () => {
  const value = new Array(1), inner = new Array(2), reads = [];
  Object.defineProperty(value, '0', { configurable: true, get() { reads.push(['outer-zero', this === value]); return inner; } });
  Object.defineProperty(inner, '0', { configurable: true, get() { reads.push(['inner-zero', this === inner]); return 'x'; } });
  Object.defineProperty(inner, '1', { configurable: true, get() { reads.push(['inner-one', this === inner]); return 1; } });
  return { value, reads };
});
globalThis.TypeBoxIndexedOperandObservation = { rows };
