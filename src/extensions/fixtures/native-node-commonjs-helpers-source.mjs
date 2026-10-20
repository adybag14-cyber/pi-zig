// Selected verbatim Node v24.14 helpers.js declarations; real imports supplied by the fixture.
export function createCommonJSHelpersSource({fs, internalFS, SafeMap, SafeSet, ObjectFreeze, getOptionValue}) {
const realpathCache = new SafeMap();
/**
 * Resolves the path of a given `require` specifier, following symlinks.
 * @param {string} requestPath The `require` specifier
 * @returns {string}
 */
function toRealPath(requestPath) {
  return fs.realpathSync(requestPath, {
    [internalFS.realpathCacheKey]: realpathCache,
  });
}

/** @type {Set<string>} */
let cjsConditions;
/** @type {string[]} */
let cjsConditionsArray;

/**
 * Define the conditions that apply to the CommonJS loader.
 * @returns {void}
 */
function initializeCjsConditions() {
  const userConditions = getOptionValue('--conditions');
  const noAddons = getOptionValue('--no-addons');
  const addonConditions = noAddons ? [] : ['node-addons'];
  // TODO: Use this set when resolving pkg#exports conditions in loader.js.
  cjsConditionsArray = [
    'require',
    'node',
    ...addonConditions,
    ...userConditions,
  ];
  if (getOptionValue('--experimental-require-module')) {
    cjsConditionsArray.push('module-sync');
  }
  ObjectFreeze(cjsConditionsArray);
  cjsConditions = new SafeSet(cjsConditionsArray);
}

/**
 * Get the conditions that apply to the CommonJS loader.
 * @returns {Set<string>}
 */
function getCjsConditions() {
  if (cjsConditions === undefined) {
    initializeCjsConditions();
  }
  return cjsConditions;
}

function getCjsConditionsArray() {
  if (cjsConditionsArray === undefined) {
    initializeCjsConditions();
  }
  return cjsConditionsArray;
}

return { toRealPath, initializeCjsConditions, getCjsConditions, getCjsConditionsArray };
}
