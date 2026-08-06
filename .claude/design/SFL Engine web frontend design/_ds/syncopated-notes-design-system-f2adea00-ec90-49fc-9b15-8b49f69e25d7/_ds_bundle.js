/* @ds-bundle: {"format":3,"namespace":"SyncopatedNotesDesignSystem_f2adea","components":[{"name":"Badge","sourcePath":"components/core/Badge.jsx"},{"name":"Button","sourcePath":"components/core/Button.jsx"},{"name":"Card","sourcePath":"components/core/Card.jsx"},{"name":"IconButton","sourcePath":"components/core/IconButton.jsx"},{"name":"Tag","sourcePath":"components/core/Tag.jsx"},{"name":"Callout","sourcePath":"components/feedback/Callout.jsx"},{"name":"CodePanel","sourcePath":"components/feedback/CodePanel.jsx"},{"name":"Checkbox","sourcePath":"components/forms/Checkbox.jsx"},{"name":"Input","sourcePath":"components/forms/Input.jsx"},{"name":"Select","sourcePath":"components/forms/Select.jsx"},{"name":"Switch","sourcePath":"components/forms/Switch.jsx"},{"name":"NavItem","sourcePath":"components/navigation/NavItem.jsx"},{"name":"Tabs","sourcePath":"components/navigation/Tabs.jsx"}],"sourceHashes":{"components/core/Badge.jsx":"b26c621b87c2","components/core/Button.jsx":"0b602b7d762a","components/core/Card.jsx":"58235bd26e2b","components/core/IconButton.jsx":"9297f44302b6","components/core/Tag.jsx":"388453055c81","components/feedback/Callout.jsx":"5dac6dfc6b86","components/feedback/CodePanel.jsx":"d2452675548f","components/forms/Checkbox.jsx":"652b63909baf","components/forms/Input.jsx":"c2e983a18e0f","components/forms/Select.jsx":"d7271ef82cae","components/forms/Switch.jsx":"a1e5854dec5d","components/navigation/NavItem.jsx":"c942ac0571e7","components/navigation/Tabs.jsx":"4c4a5e0b7667","ui_kits/knowledgebase/app.jsx":"71a8a98d10ef"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.SyncopatedNotesDesignSystem_f2adea = window.SyncopatedNotesDesignSystem_f2adea || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/core/Badge.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Badge — small status pill. Uses the editor status palette with a
 * tinted surface for legibility in both themes.
 */
function Badge({
  children,
  tone = "neutral",
  solid = false,
  style = {},
  ...rest
}) {
  const hue = {
    neutral: "var(--muted)",
    info: "var(--status-info)",
    accent: "var(--status-accent)",
    success: "var(--status-success)",
    question: "var(--status-question)",
    warning: "var(--status-warning)",
    danger: "var(--status-danger)",
    special: "var(--status-special)",
    coral: "var(--accent)"
  }[tone];
  const solidStyle = {
    background: hue,
    color: "#fff",
    border: "1px solid transparent"
  };
  const softStyle = {
    background: `color-mix(in oklab, ${hue} 14%, var(--background))`,
    color: hue,
    border: `1px solid color-mix(in oklab, ${hue} 34%, transparent)`
  };
  return /*#__PURE__*/React.createElement("span", _extends({
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: "5px",
      fontFamily: "var(--font-ui)",
      fontSize: "10.5px",
      fontWeight: 700,
      letterSpacing: "0.06em",
      textTransform: "uppercase",
      lineHeight: 1.4,
      padding: "3px 8px",
      borderRadius: "var(--radius-xs)",
      whiteSpace: "nowrap",
      ...(solid ? solidStyle : softStyle),
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Badge.jsx", error: String((e && e.message) || e) }); }

// components/core/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Button — Syncopated Notes primary action control.
 * Monospace label, hairline border, minimal radius, coral primary.
 */
function Button({
  children,
  variant = "primary",
  size = "md",
  icon = null,
  iconRight = null,
  fullWidth = false,
  disabled = false,
  type = "button",
  onClick,
  style = {},
  ...rest
}) {
  const sizes = {
    sm: {
      padding: "5px 10px",
      fontSize: "12px",
      gap: "6px",
      height: "28px"
    },
    md: {
      padding: "7px 14px",
      fontSize: "13px",
      gap: "7px",
      height: "34px"
    },
    lg: {
      padding: "10px 18px",
      fontSize: "15px",
      gap: "8px",
      height: "42px"
    }
  };
  const variants = {
    primary: {
      background: "var(--accent)",
      color: "#fff",
      border: "1px solid var(--accent)"
    },
    secondary: {
      background: "var(--surface)",
      color: "var(--foreground)",
      border: "1px solid var(--border-2)"
    },
    ghost: {
      background: "transparent",
      color: "var(--foreground)",
      border: "1px solid transparent"
    },
    outline: {
      background: "transparent",
      color: "var(--accent)",
      border: "1px solid var(--accent)"
    },
    danger: {
      background: "var(--status-danger)",
      color: "#fff",
      border: "1px solid var(--status-danger)"
    }
  };
  const [hover, setHover] = React.useState(false);
  const [active, setActive] = React.useState(false);
  const hoverBg = {
    primary: "var(--accent-hi)",
    secondary: "var(--surface-2)",
    ghost: "var(--surface)",
    outline: "var(--accent-soft)",
    danger: "color-mix(in oklab, var(--status-danger) 85%, #000)"
  };
  const base = {
    display: fullWidth ? "flex" : "inline-flex",
    width: fullWidth ? "100%" : "auto",
    alignItems: "center",
    justifyContent: "center",
    fontFamily: "var(--font-ui)",
    fontWeight: 600,
    letterSpacing: "0.01em",
    lineHeight: 1,
    borderRadius: "var(--radius-sm)",
    cursor: disabled ? "not-allowed" : "pointer",
    opacity: disabled ? 0.45 : 1,
    transition: "background var(--transition-fast) var(--ease-out), transform var(--transition-fast) var(--ease-out)",
    transform: active && !disabled ? "scale(0.97)" : "scale(1)",
    whiteSpace: "nowrap",
    userSelect: "none",
    ...sizes[size],
    ...variants[variant],
    ...(hover && !disabled ? {
      background: hoverBg[variant]
    } : {}),
    ...style
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    type: type,
    disabled: disabled,
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => {
      setHover(false);
      setActive(false);
    },
    onMouseDown: () => setActive(true),
    onMouseUp: () => setActive(false),
    style: base
  }, rest), icon ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      flexShrink: 0
    }
  }, icon) : null, children ? /*#__PURE__*/React.createElement("span", null, children) : null, iconRight ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      flexShrink: 0
    }
  }, iconRight) : null);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Button.jsx", error: String((e && e.message) || e) }); }

