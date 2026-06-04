#pragma once

#include "parser.h"

#include <cstdlib>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace flags2env {

namespace detail {
struct owned_c_string {
  char *value;

  explicit owned_c_string(char *ptr) : value(ptr) {}
  owned_c_string(const owned_c_string &) = delete;
  owned_c_string &operator=(const owned_c_string &) = delete;

  ~owned_c_string() {
    if (value) {
      f2e_free(value);
    }
  }

  std::string str() const {
    return value ? std::string(value) : std::string("{}");
  }
};

inline std::string escape_json(const std::string &value) {
  std::ostringstream out;
  out << '"';
  for (char ch : value) {
    switch (ch) {
      case '"': out << "\\\""; break;
      case '\\': out << "\\\\"; break;
      case '\b': out << "\\b"; break;
      case '\f': out << "\\f"; break;
      case '\n': out << "\\n"; break;
      case '\r': out << "\\r"; break;
      case '\t': out << "\\t"; break;
      default: out << ch; break;
    }
  }
  out << '"';
  return out.str();
}

inline std::string argv_json(const std::vector<std::string> &argv) {
  std::ostringstream out;
  out << '[';
  for (std::size_t i = 0; i < argv.size(); ++i) {
    if (i != 0) {
      out << ',';
    }
    out << escape_json(argv[i]);
  }
  out << ']';
  return out.str();
}

class json_cursor {
 public:
  explicit json_cursor(std::string input) : input_(std::move(input)) {}

  std::map<std::string, std::string> object() {
    std::map<std::string, std::string> out;
    skip();
    if (!consume('{')) {
      return out;
    }
    while (!done()) {
      skip();
      if (consume('}')) {
        return out;
      }
      std::string key = string();
      skip();
      if (!consume(':')) {
        return out;
      }
      std::string value = string();
      out[key] = value;
      skip();
      if (consume(',')) {
        continue;
      }
      consume('}');
      return out;
    }
    return out;
  }

 private:
  bool done() const { return index_ >= input_.size(); }

  void skip() {
    while (!done() && (input_[index_] == ' ' || input_[index_] == '\n' || input_[index_] == '\r' || input_[index_] == '\t')) {
      ++index_;
    }
  }

  bool consume(char expected) {
    skip();
    if (!done() && input_[index_] == expected) {
      ++index_;
      return true;
    }
    return false;
  }

  std::string string() {
    skip();
    if (done() || input_[index_] != '"') {
      return "";
    }
    ++index_;
    std::string out;
    while (!done()) {
      char ch = input_[index_++];
      if (ch == '"') {
        return out;
      }
      if (ch == '\\' && !done()) {
        char escaped = input_[index_++];
        switch (escaped) {
          case 'b': out.push_back('\b'); break;
          case 'f': out.push_back('\f'); break;
          case 'n': out.push_back('\n'); break;
          case 'r': out.push_back('\r'); break;
          case 't': out.push_back('\t'); break;
          case 'u':
            if (index_ + 4 <= input_.size()) {
              out.push_back('?');
              index_ += 4;
            }
            break;
          default: out.push_back(escaped); break;
        }
      } else {
        out.push_back(ch);
      }
    }
    return out;
  }

  std::string input_;
  std::size_t index_ = 0;
};
}  // namespace detail

inline std::map<std::string, std::string> parse(const std::vector<std::string> &argv) {
  const std::string encoded = detail::argv_json(argv);
  detail::owned_c_string result(f2e_parse_json_argv(encoded.c_str()));
  return detail::json_cursor(result.str()).object();
}

inline std::map<std::string, std::string> parse_from_file(const std::string &config_path, const std::vector<std::string> &argv) {
  const std::string encoded = detail::argv_json(argv);
  detail::owned_c_string result(f2e_parse_json_argv_from_file(config_path.c_str(), encoded.c_str()));
  return detail::json_cursor(result.str()).object();
}

inline std::map<std::string, std::string> parse_process() {
  detail::owned_c_string result(f2e_parse_process());
  return detail::json_cursor(result.str()).object();
}

inline std::map<std::string, std::string> parse_process_from_file(const std::string &config_path) {
  detail::owned_c_string result(f2e_parse_process_from_file(config_path.c_str()));
  return detail::json_cursor(result.str()).object();
}

inline std::map<std::string, std::string> apply(std::map<std::string, std::string> env, const std::vector<std::string> &argv) {
  for (const auto &pair : parse(argv)) {
    env[pair.first] = pair.second;
  }
  return env;
}

}  // namespace flags2env
