(function originalFallbackFactory(defaultModelPerProvider) {
function buildFallbackModel(providerModels, modelId) {
	const defaultId = defaultModelPerProvider[providerModels[0].provider];
	const baseModel = defaultId
		? (providerModels.find((m) => m.id === defaultId) ?? providerModels[0])
		: providerModels[0];

	return {
		...baseModel,
		id: modelId,
		name: modelId,
	};
}
return buildFallbackModel;
})