// components/core/Card.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Card — bordered surface container. Border-first, minimal shadow.
 * Optional header (eyebrow + title) and footer regions.
 */
function Card({
  children,
  title,
  eyebrow,
  actions,
  footer,
  accent = false,
  padding = "md",
  style = {},
  ...rest
}) {
  const pad = {
    none: "0",
    sm: "12px 14px",
    md: "18px 20px",
    lg: "24px 28px"
  }[padding];
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      background: "var(--surface)",
      border: "1px solid var(--border)",
      borderLeft: accent ? "3px solid var(--accent)" : "1px solid var(--border)",
      borderRadius: "var(--radius-md)",
      boxShadow: "var(--shadow-sm)",
      overflow: "hidden",
      ...style
    }
  }, rest), (title || eyebrow || actions) && /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: "12px",
      padding: "12px 16px",
      borderBottom: "1px solid var(--border)",
      background: "var(--background)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      minWidth: 0
    }
  }, eyebrow && /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: "var(--font-ui)",
      fontSize: "10.5px",
      fontWeight: 700,
      letterSpacing: "0.1em",
      textTransform: "uppercase",
      color: "var(--muted)",
      marginBottom: title ? "3px" : 0
    }
  }, eyebrow), title && /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: "var(--font-display)",
      fontSize: "15px",
      fontWeight: 700,
      color: "var(--foreground)",
      lineHeight: 1.3
    }
  }, title)), actions && /*#__PURE__*/React.createElement("div", {
    style: {
      marginLeft: "auto",
      display: "flex",
      gap: "8px"
    }
  }, actions)), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: pad,
      fontFamily: "var(--font-body)",
      color: "var(--foreground)",
      fontSize: "14px",
      lineHeight: 1.6
    }
  }, children), footer && /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "10px 16px",
      borderTop: "1px solid var(--border)",
      background: "var(--background)",
      fontFamily: "var(--font-ui)",
      fontSize: "12px",
      color: "var(--muted)"
    }
  }, footer));
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Card.jsx", error: String((e && e.message) || e) }); }

// components/core/IconButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * IconButton — square, icon-only control. Matches the theme-toggle
 * affordance: surface fill, hairline border, subtle scale on press.
 */
function IconButton({
  children,
  size = "md",
  variant = "secondary",
  disabled = false,
  active = false,
  title,
  onClick,
  style = {},
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const [press, setPress] = React.useState(false);
  const dim = {
    sm: 28,
    md: 34,
    lg: 42
  }[size];
  const variants = {
    secondary: {
      background: "var(--surface)",
      border: "1px solid var(--border)"
    },
    ghost: {
      background: "transparent",
      border: "1px solid transparent"
    },
    solid: {
      background: "var(--accent)",
      border: "1px solid var(--accent)",
      color: "#fff"
    }
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    title: title,
    "aria-label": title,
    disabled: disabled,
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => {
      setHover(false);
      setPress(false);
    },
    onMouseDown: () => setPress(true),
    onMouseUp: () => setPress(false),
    style: {
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      width: dim + "px",
      height: dim + "px",
      borderRadius: "var(--radius-md)",
      color: variant === "solid" ? "#fff" : active ? "var(--accent)" : "var(--text-2)",
      cursor: disabled ? "not-allowed" : "pointer",
      opacity: disabled ? 0.45 : 1,
      transition: "background var(--transition-fast), transform var(--transition-fast), color var(--transition-fast)",
      transform: press && !disabled ? "scale(0.92)" : hover && !disabled ? "scale(1.05)" : "scale(1)",
      ...variants[variant],
      ...(hover && !disabled && variant !== "solid" ? {
        background: "var(--popover)"
      } : {}),
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/core/Tag.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Tag — monospace topic tag, as used on notes (e.g. `prompt-engineering`).
 * Optional leading "#" and click affordance.
 */
function Tag({
  children,
  hash = true,
  active = false,
  onClick,
  style = {},
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const interactive = !!onClick;
  return /*#__PURE__*/React.createElement("span", _extends({
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: "1px",
      fontFamily: "var(--font-code)",
      fontSize: "12px",
      fontWeight: 500,
      lineHeight: 1.4,
      padding: "2px 8px",
      borderRadius: "var(--radius-xs)",
      cursor: interactive ? "pointer" : "default",
      color: active ? "var(--cyan)" : "var(--text-2)",
      background: active ? "color-mix(in oklab, var(--cyan) 12%, var(--background))" : hover && interactive ? "var(--surface)" : "var(--surface)",
      border: `1px solid ${active ? "color-mix(in oklab, var(--cyan) 36%, transparent)" : "var(--border)"}`,
      transition: "color var(--transition-fast), border-color var(--transition-fast)",
      ...style
    }
  }, rest), hash ? /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--muted)"
    }
  }, "#") : null, children);
}
Object.assign(__ds_scope, { Tag });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Tag.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Callout.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Callout — Obsidian-style admonition block, the signature
 * Syncopated Notes content component. Mono title bar + glyph,
 * italic prose body. 12 semantic types map to the status palette.
 */
