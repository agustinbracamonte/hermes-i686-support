#include <sstream>
#include <string>

std::string source_location_string(const char* function_name,
                                   const char* file_name, int line) {
#if defined(HERMES_FORCE_NODE_I686_OSSTREAM_COMPAT) || \
    (defined(__i386__) && defined(__clang__))
  std::ostringstream stream;
  stream << function_name << '@' << file_name << ':' << line;
  return stream.str();
#else
  return (std::ostringstream{} << function_name << '@' << file_name << ':'
                               << line)
      .str();
#endif
}

int main() {
  return source_location_string("function", "file.cc", 27) ==
                 "function@file.cc:27"
             ? 0
             : 1;
}
