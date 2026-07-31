from pathlib import Path

old = r'''      !f2e_buffer_append(script, "_consumes_value() {\n"
                                 "  local opt value_opts bool_value_opts\n"
                                 "  value_opts=\"$(") ||
      !f2e_buffer_append(script, function_name) ||
      !f2e_buffer_append(script, "_value_opts \"$1\")\"\n"
                                 "  for opt in $value_opts; do\n"
                                 "    if [ \"$2\" = \"$opt\" ]; then\n"
                                 "      return 0\n"
                                 "    fi\n"
                                 "  done\n"
                                 "  bool_value_opts=\"$(") ||
      !f2e_buffer_append(script, function_name) ||
      !f2e_buffer_append(script, "_bool_value_opts \"$1\")\"\n"
                                 "  for opt in $bool_value_opts; do\n"
                                 "    if [ \"$2\" = \"$opt\" ]; then\n"
                                 "      case \" ") ||
      !f2e_buffer_append(script, bool_values ? bool_values : "") ||
      !f2e_buffer_append(script, " \" in\n"
                                 "        *\" $3 \"*) return 0 ;;\n"
                                 "      esac\n"
                                 "    fi\n"
                                 "  done\n"
                                 "  return 1\n"
                                 "}\n")) {'''

new = r'''      !f2e_buffer_append(script, "_consumes_value() {\n"
                                 "  local value_opts bool_value_opts\n"
                                 "  value_opts=\"$(") ||
      !f2e_buffer_append(script, function_name) ||
      !f2e_buffer_append(script, "_value_opts \"$1\")\"\n"
                                 "  case \" $value_opts \" in\n"
                                 "    *\" $2 \"*) return 0 ;;\n"
                                 "  esac\n"
                                 "  bool_value_opts=\"$(") ||
      !f2e_buffer_append(script, function_name) ||
      !f2e_buffer_append(script, "_bool_value_opts \"$1\")\"\n"
                                 "  case \" $bool_value_opts \" in\n"
                                 "    *\" $2 \"*)\n"
                                 "      case \" ") ||
      !f2e_buffer_append(script, bool_values ? bool_values : "") ||
      !f2e_buffer_append(script, " \" in\n"
                                 "        *\" $3 \"*) return 0 ;;\n"
                                 "      esac\n"
                                 "      ;;\n"
                                 "  esac\n"
                                 "  return 1\n"
                                 "}\n")) {'''

comment_old = " *   <fn>_child <scope> <word>    resolved child scope key, or empty\n */"
comment_new = " *   <fn>_child <scope> <word>    resolved child scope key, or empty\n *   <fn>_consumes_value <scope> <previous> <word>\n *                                whether word is an option value, not a command\n */"

paths = [Path("src/parser.c"), *sorted(Path("clients").rglob("parser.c"))]
patched = 0
for path in paths:
    if not path.is_file():
        continue
    text = path.read_text(encoding="utf-8")
    if old not in text:
        continue
    if text.count(old) != 1:
        raise RuntimeError(f"{path}: unexpected completion helper count")
    if text.count(comment_old) != 1:
        raise RuntimeError(f"{path}: completion helper comment changed")
    path.write_text(text.replace(old, new).replace(comment_old, comment_new), encoding="utf-8")
    patched += 1

if patched != 13:
    raise RuntimeError(f"expected 13 parser copies, patched {patched}")