const TYPES = {
  note: {
    hue: "var(--status-info)",
    glyph: "✎",
    label: "Note"
  },
  info: {
    hue: "var(--status-info)",
    glyph: "ℹ",
    label: "Info"
  },
  todo: {
    hue: "var(--status-info)",
    glyph: "☐",
    label: "Todo"
  },
  abstract: {
    hue: "var(--status-accent)",
    glyph: "⚡",
    label: "Abstract"
  },
  tldr: {
    hue: "var(--status-accent)",
    glyph: "⚡",
    label: "TL;DR"
  },
  tip: {
    hue: "var(--status-success)",
    glyph: "🔥",
    label: "Tip"
  },
  important: {
    hue: "var(--status-success)",
    glyph: "🔥",
    label: "Important"
  },
  success: {
    hue: "var(--status-success)",
    glyph: "✓",
    label: "Success"
  },
  done: {
    hue: "var(--status-success)",
    glyph: "✓",
    label: "Done"
  },
  question: {
    hue: "var(--status-question)",
    glyph: "?",
    label: "Question"
  },
  faq: {
    hue: "var(--status-question)",
    glyph: "?",
    label: "FAQ"
  },
  warning: {
    hue: "var(--status-warning)",
    glyph: "⚠",
    label: "Warning"
  },
  caution: {
    hue: "var(--status-warning)",
    glyph: "⚠",
    label: "Caution"
  },
  failure: {
    hue: "var(--status-danger)",
    glyph: "✗",
    label: "Failure"
  },
  error: {
    hue: "var(--status-danger)",
    glyph: "✗",
    label: "Error"
  },
  bug: {
    hue: "var(--status-danger)",
    glyph: "✗",
    label: "Bug"
  },
  example: {
    hue: "var(--status-special)",
    glyph: "◈",
    label: "Example"
  },
  quote: {
    hue: "var(--muted)",
    glyph: "“",
    label: "Quote"
  }
};
function Callout({
  type = "note",
  title,
  children,
  style = {},
  ...rest
}) {
  const t = TYPES[type] || TYPES.note;
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      margin: "1.25rem 0",
      background: "var(--surface)",
      border: "1px solid var(--border)",
      borderRadius: "var(--radius-md)",
      overflow: "hidden",
      boxShadow: "var(--shadow-sm)",
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: "9px",
      padding: "9px 14px",
      background: "var(--background)",
      borderBottom: "1px solid var(--border)",
      fontFamily: "var(--font-ui)",
      fontWeight: 600,
      fontSize: "13px",
      letterSpacing: "0.02em",
      color: t.hue
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "16px",
      lineHeight: 1,
      fontStyle: "normal"
    },
    "aria-hidden": true
  }, t.glyph), /*#__PURE__*/React.createElement("span", null, title || t.label)), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "12px 16px",
      fontFamily: "var(--font-body)",
      fontStyle: "italic",
      color: "var(--foreground)",
      fontSize: "14px",
      lineHeight: 1.6
    }
  }, children));
}
Object.assign(__ds_scope, { Callout });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Callout.jsx", error: String((e && e.message) || e) }); }

// components/feedback/CodePanel.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * CodePanel — inset command/output panel, the "code-panel" pattern from
 * the notes theme. Renders a terminal-flavored block with optional
 * filename/lang chip and a copy affordance.
 */
function CodePanel({
  children,
  lang,
  filename,
  copy = true,
  style = {},
  ...rest
}) {
  const [copied, setCopied] = React.useState(false);
  const ref = React.useRef(null);
  const doCopy = () => {
    const text = ref.current ? ref.current.innerText : "";
    if (navigator.clipboard) navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 1400);
  };
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      background: "var(--bg-code)",
      border: "1px solid var(--border)",
      borderRadius: "var(--radius-md)",
      overflow: "hidden",
      fontFamily: "var(--font-code)",
      ...style
    }
  }, rest), (lang || filename || copy) && /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: "8px",
      padding: "6px 10px 6px 12px",
      borderBottom: "1px solid var(--border)",
      background: "var(--background)"
    }
  }, filename && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "11.5px",
      color: "var(--text-2)"
    }
  }, filename), lang && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "10px",
      fontWeight: 700,
      letterSpacing: "0.08em",
      textTransform: "uppercase",
      color: "var(--cyan)",
      padding: "2px 6px",
      border: "1px solid var(--border)",
      borderRadius: "var(--radius-xs)",
      background: "var(--surface)"
    }
  }, lang), copy && /*#__PURE__*/React.createElement("button", {
    onClick: doCopy,
    style: {
      marginLeft: "auto",
      cursor: "pointer",
      background: "transparent",
      border: "1px solid var(--border)",
      borderRadius: "var(--radius-xs)",
      color: copied ? "var(--status-success)" : "var(--muted)",
      fontFamily: "var(--font-ui)",
      fontSize: "11px",
      padding: "3px 8px"
    }
  }, copied ? "copied ✓" : "copy")), /*#__PURE__*/React.createElement("pre", {
    ref: ref,
    style: {
      margin: 0,
      padding: "12px 14px",
      fontSize: "12.5px",
      lineHeight: 1.7,
      color: "var(--foreground)",
      overflowX: "auto",
      whiteSpace: "pre"
    }
  }, children));
}
Object.assign(__ds_scope, { CodePanel });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/CodePanel.jsx", error: String((e && e.message) || e) }); }

