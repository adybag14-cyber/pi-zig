(function(resolveModelScopeWithDiagnostics, chalk) {
"use strict";
async function resolveModelScope(patterns, modelRuntime, options) {
	const { scopedModels, diagnostics } = await resolveModelScopeWithDiagnostics(patterns, modelRuntime, options);
	for (const diagnostic of diagnostics) {
		console.warn(chalk.yellow(`Warning: ${diagnostic.message}`));
	}
	return scopedModels;
}
return resolveModelScope;
})
