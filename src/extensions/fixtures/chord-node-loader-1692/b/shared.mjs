// Guest module identities must agree across roots and change at each reload.
globalThis.loaderSequence = (globalThis.loaderSequence ?? 0) + 1;
export const marker = { generation: globalThis.loaderSequence };
export const url = import.meta.url;