// components/forms/Checkbox.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Checkbox — square check with coral fill when set. */
function Checkbox({
  checked = false,
  disabled = false,
  indeterminate = false,
  onChange,
  label,
  style = {},
  ...rest
}) {
  const toggle = () => {
    if (!disabled && onChange) onChange(!checked);
  };
  const box = /*#__PURE__*/React.createElement("span", {
    role: "checkbox",
    "aria-checked": indeterminate ? "mixed" : checked,
    onClick: toggle,
    style: {
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      flexShrink: 0,
      width: "18px",
      height: "18px",
      borderRadius: "var(--radius-xs)",
      background: checked || indeterminate ? "var(--accent)" : "var(--popover)",
      border: "1px solid",
      borderColor: checked || indeterminate ? "var(--accent)" : "var(--border-2)",
      cursor: disabled ? "not-allowed" : "pointer",
      opacity: disabled ? 0.5 : 1,
      transition: "background var(--transition-fast), border-color var(--transition-fast)"
    }
  }, indeterminate ? /*#__PURE__*/React.createElement("span", {
    style: {
      width: "9px",
      height: "2px",
      background: "#fff",
      borderRadius: "1px"
    }
  }) : checked ? /*#__PURE__*/React.createElement("svg", {
    width: "12",
    height: "12",
    viewBox: "0 0 12 12",
    fill: "none"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M2.5 6.2L5 8.6L9.6 3.6",
    stroke: "#fff",
    strokeWidth: "1.8",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  })) : null);
  if (!label) return React.cloneElement(box, {
    style: {
      ...box.props.style,
      ...style
    },
    ...rest
  });
  return /*#__PURE__*/React.createElement("label", _extends({
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: "9px",
      cursor: disabled ? "not-allowed" : "pointer",
      ...style
    }
  }, rest), box, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-ui)",
      fontSize: "13px",
      color: "var(--foreground)"
    }
  }, label));
}
Object.assign(__ds_scope, { Checkbox });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Checkbox.jsx", error: String((e && e.message) || e) }); }

// components/forms/Input.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Input — text field with hairline border and coral focus ring.
 */
function Input({
  value,
  defaultValue,
  placeholder,
  type = "text",
  size = "md",
  disabled = false,
  invalid = false,
  prefix = null,
  onChange,
  style = {},
  ...rest
}) {
  const [focus, setFocus] = React.useState(false);
  const dims = {
    sm: {
      height: "30px",
      fontSize: "13px",
      padding: "0 9px"
    },
    md: {
      height: "36px",
      fontSize: "14px",
      padding: "0 11px"
    },
    lg: {
      height: "44px",
      fontSize: "15px",
      padding: "0 13px"
    }
  }[size];
  const borderColor = invalid ? "var(--status-danger)" : focus ? "var(--accent)" : "var(--border-2)";
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: "8px",
      background: "var(--popover)",
      border: `1px solid ${borderColor}`,
      borderRadius: "var(--radius-sm)",
      boxShadow: focus ? "0 0 0 3px var(--ring)" : "none",
      transition: "border-color var(--transition-fast), box-shadow var(--transition-fast)",
      opacity: disabled ? 0.5 : 1,
      ...dims,
      padding: undefined,
      paddingInline: dims.padding.split(" ")[1],
      ...style
    }
  }, prefix && /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      color: "var(--muted)",
      flexShrink: 0
    }
  }, prefix), /*#__PURE__*/React.createElement("input", _extends({
    type: type,
    value: value,
    defaultValue: defaultValue,
    placeholder: placeholder,
    disabled: disabled,
    onChange: onChange,
    onFocus: () => setFocus(true),
    onBlur: () => setFocus(false),
    style: {
      flex: 1,
      minWidth: 0,
      height: "100%",
      border: "none",
      outline: "none",
      background: "transparent",
      color: "var(--foreground)",
      fontFamily: "var(--font-code)",
      fontSize: dims.fontSize,
      letterSpacing: "0.01em"
    }
  }, rest)));
}
Object.assign(__ds_scope, { Input });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Input.jsx", error: String((e && e.message) || e) }); }

