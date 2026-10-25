// Exact pinned Chalk 6.0.0 source bodies; only module syntax is adapted.
// supportsColor is the genuine installed native detector output, shared input
// for this style-only comparison. No detector or unconsumed style parity claim.
(function originalChalkSource(supportsColor) {
"use strict";
const ansiStyles = (() => {
const ANSI_BACKGROUND_OFFSET = 10;
const ANSI_UNDERLINE_OFFSET = 20;

const wrapAnsi16 = (offset = 0) => code => `\u{1B}[${code + offset}m`;

const wrapAnsi256 = (offset = 0) => code => `\u{1B}[${38 + offset};5;${code}m`;

const wrapAnsi16m = (offset = 0) => (red, green, blue) => `\u{1B}[${38 + offset};2;${red};${green};${blue}m`;

// `SGR 58` has no basic 16-color form, so the basic color code is mapped to its palette index instead.
const wrapUnderlineAnsi = code => `\u{1B}[58;5;${code < 90 ? code - 30 : code - 90 + 8}m`;

const styles = {
	modifier: {
		reset: [0, 0],
		// 21 isn't widely supported and 22 does the same thing
		bold: [1, 22],
		dim: [2, 22],
		italic: [3, 23],
		underline: [4, 24],
		// Extended underline styles (`SGR 4:x` sub-parameters). Not in upstream `ansi-styles`.
		underlineDouble: ['4:2', 24],
		underlineCurly: ['4:3', 24],
		underlineDotted: ['4:4', 24],
		underlineDashed: ['4:5', 24],
		overline: [53, 55],
		inverse: [7, 27],
		hidden: [8, 28],
		strikethrough: [9, 29],
	},
	color: {
		black: [30, 39],
		red: [31, 39],
		green: [32, 39],
		yellow: [33, 39],
		blue: [34, 39],
		magenta: [35, 39],
		cyan: [36, 39],
		white: [37, 39],

		// Bright color
		blackBright: [90, 39],
		gray: [90, 39], // Alias of `blackBright`
		grey: [90, 39], // Alias of `blackBright`
		redBright: [91, 39],
		greenBright: [92, 39],
		yellowBright: [93, 39],
		blueBright: [94, 39],
		magentaBright: [95, 39],
		cyanBright: [96, 39],
		whiteBright: [97, 39],
	},
	bgColor: {
		bgBlack: [40, 49],
		bgRed: [41, 49],
		bgGreen: [42, 49],
		bgYellow: [43, 49],
		bgBlue: [44, 49],
		bgMagenta: [45, 49],
		bgCyan: [46, 49],
		bgWhite: [47, 49],

		// Bright color
		bgBlackBright: [100, 49],
		bgGray: [100, 49], // Alias of `bgBlackBright`
		bgGrey: [100, 49], // Alias of `bgBlackBright`
		bgRedBright: [101, 49],
		bgGreenBright: [102, 49],
		bgYellowBright: [103, 49],
		bgBlueBright: [104, 49],
		bgMagentaBright: [105, 49],
		bgCyanBright: [106, 49],
		bgWhiteBright: [107, 49],
	},
	// Underline color (`SGR 58`/`59`). Not in upstream `ansi-styles`.
	underlineColor: {
		underlineBlack: ['58;5;0', 59],
		underlineRed: ['58;5;1', 59],
		underlineGreen: ['58;5;2', 59],
		underlineYellow: ['58;5;3', 59],
		underlineBlue: ['58;5;4', 59],
		underlineMagenta: ['58;5;5', 59],
		underlineCyan: ['58;5;6', 59],
		underlineWhite: ['58;5;7', 59],

		// Bright color
		underlineBlackBright: ['58;5;8', 59],
		underlineGray: ['58;5;8', 59], // Alias of `underlineBlackBright`
		underlineGrey: ['58;5;8', 59], // Alias of `underlineBlackBright`
		underlineRedBright: ['58;5;9', 59],
		underlineGreenBright: ['58;5;10', 59],
		underlineYellowBright: ['58;5;11', 59],
		underlineBlueBright: ['58;5;12', 59],
		underlineMagentaBright: ['58;5;13', 59],
		underlineCyanBright: ['58;5;14', 59],
		underlineWhiteBright: ['58;5;15', 59],
	},
};

const modifierNames = Object.keys(styles.modifier);
const foregroundColorNames = Object.keys(styles.color);
const backgroundColorNames = Object.keys(styles.bgColor);
const underlineColorNames = Object.keys(styles.underlineColor);
const colorNames = [...foregroundColorNames, ...backgroundColorNames];

function assembleStyles() {
	const codes = new Map();

	for (const [groupName, group] of Object.entries(styles)) {
		for (const [styleName, style] of Object.entries(group)) {
			styles[styleName] = {
				open: `\u{1B}[${style[0]}m`,
				close: `\u{1B}[${style[1]}m`,
			};

			group[styleName] = styles[styleName];

			// Only the leading SGR parameter identifies a style, so `4:3` and `58;5;1` are keyed as `4` and `58`.
			codes.set(Number.parseInt(style[0], 10), style[1]);
		}

		Object.defineProperty(styles, groupName, {
			value: group,
			enumerable: false,
		});
	}

	Object.defineProperty(styles, 'codes', {
		value: codes,
		enumerable: false,
	});

	styles.color.close = '\u{1B}[39m';
	styles.bgColor.close = '\u{1B}[49m';
	styles.underlineColor.close = '\u{1B}[59m';

	styles.color.ansi = wrapAnsi16();
	styles.color.ansi256 = wrapAnsi256();
	styles.color.ansi16m = wrapAnsi16m();
	styles.bgColor.ansi = wrapAnsi16(ANSI_BACKGROUND_OFFSET);
	styles.bgColor.ansi256 = wrapAnsi256(ANSI_BACKGROUND_OFFSET);
	styles.bgColor.ansi16m = wrapAnsi16m(ANSI_BACKGROUND_OFFSET);
	styles.underlineColor.ansi = wrapUnderlineAnsi;
	styles.underlineColor.ansi256 = wrapAnsi256(ANSI_UNDERLINE_OFFSET);
	styles.underlineColor.ansi16m = wrapAnsi16m(ANSI_UNDERLINE_OFFSET);

	// From https://github.com/Qix-/color-convert/blob/3f0e0d4e92e235796ccb17f6e85c72094a651f49/conversions.js
	Object.defineProperties(styles, {
		rgbToAnsi256: {
			value(red, green, blue) {
				// We use the extended greyscale palette here, with the exception of
				// black and white. normal palette only has 4 greyscale shades.
				if (red === green && green === blue) {
					if (red < 8) {
						return 16;
					}

					if (red > 248) {
						return 231;
					}

					return Math.round(((red - 8) / 247) * 24) + 232;
				}

				return 16
					+ (36 * Math.round(red / 255 * 5))
					+ (6 * Math.round(green / 255 * 5))
					+ Math.round(blue / 255 * 5);
			},
			enumerable: false,
		},
		hexToRgb: {
			value(hex) {
				const matches = /[\da-f]{6}|[\da-f]{3}/i.exec(hex.toString(16));
				if (!matches) {
					return [0, 0, 0];
				}

				let [colorString] = matches;

				if (colorString.length === 3) {
					colorString = [...colorString].map(character => character + character).join('');
				}

				const integer = Number.parseInt(colorString, 16);

				return [
					/* eslint-disable no-bitwise -- We need the speed */
					(integer >> 16) & 0xFF,
					(integer >> 8) & 0xFF,
					integer & 0xFF,
					/* eslint-enable no-bitwise */
				];
			},
			enumerable: false,
		},
		hexToAnsi256: {
			value: hex => styles.rgbToAnsi256(...styles.hexToRgb(hex)),
			enumerable: false,
		},
		ansi256ToAnsi: {
			value(code) {
				if (code < 8) {
					return 30 + code;
				}

				if (code < 16) {
					return 90 + (code - 8);
				}

				let red;
				let green;
				let blue;

				if (code >= 232) {
					red = (((code - 232) * 10) + 8) / 255;
					green = red;
					blue = red;
				} else {
					code -= 16;

					const remainder = code % 36;

					red = Math.floor(code / 36) / 5;
					green = Math.floor(remainder / 6) / 5;
					blue = (remainder % 6) / 5;
				}

				const value = Math.max(red, green, blue) * 2;

				if (value === 0) {
					return 30;
				}

				// eslint-disable-next-line no-bitwise
				let result = 30 + ((Math.round(blue) << 2) | (Math.round(green) << 1) | Math.round(red));

				if (value === 2) {
					result += 60;
				}

				return result;
			},
			enumerable: false,
		},
		rgbToAnsi: {
			value: (red, green, blue) => styles.ansi256ToAnsi(styles.rgbToAnsi256(red, green, blue)),
			enumerable: false,
		},
		hexToAnsi: {
			value: hex => styles.ansi256ToAnsi(styles.hexToAnsi256(hex)),
			enumerable: false,
		},
	});

	return styles;
}

const ansiStyles = assembleStyles();

return ansiStyles;

})();
// Note: Each match is kept and `postfix` is inserted after it. `String#replaceAll(substring, substring + postfix)` does the same, but it has to scan the replacement for `$` patterns and it is several times slower on the no-match path that most calls take.
function stringReplaceAll(string, substring, postfix) {
	let index = string.indexOf(substring);
	if (index === -1) {
		return string;
	}

	const substringLength = substring.length;
	let endIndex = 0;
	let returnValue = '';
	do {
		returnValue += string.slice(endIndex, index) + substring + postfix;
		endIndex = index + substringLength;
		index = string.indexOf(substring, endIndex);
	} while (index !== -1);

	returnValue += string.slice(endIndex);
	return returnValue;
}

function stringEncaseCRLFWithFirstIndex(string, prefix, postfix, index) {
	let endIndex = 0;
	let returnValue = '';
	do {
		const isGotCR = string[index - 1] === '\r';
		returnValue += string.slice(endIndex, (isGotCR ? index - 1 : index)) + prefix + (isGotCR ? '\r\n' : '\n') + postfix;
		endIndex = index + 1;
		index = string.indexOf('\n', endIndex);
	} while (index !== -1);

	returnValue += string.slice(endIndex);
	return returnValue;
}

const {stdout: stdoutColor, stderr: stderrColor} = supportsColor;

const GENERATOR = Symbol('GENERATOR');
const STYLER = Symbol('STYLER');
const IS_EMPTY = Symbol('IS_EMPTY');
const LEVEL = Symbol('LEVEL');

const styles = Object.create(null);

const assertValidLevel = level => {
	if (!Number.isSafeInteger(level) || level < 0 || level > 3) {
		throw new Error('The `level` should be an integer from 0 to 3');
	}
};

// The level is stored under a symbol so the hot path can read it as a plain property, while `level` itself is an accessor that rejects values the rest of the code could not handle.
const levelDescriptor = {
	enumerable: true,
	get() {
		return this[LEVEL];
	},
	set(level) {
		assertValidLevel(level);
		this[LEVEL] = level;
	},
};

const applyOptions = (object, options = {}) => {
	if (options.level !== undefined) {
		assertValidLevel(options.level);
	}

	// Detect level if not set manually. Written under the symbol rather than through `level`, as the prototype carrying that accessor is not installed until after this runs.
	const colorLevel = stdoutColor ? stdoutColor.level : 0;
	object[LEVEL] = options.level === undefined ? colorLevel : options.level;
};

class Chalk {
	constructor(options) {
		// eslint-disable-next-line no-constructor-return
		return chalkFactory(options);
	}
}

const chalkFactory = options => {
	const chalk = (...strings) => strings.join(' ');
	applyOptions(chalk, options);

	Object.setPrototypeOf(chalk, createChalk.prototype);

	return chalk;
};

function createChalk(options) {
	return chalkFactory(options);
}

// eslint-disable-next-line unicorn/no-top-level-side-effects -- The prototype chain must be set up at module load.
Object.setPrototypeOf(createChalk.prototype, Function.prototype);

for (const [styleName, style] of Object.entries(ansiStyles)) {
	styles[styleName] = {
		get() {
			const builder = createBuilder(this, createStyler(style.open, style.close, this[STYLER]), this[IS_EMPTY]);
			Object.defineProperty(this, styleName, {value: builder});
			return builder;
		},
	};
}

styles.visible = {
	get() {
		const builder = createBuilder(this, this[STYLER], true);
		Object.defineProperty(this, 'visible', {value: builder});
		return builder;
	},
};

// Resolve a color model to one converter per `level`, so that a call only has to look up the converter for the current level instead of re-deciding the model and level every time.
const createModelConverters = (model, type) => {
	const style = ansiStyles[type];

	if (model === 'rgb') {
		const ansi = (red, green, blue) => style.ansi(ansiStyles.rgbToAnsi(red, green, blue));
		const ansi256 = (red, green, blue) => style.ansi256(ansiStyles.rgbToAnsi256(red, green, blue));
		return [ansi, ansi, ansi256, style.ansi16m];
	}

	if (model === 'hex') {
		const ansi = hex => style.ansi(ansiStyles.hexToAnsi(hex));
		const ansi256 = hex => style.ansi256(ansiStyles.hexToAnsi256(hex));
		return [ansi, ansi, ansi256, hex => style.ansi16m(...ansiStyles.hexToRgb(hex))];
	}

	// `ansi256` is already the native form, so only the 16-color levels need converting.
	const ansi = code => style.ansi(ansiStyles.ansi256ToAnsi(code));
	return [ansi, ansi, style.ansi256, style.ansi256];
};

const usedModels = ['rgb', 'hex', 'ansi256'];

for (const model of usedModels) {
	const capitalizedModel = model[0].toUpperCase() + model.slice(1);

	for (const [styleName, type] of [
		[model, 'color'],
		['bg' + capitalizedModel, 'bgColor'],
		['underline' + capitalizedModel, 'underlineColor'],
	]) {
		const {close} = ansiStyles[type];
		const converters = createModelConverters(model, type);

		styles[styleName] = {
			get() {
				// The level is read on call rather than captured here so the function can be cached on the instance instead of being reallocated on every property access.
				// `rgb` is the widest model, so naming the three parameters avoids a rest array.
				const styleFunction = function (first, second, third) {
					const open = converters[this.level](first, second, third);
					return createBuilder(this, createStyler(open, close, this[STYLER]), this[IS_EMPTY]);
				};

				Object.defineProperty(this, styleName, {value: styleFunction});
				return styleFunction;
			},
		};
	}
}

const proto = Object.defineProperties(
	() => {},
	{
		...styles,
		level: {
			enumerable: true,
			get() {
				return this[GENERATOR].level;
			},
			set(level) {
				this[GENERATOR].level = level;
			},
		},
	},
);

const createStyler = (open, close, parent) => {
	let openAll;
	let closeAll;
	if (parent === undefined) {
		openAll = open;
		closeAll = close;
	} else {
		openAll = parent.openAll + open;
		closeAll = close + parent.closeAll;
	}

	return {
		open,
		close,
		openAll,
		closeAll,
		parent,
	};
};

const createBuilder = (self, _styler, _isEmpty) => {
	// Single argument is hot path, implicit coercion is faster than anything
	const builder = (...arguments_) => {
		if (arguments_.length === 1) {
			// eslint-disable-next-line no-implicit-coercion
			return applyStyle(builder, '' + arguments_[0]);
		}

		if (arguments_.length === 2) {
			return applyStyle(builder, arguments_[0] + ' ' + arguments_[1]);
		}

		return applyStyle(builder, arguments_.join(' '));
	};

	// We alter the prototype because we must return a function, but there is
	// no way to create a function with a different prototype
	Object.setPrototypeOf(builder, proto);

	// Point every builder at the root generator instead of its immediate parent, so reading the level costs one property load rather than walking a `level` getter per link of the chain.
	builder[GENERATOR] = self[GENERATOR] ?? self;
	builder[STYLER] = _styler;
	builder[IS_EMPTY] = _isEmpty;

	return builder;
};

const applyStyle = (self, string) => {
	// Read the level directly off the generator to skip the `level` getter dispatch on this hot path
	if (self[GENERATOR][LEVEL] <= 0 || !string) {
		// eslint-disable-next-line unicorn/no-computed-property-existence-check -- Reads the boolean value, not a property existence check.
		return self[IS_EMPTY] ? '' : string;
	}

	let styler = self[STYLER];

	if (styler === undefined) {
		return string;
	}

	const {openAll, closeAll} = styler;
	if (string.includes('\u{1B}')) {
		while (styler !== undefined) {
			// Replace any instances already present with a re-opening code
			// otherwise only the part of the string until said closing code
			// will be colored, and the rest will simply be 'plain'.
			string = stringReplaceAll(string, styler.close, styler.open);

			styler = styler.parent;
		}
	}

	// We can move both next actions out of loop, because remaining actions in loop won't have
	// any/visible effect on parts we add here. Close the styling before a linebreak and reopen
	// after next line to fix a bleed issue on macOS: https://github.com/chalk/chalk/pull/92
	const lfIndex = string.indexOf('\n');
	if (lfIndex !== -1) {
		string = stringEncaseCRLFWithFirstIndex(string, closeAll, openAll, lfIndex);
	}

	return openAll + string + closeAll;
};

// `level` lives on the prototype rather than on each instance, so it costs nothing to construct an instance and matches how builders already expose it. It is inherited rather than own, so it does not show up in `Object.keys()`, same as for a builder.
// eslint-disable-next-line unicorn/no-top-level-side-effects -- The style getters must be installed at module load.
Object.defineProperties(createChalk.prototype, {...styles, level: levelDescriptor});

const chalk = createChalk();
const chalkStderr = createChalk({level: stderrColor ? stderrColor.level : 0});


return chalk;
})
