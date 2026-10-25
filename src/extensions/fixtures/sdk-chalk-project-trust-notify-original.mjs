// Exact original createProjectTrustContext.notify arrow; options and chalk
// are its genuine lexical inputs. Startup UI methods are outside this fixture.
(function originalProjectTrustNotify(options, chalk) {
"use strict";
return (message, type = "info") => {
				if (options.mode !== "interactive") {
					const color = type === "error" ? chalk.red : type === "warning" ? chalk.yellow : chalk.cyan;
					console.error(color(message));
				}
			};
})