// components/forms/Select.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Select — native dropdown styled to match Input. */
function Select({
  value,
  defaultValue,
  options = [],
  size = "md",
  disabled = false,
  onChange,
  style = {},
  ...rest
}) {
  const [focus, setFocus] = React.useState(false);
  const dims = {
    sm: {
      height: "30px",
      fontSize: "13px"
    },
    md: {
      height: "36px",
      fontSize: "14px"
    },
    lg: {
      height: "44px",
      fontSize: "15px"
    }
  }[size];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative",
      display: "inline-flex",
      alignItems: "center",
      background: "var(--popover)",
      border: `1px solid ${focus ? "var(--accent)" : "var(--border-2)"}`,
      borderRadius: "var(--radius-sm)",
      boxShadow: focus ? "0 0 0 3px var(--ring)" : "none",
      opacity: disabled ? 0.5 : 1,
      transition: "border-color var(--transition-fast), box-shadow var(--transition-fast)",
      ...dims,
      ...style
    }
  }, /*#__PURE__*/React.createElement("select", _extends({
    value: value,
    defaultValue: defaultValue,
    disabled: disabled,
    onChange: onChange,
    onFocus: () => setFocus(true),
    onBlur: () => setFocus(false),
    style: {
      appearance: "none",
      WebkitAppearance: "none",
      border: "none",
      outline: "none",
      background: "transparent",
      color: "var(--foreground)",
      cursor: disabled ? "not-allowed" : "pointer",
      fontFamily: "var(--font-ui)",
      fontSize: dims.fontSize,
      height: "100%",
      padding: "0 30px 0 11px",
      width: "100%"
    }
  }, rest), options.map(o => {
    const opt = typeof o === "string" ? {
      value: o,
      label: o
    } : o;
    return /*#__PURE__*/React.createElement("option", {
      key: opt.value,
      value: opt.value
    }, opt.label);
  })), /*#__PURE__*/React.createElement("svg", {
    width: "11",
    height: "11",
    viewBox: "0 0 12 12",
    fill: "none",
    style: {
      position: "absolute",
      right: "10px",
      pointerEvents: "none"
    }
  }, /*#__PURE__*/React.createElement("path", {
    d: "M3 4.5L6 7.5L9 4.5",
    stroke: "var(--muted)",
    strokeWidth: "1.4",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  })));
}
Object.assign(__ds_scope, { Select });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Select.jsx", error: String((e && e.message) || e) }); }

// components/forms/Switch.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Switch — toggle control with coral "on" track. */
function Switch({
  checked = false,
  disabled = false,
  onChange,
  label,
  style = {},
  ...rest
}) {
  const toggle = () => {
    if (!disabled && onChange) onChange(!checked);
  };
  const sw = /*#__PURE__*/React.createElement("span", {
    role: "switch",
    "aria-checked": checked,
    onClick: toggle,
    style: {
      position: "relative",
      display: "inline-flex",
      flexShrink: 0,
      width: "38px",
      height: "22px",
      borderRadius: "var(--radius-pill)",
      background: checked ? "var(--accent)" : "var(--border-2)",
      border: "1px solid",
      borderColor: checked ? "var(--accent)" : "var(--border-2)",
      cursor: disabled ? "not-allowed" : "pointer",
      opacity: disabled ? 0.5 : 1,
      transition: "background var(--transition-base) var(--ease-out)"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      top: "2px",
      left: checked ? "18px" : "2px",
      width: "16px",
      height: "16px",
      borderRadius: "50%",
      background: "#fff",
      boxShadow: "var(--shadow-sm)",
      transition: "left var(--transition-base) var(--ease-out)"
    }
  }));
  if (!label) return React.cloneElement(sw, {
    style: {
      ...sw.props.style,
      ...style
    },
    ...rest
  });
  return /*#__PURE__*/React.createElement("label", _extends({
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: "9px",
      cursor: disabled ? "not-allowed" : "pointer",
      ...style
    }
  }, rest), sw, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-ui)",
      fontSize: "13px",
      color: "var(--foreground)"
    }
  }, label));
}
Object.assign(__ds_scope, { Switch });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Switch.jsx", error: String((e && e.message) || e) }); }

// components/navigation/NavItem.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * NavItem — sidebar / TOC link. Active state uses a coral left-rule
 * and tinted surface, matching the knowledgebase navigation.
 */
function NavItem({
  children,
  active = false,
  depth = 0,
  icon = null,
  href,
  onClick,
  style = {},
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("a", _extends({
    href: href || undefined,
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      display: "flex",
      alignItems: "center",
      gap: "8px",
      padding: "6px 12px",
      paddingLeft: `${12 + depth * 14}px`,
      fontFamily: "var(--font-ui)",
      fontSize: "13px",
      fontWeight: active ? 600 : 400,
      color: active ? "var(--accent)" : hover ? "var(--foreground)" : "var(--text-2)",
      background: active ? "var(--surface)" : hover ? "var(--surface)" : "transparent",
      borderLeft: `2px solid ${active ? "var(--accent)" : "transparent"}`,
      textDecoration: "none",
      cursor: "pointer",
      lineHeight: 1.4,
      transition: "color var(--transition-fast), background var(--transition-fast)",
      ...style
    }
  }, rest), icon ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      flexShrink: 0,
      color: active ? "var(--accent)" : "var(--muted)"
    }
  }, icon) : null, /*#__PURE__*/React.createElement("span", {
    style: {
      overflow: "hidden",
      textOverflow: "ellipsis",
      whiteSpace: "nowrap"
    }
  }, children));
}
Object.assign(__ds_scope, { NavItem });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/NavItem.jsx", error: String((e && e.message) || e) }); }

