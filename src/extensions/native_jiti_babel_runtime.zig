//! Compiler-emitted runtime helper templates, derived from actual Babel helpers
//! in the pinned licensed default backend. These run only as generated user
//! module syntax, never as a host compiler or substitute native dependency.
pub const default_interop = "function __pi_cjs_default(e){return e&&e.__esModule?e:{default:e};}";
pub const wildcard_interop =
    "function __pi_cjs_wildcard(e,t){if(\"function\"==typeof WeakMap)var r=new WeakMap(),n=new WeakMap();" ++
    "return(__pi_cjs_wildcard=function(e,t){if(!t&&e&&e.__esModule)return e;var o,i,f={__proto__:null,default:e};" ++
    "if(null===e||\"object\"!=typeof e&&\"function\"!=typeof e)return f;if(o=t?n:r){if(o.has(e))return o.get(e);o.set(e,f);}" ++
    "for(const t in e)\"default\"!==t&&{}.hasOwnProperty.call(e,t)&&((i=(o=Object.defineProperty)&&Object.getOwnPropertyDescriptor(e,t))&&(i.get||i.set)?o(f,t,i):f[t]=e[t]);return f;})(e,t);}";
// Actual Babel usingCtx helper body. Native syntax planning chooses hygienic
// context/helper names and emits calls for every actual using initializer.
pub const using_context_body =
    "var r=\"function\"==typeof SuppressedError?SuppressedError:function(r,e){var n=Error();return n.name=\"SuppressedError\",n.error=r,n.suppressed=e,n;},e={},n=[];" ++
    "function using(r,e){if(null!=e){if(Object(e)!==e)throw new TypeError(\"using declarations can only be used with objects, functions, null, or undefined.\");" ++
    "if(r)var o=e[Symbol.asyncDispose||Symbol.for(\"Symbol.asyncDispose\")];if(void 0===o&&(o=e[Symbol.dispose||Symbol.for(\"Symbol.dispose\")],r))var t=o;" ++
    "if(\"function\"!=typeof o)throw new TypeError(\"Object is not disposable.\");t&&(o=function(){try{t.call(e);}catch(r){return Promise.reject(r);}}),n.push({v:e,d:o,a:r});}else r&&n.push({d:e,a:r});return e;}" ++
    "return{e:e,u:using.bind(null,!1),a:using.bind(null,!0),d:function(){var o,t=this.e,s=0;function next(){for(;o=n.pop();)try{" ++
    "if(!o.a&&1===s)return s=0,n.push(o),Promise.resolve().then(next);if(o.d){var r=o.d.call(o.v);if(o.a)return s|=2,Promise.resolve(r).then(next,err);}else s|=1;}catch(r){return err(r);}" ++
    "if(1===s)return t!==e?Promise.reject(t):Promise.resolve();if(t!==e)throw t;}function err(n){return t=t!==e?new r(n,t):n,next();}return next();}};}";
