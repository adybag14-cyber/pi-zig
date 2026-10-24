(function settingsAccessorsOriginal(SETTINGS_DEFAULTS) {
"use strict";
const CACHE_WARMING_MODES = ["off", "streaming", "idle"];

const DEFAULT_COMPACTION_TOKEN_SETTINGS = {
	reserveTokens: SETTINGS_DEFAULTS.compaction.reserveTokens,
	keepRecentTokens: SETTINGS_DEFAULTS.compaction.keepRecentTokens,
};

function isMergeableObject(value) {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

class SourceAccessors {
	getSteeringMode() {
		return this.settings.steeringMode || SETTINGS_DEFAULTS.steeringMode;
	}

	getFollowUpMode() {
		return this.settings.followUpMode || SETTINGS_DEFAULTS.followUpMode;
	}

	getTransport() {
		return this.settings.transport ?? SETTINGS_DEFAULTS.transport;
	}

	getSessionShareDestination() {
		const destination = this.settings.sessionShareDestination;
		return destination === "gist" || destination === "radius"
			? destination
			: SETTINGS_DEFAULTS.sessionShareDestination;
	}

	getCompactionEnabled() {
		return this.settings.compaction?.enabled ?? SETTINGS_DEFAULTS.compaction.enabled;
	}

	getCompactionTokenSetting(field, model) {
		const compaction = this.settings.compaction;
		const ordinary = compaction?.[field];
		if (ordinary !== undefined && (typeof ordinary !== "number" || !Number.isSafeInteger(ordinary) || ordinary < 0)) {
			throw new Error(
				`Invalid compaction.${field} setting: ${String(ordinary)}. Expected a non-negative safe integer.`,
			);
		}

		const modelKey = model ? `${model.provider}/${model.id}` : undefined;
		const entry = modelKey !== undefined ? compaction?.modelOverrides?.[modelKey] : undefined;
		if (entry !== undefined && !isMergeableObject(entry)) {
			throw new Error(
				`Invalid compaction.modelOverrides["${modelKey}"] setting: ${String(entry)}. Expected an object.`,
			);
		}
		const override = entry?.[field];
		if (override !== undefined && (typeof override !== "number" || !Number.isSafeInteger(override) || override < 0)) {
			throw new Error(
				`Invalid compaction.modelOverrides["${modelKey}"].${field} setting: ${String(override)}. Expected a non-negative safe integer.`,
			);
		}
		return override ?? ordinary ?? DEFAULT_COMPACTION_TOKEN_SETTINGS[field];
	}

	getCompactionReserveTokens(model) {
		return this.getCompactionTokenSetting("reserveTokens", model);
	}

	getCompactionKeepRecentTokens(model) {
		return this.getCompactionTokenSetting("keepRecentTokens", model);
	}

	getCompactionSettings(model) {
		return {
			enabled: this.getCompactionEnabled(),
			reserveTokens: this.getCompactionReserveTokens(model),
			keepRecentTokens: this.getCompactionKeepRecentTokens(model),
		};
	}

	getBranchSummarySettings() {
		return {
			reserveTokens: this.settings.branchSummary?.reserveTokens ?? SETTINGS_DEFAULTS.branchSummary.reserveTokens,
			skipPrompt: this.settings.branchSummary?.skipPrompt ?? SETTINGS_DEFAULTS.branchSummary.skipPrompt,
		};
	}

	getBranchSummarySkipPrompt() {
		return this.settings.branchSummary?.skipPrompt ?? SETTINGS_DEFAULTS.branchSummary.skipPrompt;
	}

	getRetryEnabled() {
		return this.settings.retry?.enabled ?? SETTINGS_DEFAULTS.retry.enabled;
	}

	getRetrySettings() {
		return {
			enabled: this.getRetryEnabled(),
			maxRetries: this.settings.retry?.maxRetries ?? SETTINGS_DEFAULTS.retry.maxRetries,
			baseDelayMs: this.settings.retry?.baseDelayMs ?? SETTINGS_DEFAULTS.retry.baseDelayMs,
			maxAgentDelayMs: this.settings.retry?.maxAgentDelayMs ?? SETTINGS_DEFAULTS.retry.maxAgentDelayMs,
		};
	}

	getCacheWarmingMode() {
		const mode = this.globalSettings.cacheWarming;
		return mode !== undefined && CACHE_WARMING_MODES.includes(mode) ? mode : SETTINGS_DEFAULTS.cacheWarming;
	}

	getProviderRetrySettings() {
		return {
			timeoutMs: this.settings.retry?.provider?.timeoutMs,
			maxRetries: this.settings.retry?.provider?.maxRetries,
			maxRetryDelayMs:
				this.settings.retry?.provider?.maxRetryDelayMs ?? SETTINGS_DEFAULTS.retry.provider.maxRetryDelayMs,
		};
	}

	getHideThinkingBlock() {
		return this.settings.hideThinkingBlock ?? SETTINGS_DEFAULTS.hideThinkingBlock;
	}

	getShowCacheMissNotices() {
		return this.settings.showCacheMissNotices ?? SETTINGS_DEFAULTS.showCacheMissNotices;
	}

	getQuietStartup() {
		const value = this.settings.quietStartup;
		return value === true || value === "header" ? value : SETTINGS_DEFAULTS.quietStartup;
	}

	getDefaultProjectTrust() {
		const value = this.globalSettings.defaultProjectTrust;
		return value === "always" || value === "never" ? value : SETTINGS_DEFAULTS.defaultProjectTrust;
	}

	getCollapseChangelog() {
		return this.settings.collapseChangelog ?? SETTINGS_DEFAULTS.collapseChangelog;
	}

	getEnableInstallTelemetry() {
		return this.settings.enableInstallTelemetry ?? SETTINGS_DEFAULTS.enableInstallTelemetry;
	}

	getEnableAnalytics() {
		return this.settings.enableAnalytics ?? SETTINGS_DEFAULTS.enableAnalytics;
	}

	getEnableSkillCommands() {
		return this.settings.enableSkillCommands ?? SETTINGS_DEFAULTS.enableSkillCommands;
	}

	getShowImages() {
		return this.settings.terminal?.showImages ?? SETTINGS_DEFAULTS.terminal.showImages;
	}

	getImageWidthCells() {
		const width = this.settings.terminal?.imageWidthCells;
		if (typeof width !== "number" || !Number.isFinite(width)) {
			return SETTINGS_DEFAULTS.terminal.imageWidthCells;
		}
		return Math.max(1, Math.floor(width));
	}

	getClearOnShrink() {
		// Settings takes precedence, then env var, then default false
		if (this.settings.terminal?.clearOnShrink !== undefined) {
			return this.settings.terminal.clearOnShrink;
		}
		if (process.env.PI_CLEAR_ON_SHRINK === "1") return true;
		return SETTINGS_DEFAULTS.terminal.clearOnShrink;
	}

	getShowTerminalProgress() {
		return this.settings.terminal?.showTerminalProgress ?? SETTINGS_DEFAULTS.terminal.showTerminalProgress;
	}

	getTuiMode() {
		return this.settings.tuiMode === "regular" ? "regular" : SETTINGS_DEFAULTS.tuiMode;
	}

	getFullscreenExitOutput() {
		return this.settings.fullscreenExitOutput === "resume-hint"
			? "resume-hint"
			: SETTINGS_DEFAULTS.fullscreenExitOutput;
	}

	getFullscreenScrollbar() {
		const mode = this.settings.fullscreenScrollbar;
		return mode === "always" || mode === "hidden" ? mode : SETTINGS_DEFAULTS.fullscreenScrollbar;
	}

	getFullscreenCopyOnSelect() {
		return this.settings.fullscreenCopyOnSelect ?? SETTINGS_DEFAULTS.fullscreenCopyOnSelect;
	}

	getFullscreenWheelScrollLines() {
		const lines = this.settings.fullscreenWheelScrollLines;
		return typeof lines === "number" && Number.isFinite(lines)
			? Math.max(1, Math.min(100, Math.floor(lines)))
			: SETTINGS_DEFAULTS.fullscreenWheelScrollLines;
	}

	getImageAutoResize() {
		return this.settings.images?.autoResize ?? SETTINGS_DEFAULTS.images.autoResize;
	}

	getBlockImages() {
		return this.settings.images?.blockImages ?? SETTINGS_DEFAULTS.images.blockImages;
	}

	getDoubleEscapeAction() {
		return this.settings.doubleEscapeAction ?? SETTINGS_DEFAULTS.doubleEscapeAction;
	}

	getTreeFilterMode() {
		const mode = this.settings.treeFilterMode;
		const valid = ["default", "no-tools", "user-only", "labeled-only", "all"];
		return mode && valid.includes(mode) ? mode : SETTINGS_DEFAULTS.treeFilterMode;
	}

	getEditorPaddingX() {
		return this.settings.editorPaddingX ?? SETTINGS_DEFAULTS.editorPaddingX;
	}

	getOutputPad() {
		return this.settings.outputPad === 0 ? 0 : SETTINGS_DEFAULTS.outputPad;
	}

	getAutocompleteMaxVisible() {
		return this.settings.autocompleteMaxVisible ?? SETTINGS_DEFAULTS.autocompleteMaxVisible;
	}

	getCodeBlockIndent() {
		return this.settings.markdown?.codeBlockIndent ?? SETTINGS_DEFAULTS.markdown.codeBlockIndent;
	}

	getMermaidRenderingMode() {
		const mode = this.settings.markdown?.mermaid;
		return mode === "off" || mode === "final" ? mode : SETTINGS_DEFAULTS.markdown.mermaid;
	}
}

return { methods: SourceAccessors.prototype, CACHE_WARMING_MODES };
})