// components/navigation/Tabs.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Tabs — underline tab bar with a coral active indicator. Controlled
 * (pass value + onChange) or uncontrolled (defaultValue).
 */
function Tabs({
  tabs = [],
  value,
  defaultValue,
  onChange,
  style = {},
  ...rest
}) {
  const [internal, setInternal] = React.useState(defaultValue ?? (tabs[0] && (tabs[0].value ?? tabs[0])));
  const active = value !== undefined ? value : internal;
  const pick = v => {
    if (value === undefined) setInternal(v);
    if (onChange) onChange(v);
  };
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      display: "flex",
      gap: "2px",
      borderBottom: "1px solid var(--border)",
      ...style
    }
  }, rest), tabs.map(t => {
    const tab = typeof t === "string" ? {
      value: t,
      label: t
    } : t;
    const on = tab.value === active;
    return /*#__PURE__*/React.createElement("button", {
      key: tab.value,
      onClick: () => pick(tab.value),
      style: {
        position: "relative",
        cursor: "pointer",
        background: "transparent",
        border: "none",
        padding: "9px 14px",
        marginBottom: "-1px",
        fontFamily: "var(--font-ui)",
        fontSize: "13px",
        fontWeight: on ? 700 : 500,
        color: on ? "var(--accent)" : "var(--text-2)",
        borderBottom: `2px solid ${on ? "var(--accent)" : "transparent"}`,
        transition: "color var(--transition-fast)",
        display: "inline-flex",
        alignItems: "center",
        gap: "7px"
      }
    }, tab.icon ? /*#__PURE__*/React.createElement("span", {
      style: {
        display: "inline-flex"
      }
    }, tab.icon) : null, tab.label, tab.count != null && /*#__PURE__*/React.createElement("span", {
      style: {
        fontSize: "10.5px",
        fontWeight: 700,
        color: "var(--muted)",
        background: "var(--surface)",
        border: "1px solid var(--border)",
        borderRadius: "var(--radius-pill)",
        padding: "0 6px",
        lineHeight: "16px"
      }
    }, tab.count));
  }));
}
Object.assign(__ds_scope, { Tabs });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/Tabs.jsx", error: String((e && e.message) || e) }); }

// ui_kits/knowledgebase/app.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Syncopated Notes — Knowledgebase UI kit
   Composes design-system primitives into the real note-reader product.
   Exports <KnowledgebaseApp/> to window. */

const DS = window.SyncopatedNotesDesignSystem_f2adea;
const {
  Button,
  Badge,
  Tag,
  IconButton,
  Callout,
  CodePanel,
  NavItem,
  Tabs
} = DS;

/* ---------- tiny inline icons (stroke, 1.5) ---------- */
const Ico = {
  sun: p => /*#__PURE__*/React.createElement("svg", _extends({
    width: "16",
    height: "16",
    viewBox: "0 0 20 20",
    fill: "none"
  }, p), /*#__PURE__*/React.createElement("circle", {
    cx: "10",
    cy: "10",
    r: "3.4",
    stroke: "currentColor",
    strokeWidth: "1.5"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M10 2.5v2M10 15.5v2M2.5 10h2M15.5 10h2M4.7 4.7l1.4 1.4M13.9 13.9l1.4 1.4M15.3 4.7l-1.4 1.4M6.1 13.9l-1.4 1.4",
    stroke: "currentColor",
    strokeWidth: "1.5",
    strokeLinecap: "round"
  })),
  moon: p => /*#__PURE__*/React.createElement("svg", _extends({
    width: "16",
    height: "16",
    viewBox: "0 0 20 20",
    fill: "none"
  }, p), /*#__PURE__*/React.createElement("path", {
    d: "M16 11.5A6.5 6.5 0 018.5 4a6.5 6.5 0 100 12 6.5 6.5 0 007.5-4.5z",
    stroke: "currentColor",
    strokeWidth: "1.5",
    strokeLinejoin: "round"
  })),
  copy: p => /*#__PURE__*/React.createElement("svg", _extends({
    width: "15",
    height: "15",
    viewBox: "0 0 18 18",
    fill: "none"
  }, p), /*#__PURE__*/React.createElement("rect", {
    x: "6",
    y: "6",
    width: "9",
    height: "9",
    rx: "1.5",
    stroke: "currentColor",
    strokeWidth: "1.4"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M12 6V4.5A1.5 1.5 0 0010.5 3h-6A1.5 1.5 0 003 4.5v6A1.5 1.5 0 004.5 12H6",
    stroke: "currentColor",
    strokeWidth: "1.4"
  })),
  hash: p => /*#__PURE__*/React.createElement("svg", _extends({
    width: "14",
    height: "14",
    viewBox: "0 0 16 16",
    fill: "none"
  }, p), /*#__PURE__*/React.createElement("path", {
    d: "M6 2L4 14M12 2l-2 12M3 6h11M2 10h11",
    stroke: "currentColor",
    strokeWidth: "1.4",
    strokeLinecap: "round"
  })),
  cal: p => /*#__PURE__*/React.createElement("svg", _extends({
    width: "14",
    height: "14",
    viewBox: "0 0 16 16",
    fill: "none"
  }, p), /*#__PURE__*/React.createElement("rect", {
    x: "2.5",
    y: "3.5",
    width: "11",
    height: "10",
    rx: "1.5",
    stroke: "currentColor",
    strokeWidth: "1.3"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M2.5 6.5h11M5.5 2v3M10.5 2v3",
    stroke: "currentColor",
    strokeWidth: "1.3",
    strokeLinecap: "round"
  }))
};

/* ---------- Header ---------- */
function Header({
  dark,
  onToggle
}) {
  const nav = ["Notes", "Projects", "Wikis", "About"];
  return /*#__PURE__*/React.createElement("header", {
    style: {
      position: "sticky",
      top: 0,
      zIndex: 30,
      height: "var(--header-h)",
      display: "flex",
      alignItems: "center",
      gap: "20px",
      padding: "0 26px",
      background: "color-mix(in oklab, var(--background) 86%, transparent)",
      backdropFilter: "blur(8px)",
      borderBottom: "1px solid var(--border)"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: "var(--font-display)",
      fontWeight: 700,
      fontSize: "15px",
      color: "var(--cyan)",
      letterSpacing: "-0.01em"
    }
  }, "syncopated notes"), /*#__PURE__*/React.createElement("nav", {
    style: {
      marginLeft: "auto",
      display: "flex",
      gap: "20px"
    }
  }, nav.map((n, i) => /*#__PURE__*/React.createElement("a", {
    key: n,
    href: "#",
    style: {
      fontFamily: "var(--font-ui)",
      fontSize: "13px",
      color: i === 0 ? "var(--cyan)" : "var(--text-2)",
      textDecoration: "none"
    }
  }, n))), /*#__PURE__*/React.createElement(IconButton, {
    size: "sm",
    title: "Toggle theme",
    onClick: onToggle
  }, dark ? /*#__PURE__*/React.createElement(Ico.sun, null) : /*#__PURE__*/React.createElement(Ico.moon, null)));
}

/* ---------- Left nav rail ---------- */
function NavRail({
  notes,
  current,
  onPick
}) {
  return /*#__PURE__*/React.createElement("aside", {
    style: {
      width: "var(--sidebar-w)",
      flexShrink: 0,
      paddingTop: "32px",
      paddingRight: "12px"
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "eyebrow",
    style: {
      padding: "0 12px",
      marginBottom: "10px"
    }
  }, "Navigation"), /*#__PURE__*/React.createElement("div", {
    className: "eyebrow",
    style: {
      padding: "0 12px",
      margin: "16px 0 6px",
      color: "var(--dim)"
    }
  }, "Recent notes"), notes.map(n => /*#__PURE__*/React.createElement(NavItem, {
    key: n.id,
    active: n.id === current,
    onClick: e => {
      e.preventDefault();
      onPick(n.id);
    }
  }, n.title)));
}

/* ---------- Right TOC rail ---------- */
function Toc({
  items,
  active
}) {
  return /*#__PURE__*/React.createElement("aside", {
    style: {
      width: "var(--toc-w)",
      flexShrink: 0,
      paddingTop: "32px"
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "eyebrow",
    style: {
      marginBottom: "12px"
    }
  }, "Table of contents"), /*#__PURE__*/React.createElement("div", {
    className: "eyebrow",
    style: {
      color: "var(--dim)",
      marginBottom: "8px",
      fontSize: "10px"
    }
  }, "On this page"), items.map(it => /*#__PURE__*/React.createElement(NavItem, {
    key: it.id,
    href: "#" + it.id,
    active: it.id === active,
    depth: it.depth
  }, it.label)));
}

/* ---------- The note article ---------- */
function Article({
  note
}) {
  return /*#__PURE__*/React.createElement("article", {
    style: {
      flex: 1,
      minWidth: 0,
      maxWidth: "var(--width-article)",
      padding: "30px 8px 80px"
    }
  }, /*#__PURE__*/React.createElement("h1", {
    style: {
      fontSize: "var(--text-3xl)",
      marginBottom: "14px"
    }
  }, note.title), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: "10px",
      flexWrap: "wrap",
      marginBottom: "10px"
    }
  }, note.tags.map(t => /*#__PURE__*/React.createElement(Tag, {
    key: t
  }, t))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: "7px",
      fontFamily: "var(--font-ui)",
      fontSize: "12px",
      color: "var(--muted)",
      marginBottom: "30px"
    }
  }, /*#__PURE__*/React.createElement(Ico.cal, null), " Last modified: ", note.modified), /*#__PURE__*/React.createElement("h2", {
    id: "prompt",
    style: {
      fontSize: "var(--text-2xl)",
      marginBottom: "10px"
    }
  }, "SFL-Structured Prompt"), /*#__PURE__*/React.createElement("p", {
    style: pStyle
  }, "Interpersonal scaffolding is essentially \"relational noise\" that obscures data. While derived from psychological theories meant to build trust, in technical contexts it becomes a hindrance."), /*#__PURE__*/React.createElement(CodePanel, {
    lang: "prompt",
    filename: "prompt.md",
    style: {
      margin: "20px 0"
    }
  }, `Design the AI's interaction to mirror human conversational rhythm,
emphasizing natural turn-taking and brevity. Avoid 'essay mode' and
operate under 'biological constraints' that limit response length.`), /*#__PURE__*/React.createElement("h2", {
    id: "metadata",
    style: {
      fontSize: "var(--text-2xl)",
      margin: "34px 0 10px"
    }
  }, "SFL Metadata"), /*#__PURE__*/React.createElement("h3", {
    id: "field",
    style: {
      fontSize: "var(--text-xl)",
      margin: "18px 0 8px"
    }
  }, "Field \u2014 what is happening?"), /*#__PURE__*/React.createElement("ul", {
    style: ulStyle
  }, /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("b", null, "Topic:"), " Simulating natural, human-like conversational dynamics and pacing."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("b", null, "Task type:"), " Generating concise, informal, interactive responses that mirror human turn-taking."), /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement("b", null, "Keywords:"), " ", /*#__PURE__*/React.createElement(Tag, {
    hash: false
  }, "conversational-rhythm"), " ", /*#__PURE__*/React.createElement(Tag, {
    hash: false
  }, "natural-pacing"), " ", /*#__PURE__*/React.createElement(Tag, {
    hash: false
  }, "turn-taking"))), /*#__PURE__*/React.createElement(Callout, {
    type: "abstract",
    title: "The Claim vs. The Leak"
  }, "\"The orchestrator just routes tasks.\" But agentic systems are already accumulating capability discovery, context propagation, memory, policy enforcement, approval gates, tracing, identity, retries, and governance."), /*#__PURE__*/React.createElement("h3", {
    id: "tenor",
    style: {
      fontSize: "var(--text-xl)",
      margin: "24px 0 8px"
    }
  }, "Tenor \u2014 who is taking part?"), /*#__PURE__*/React.createElement("p", {
    style: pStyle
  }, "AI persona: ", /*#__PURE__*/React.createElement("b", null, "Expert"), ". Audience: users expecting quick, direct, human-like interaction \u2014 including Radiology IT systems support engineers. Desired tone: empathetic but non-dominant."), /*#__PURE__*/React.createElement(Callout, {
    type: "warning",
    title: "Caution"
  }, "Strict prohibition against boilerplate phrases (\"I hope this helps\", \"Let me know\") and restating the user's question. Self-edit for brevity; offer a \"full list\" only when items exceed three."), /*#__PURE__*/React.createElement("h2", {
    id: "output",
    style: {
      fontSize: "var(--text-2xl)",
      margin: "34px 0 10px"
    }
  }, "Example Output"), /*#__PURE__*/React.createElement(CodePanel, {
    filename: "response.txt",
    style: {
      margin: "16px 0"
    }
  }, `It's basically OAuth2. You swap the API key for a bearer token in
the header. Need the docs?`), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: "10px",
      marginTop: "28px"
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    icon: /*#__PURE__*/React.createElement(Ico.copy, null)
  }, "Copy note"), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary"
  }, "Open in editor")));
}
const pStyle = {
  fontFamily: "var(--font-body)",
  fontSize: "15px",
  lineHeight: 1.7,
  color: "var(--foreground)",
  margin: "0 0 14px",
  maxWidth: "62ch"
};
const ulStyle = {
  fontFamily: "var(--font-body)",
  fontSize: "15px",
  lineHeight: 1.8,
  color: "var(--foreground)",
  paddingLeft: "20px",
  margin: "0 0 18px"
};

/* ---------- App shell ---------- */
function KnowledgebaseApp() {
  const [dark, setDark] = React.useState(false);
  const [current, setCurrent] = React.useState("pacing");
  React.useEffect(() => {
    document.documentElement.classList.toggle("dark", dark);
  }, [dark]);
  const notes = [{
    id: "pacing",
    title: "The Natural Pacing Protocol"
  }, {
    id: "leak",
    title: "The Claim and The Leak"
  }, {
    id: "ospf",
    title: "OSPF as a Planner"
  }, {
    id: "bus",
    title: "Shared Context Bus"
  }];
  const note = {
    title: "The Natural Pacing Protocol",
    modified: "2026-02-02 06:37:57 PM",
    tags: ["natural-language-processing", "prompt-engineering", "generative-ai"]
  };
  const toc = [{
    id: "prompt",
    label: "Prompt Text",
    depth: 0
  }, {
    id: "metadata",
    label: "SFL Metadata",
    depth: 0
  }, {
    id: "field",
    label: "Field",
    depth: 1
  }, {
    id: "tenor",
    label: "Tenor",
    depth: 1
  }, {
    id: "output",
    label: "Example Output",
    depth: 0
  }];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: "var(--background)",
      minHeight: "100vh",
      color: "var(--foreground)"
    }
  }, /*#__PURE__*/React.createElement(Header, {
    dark: dark,
    onToggle: () => setDark(d => !d)
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: "20px",
      maxWidth: "1340px",
      margin: "0 auto",
      padding: "0 26px",
      alignItems: "flex-start"
    }
  }, /*#__PURE__*/React.createElement(NavRail, {
    notes: notes,
    current: current,
    onPick: setCurrent
  }), /*#__PURE__*/React.createElement(Article, {
    note: note
  }), /*#__PURE__*/React.createElement(Toc, {
    items: toc,
    active: "prompt"
  })));
}
window.KnowledgebaseApp = KnowledgebaseApp;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/knowledgebase/app.jsx", error: String((e && e.message) || e) }); }

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.Tag = __ds_scope.Tag;

__ds_ns.Callout = __ds_scope.Callout;

__ds_ns.CodePanel = __ds_scope.CodePanel;

__ds_ns.Checkbox = __ds_scope.Checkbox;

__ds_ns.Input = __ds_scope.Input;

__ds_ns.Select = __ds_scope.Select;

__ds_ns.Switch = __ds_scope.Switch;

__ds_ns.NavItem = __ds_scope.NavItem;

__ds_ns.Tabs = __ds_scope.Tabs;

})();
